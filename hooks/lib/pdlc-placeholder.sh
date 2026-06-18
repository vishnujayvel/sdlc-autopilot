#!/bin/bash
# hooks/lib/pdlc-placeholder.sh — Placeholder detection scanner
#
# Scans spec artifacts for template markers, unresolved clarifications,
# and action-required comments. Reports findings with file:line:type:match format.
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-placeholder.sh"
#
# Host adapter / Ralph driver reuse:
# Example: pdlc_placeholder_scan / pdlc_placeholder_check
# (used in critic advocate + final validator)

set -euo pipefail

# Placeholder patterns to detect (grep -E compatible)
# Each entry: "TYPE|PATTERN"
PDLC_PLACEHOLDER_PATTERNS=(
  "CLARIFICATION|\\[NEEDS CLARIFICATION:"
  "TEMPLATE|\\[[A-Z][A-Z _-]{4,}\\]"
  "ACTION_REQUIRED|ACTION REQUIRED:"
  "TODO|\\[TODO:"
)

# Scan a single file for placeholder patterns
# Usage: pdlc_placeholder_scan <file>
# Output: file:line:type:match (one per line)
# Returns: 0 always (findings go to stdout)
pdlc_placeholder_scan() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  local entry pattern type line_num line_content
  for entry in "${PDLC_PLACEHOLDER_PATTERNS[@]}"; do
    type="${entry%%|*}"
    pattern="${entry#*|}"

    # Use grep -n to get line numbers, then filter exclusions
    grep -n -E "$pattern" "$file" 2>/dev/null | while IFS=: read -r line_num line_content; do
      # Exclusion: markdown checkboxes [x], [ ], [-] — only for TEMPLATE pattern
      if [[ "$type" == "TEMPLATE" ]] && echo "$line_content" | grep -qE '^\s*- \[(x| |-)\]'; then
        continue
      fi
      # Exclusion: markdown links [text](url) — skip if bracket is followed by (
      if [[ "$type" == "TEMPLATE" ]] && echo "$line_content" | grep -qE '\[[A-Z][A-Z _-]{2,}\]\('; then
        continue
      fi
      # Exclusion: markdown images ![alt](url)
      if [[ "$type" == "TEMPLATE" ]] && echo "$line_content" | grep -qE '!\[[A-Z][A-Z _-]{2,}\]\('; then
        continue
      fi
      # Exclusion: [P] parallelism marker
      if [[ "$type" == "TEMPLATE" ]] && echo "$line_content" | grep -qE '\[P\]'; then
        # Check if the only template match is [P] itself
        local without_p
        without_p=$(echo "$line_content" | sed 's/\[P\]//g')
        if ! echo "$without_p" | grep -qE '\[[A-Z][A-Z _-]{2,}\]'; then
          continue
        fi
      fi
      # Exclusion: [US1], [US2], etc. story markers
      if [[ "$type" == "TEMPLATE" ]]; then
        local without_us
        without_us=$(echo "$line_content" | sed -E 's/\[US[0-9]+\]//g')
        if ! echo "$without_us" | grep -qE '\[[A-Z][A-Z _-]{2,}\]'; then
          continue
        fi
      fi

      echo "$file:$line_num:$type:$line_content"
    done || true
  done
}

# Check all spec artifacts in a directory for placeholders
# Usage: pdlc_placeholder_check <spec_dir>
# Returns: 0 if clean, 1 if placeholders found
# When PDLC_DISABLED=1, still scans but always returns 0 (non-blocking)
pdlc_placeholder_check() {
  local spec_dir="$1"
  local findings=""
  local count=0

  local artifact
  for artifact in spec.md plan.md tasks.md; do
    local filepath="${spec_dir}/${artifact}"
    if [[ -f "$filepath" ]]; then
      local result
      result=$(pdlc_placeholder_scan "$filepath") || true
      if [[ -n "$result" ]]; then
        findings="${findings}${result}"$'\n'
        count=$((count + $(echo "$result" | wc -l | tr -d ' ')))
      fi
    fi
  done

  if [[ $count -gt 0 ]]; then
    echo "$findings" | sed '/^$/d'
    echo "Placeholders found: $count" >&2
    # PDLC_DISABLED=1: still scan (report findings) but always return 0 (non-blocking)
    if [[ "${PDLC_DISABLED:-0}" == "1" ]]; then
      return 0
    fi
    return 1
  else
    echo "No placeholders found" >&2
    return 0
  fi
}
