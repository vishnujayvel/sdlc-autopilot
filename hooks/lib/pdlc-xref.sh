#!/bin/bash
# hooks/lib/pdlc-xref.sh — Cross-reference consistency checker
#
# Checks bidirectional references between spec.md and tasks.md:
# - Every FR-XXX in spec.md should be referenced in tasks.md
# - Every US-XXX in tasks.md should resolve to a user story in spec.md
#
# Host adapter / Ralph driver reuse:
# Example call sequence for host /loop or Ralph driver:
#   pdlc_xref_extract_ids / pdlc_xref_check
#   (used in critic advocate + semantic for portable core; Ralph/loop/Grok/Cursor reuse)
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-xref.sh"
# Depends on: pdlc-state.sh (for pdlc_get_field)

set -euo pipefail

# Source state library if not already loaded
if ! declare -f pdlc_get_field &>/dev/null; then
  source "$(dirname "${BASH_SOURCE[0]}")/pdlc-state.sh"
fi

# Generic ID extractor: extract all PREFIX-NNN IDs from a file
# Usage: pdlc_xref_extract_ids <file> <prefix>
# Output: sorted unique list of PREFIX-NNN IDs, one per line
pdlc_xref_extract_ids() {
  local file="$1"
  local prefix="$2"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  awk -v pfx="$prefix" '{
    pat = pfx "-[0-9]+"
    while (match($0, pat)) {
      print substr($0, RSTART, RLENGTH)
      $0 = substr($0, RSTART + RLENGTH)
    }
  }' "$file" | sort -u
}

# Extract all FR-XXX IDs from a file
# Usage: pdlc_xref_extract_fr_ids <file>
# Output: sorted unique list of FR-XXX IDs, one per line
pdlc_xref_extract_fr_ids() {
  pdlc_xref_extract_ids "$1" "FR"
}

# Extract all US-XXX IDs from a file (from section headers)
# Usage: pdlc_xref_extract_us_ids <file>
# Output: sorted unique list of US-XXX IDs, one per line
pdlc_xref_extract_us_ids() {
  pdlc_xref_extract_ids "$1" "US"
}

# Check cross-reference consistency between spec.md and tasks.md
# Usage: pdlc_xref_check <spec_dir>
# Returns: 0 if all references resolve, 1 if gaps found
# When PDLC_DISABLED=1, still checks but always returns 0 (non-blocking)
pdlc_xref_check() {
  local spec_dir="$1"
  local spec_file="${spec_dir}/spec.md"
  local tasks_file="${spec_dir}/tasks.md"
  local gaps=""
  local gap_count=0

  # Skip gracefully if spec.md doesn't exist
  if [[ ! -f "$spec_file" ]]; then
    echo "INFO: spec.md not found, skipping cross-reference check" >&2
    return 0
  fi

  # Skip gracefully if tasks.md doesn't exist
  if [[ ! -f "$tasks_file" ]]; then
    echo "INFO: tasks.md not found, skipping cross-reference check" >&2
    return 0
  fi

  # Check FR coverage: every FR in spec.md should appear in tasks.md
  local spec_frs tasks_frs
  spec_frs=$(pdlc_xref_extract_fr_ids "$spec_file") || true
  tasks_frs=$(pdlc_xref_extract_fr_ids "$tasks_file") || true

  local fr
  while IFS= read -r fr; do
    [[ -z "$fr" ]] && continue
    if ! echo "$tasks_frs" | grep -q "^${fr}$"; then
      gaps="${gaps}UNREFERENCED:${fr}:Not found in tasks.md"$'\n'
      gap_count=$((gap_count + 1))
    fi
  done <<< "$spec_frs"

  # Check US references: every US in tasks.md should exist in spec.md
  local tasks_us spec_us
  tasks_us=$(pdlc_xref_extract_us_ids "$tasks_file") || true
  spec_us=$(pdlc_xref_extract_us_ids "$spec_file") || true

  local us
  while IFS= read -r us; do
    [[ -z "$us" ]] && continue
    if ! echo "$spec_us" | grep -q "^${us}$"; then
      gaps="${gaps}ORPHANED:${us}:Referenced in tasks.md but not found in spec.md"$'\n'
      gap_count=$((gap_count + 1))
    fi
  done <<< "$tasks_us"

  if [[ $gap_count -gt 0 ]]; then
    echo "$gaps" | sed '/^$/d'
    echo "Cross-reference gaps: $gap_count" >&2
    # PDLC_DISABLED=1: still check (report gaps) but always return 0 (non-blocking)
    if [[ "${PDLC_DISABLED:-0}" == "1" ]]; then
      return 0
    fi
    return 1
  else
    echo "All cross-references resolve" >&2
    return 0
  fi
}
