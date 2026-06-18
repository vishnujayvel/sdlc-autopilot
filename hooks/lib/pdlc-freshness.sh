#!/bin/bash
# hooks/lib/pdlc-freshness.sh — Context freshness checks
#
# Read-only Observer: detects stale spec artifacts, expired session state,
# and spec-code drift. Never blocks, never writes state.
#
# Primary signal: dates embedded in spec files (Created/last_updated fields)
# Fallback signal: file modification time (mtime) when dates unavailable
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-freshness.sh"
# Depends on: pdlc-state.sh (pdlc_get_field, pdlc_get_mtime)
#
# Host adapter / Ralph driver reuse:
# Example: pdlc_freshness_report (FRESH/STALE/DRIFT)
# (called in director prompts + context health for /goal + /loop)

set -euo pipefail

# Source state library if not already loaded
if ! declare -f pdlc_get_mtime &>/dev/null; then
  source "$(dirname "${BASH_SOURCE[0]}")/pdlc-state.sh"
fi

# Default freshness threshold in days
PDLC_FRESHNESS_THRESHOLD_DAYS="${PDLC_FRESHNESS_THRESHOLD_DAYS:-7}"

# Source directories to compare against for drift detection
# Override via env: PDLC_SOURCE_DIRS="hooks/ src/ tests/ lib/"
if [[ -z "${PDLC_SOURCE_DIRS+x}" ]]; then
  PDLC_SOURCE_DIRS=(hooks/ src/ tests/)
fi

# Extract a date from a spec file's header fields
# Looks for patterns like: **Created**: 2026-03-16 or **Last Updated**: 2026-03-17
# Usage: pdlc_freshness_extract_date <file> <field>
#   field: "created" or "last_updated"
# Output: date string (YYYY-MM-DD) or empty if not found
pdlc_freshness_extract_date() {
  local file="$1"
  local field="$2"

  if [[ ! -f "$file" ]]; then
    echo ""
    return 0
  fi

  local pattern
  case "$field" in
    created)
      pattern='^\*\*Created\*\*:'
      ;;
    last_updated)
      pattern='^\*\*Last Updated\*\*:'
      ;;
    *)
      echo ""
      return 0
      ;;
  esac

  # Extract YYYY-MM-DD from the matching line
  local date_str
  date_str=$(grep -i "$pattern" "$file" 2>/dev/null | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1) || true
  echo "$date_str"
}

# Convert a YYYY-MM-DD date to epoch seconds (portable)
# Usage: pdlc_freshness_date_to_epoch <date_str>
# Output: epoch seconds or empty if parse fails
pdlc_freshness_date_to_epoch() {
  local date_str="$1"
  if [[ -z "$date_str" ]]; then
    echo ""
    return 0
  fi
  # macOS: date -j -f, Linux: date -d
  local epoch
  epoch=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null) || \
  epoch=$(date -d "$date_str" +%s 2>/dev/null) || true
  echo "$epoch"
}

# Get the best available age of a spec artifact in days
# Priority: last_updated field > created field > file mtime
# Usage: pdlc_freshness_artifact_age <file>
# Output: age in days (integer) or empty if cannot determine
pdlc_freshness_artifact_age() {
  local file="$1"
  local now
  now=$(date +%s)

  # Try last_updated field first
  local date_str epoch
  date_str=$(pdlc_freshness_extract_date "$file" "last_updated")
  if [[ -n "$date_str" ]]; then
    epoch=$(pdlc_freshness_date_to_epoch "$date_str")
    if [[ -n "$epoch" ]]; then
      echo $(( (now - epoch) / 86400 ))
      return 0
    fi
  fi

  # Try created field
  date_str=$(pdlc_freshness_extract_date "$file" "created")
  if [[ -n "$date_str" ]]; then
    epoch=$(pdlc_freshness_date_to_epoch "$date_str")
    if [[ -n "$epoch" ]]; then
      echo $(( (now - epoch) / 86400 ))
      return 0
    fi
  fi

  # Fallback: file mtime
  local mtime
  mtime=$(pdlc_get_mtime "$file")
  if [[ -n "$mtime" ]]; then
    echo $(( (now - mtime) / 86400 ))
    return 0
  fi

  echo ""
}

# Check spec-code drift: are spec artifacts older than source files?
# Uses embedded dates when available, falls back to mtime
# Usage: pdlc_freshness_check_drift <spec_dir>
# Output: "DRIFT:spec_artifacts:N_days_behind" or "FRESH"
# Returns: 0 always (Observer — never fails)
pdlc_freshness_check_drift() {
  local spec_dir="$1"

  if [[ ! -d "$spec_dir" ]]; then
    echo "INFO:No spec directory found"
    return 0
  fi

  # Find the most recent spec artifact date (smallest age = newest)
  local spec_min_age=""
  local artifact
  for artifact in spec.md plan.md tasks.md; do
    local filepath="${spec_dir}/${artifact}"
    if [[ -f "$filepath" ]]; then
      local age
      age=$(pdlc_freshness_artifact_age "$filepath")
      if [[ -n "$age" ]]; then
        if [[ -z "$spec_min_age" ]] || [[ "$age" -lt "$spec_min_age" ]]; then
          spec_min_age="$age"
        fi
      fi
    fi
  done

  if [[ -z "$spec_min_age" ]]; then
    echo "INFO:No spec artifacts found"
    return 0
  fi

  # Find newest source file mtime (mtime is fine for source — they don't have date fields)
  local now source_min_age=""
  now=$(date +%s)
  local src_dir
  for src_dir in "${PDLC_SOURCE_DIRS[@]}"; do
    if [[ -d "$src_dir" ]]; then
      local file
      for file in "$src_dir"*; do
        [[ -f "$file" ]] || continue
        local mtime
        mtime=$(pdlc_get_mtime "$file")
        if [[ -n "$mtime" ]]; then
          local age=$(( (now - mtime) / 86400 ))
          if [[ -z "$source_min_age" ]] || [[ "$age" -lt "$source_min_age" ]]; then
            source_min_age="$age"
          fi
        fi
      done
    fi
  done

  if [[ -z "$source_min_age" ]]; then
    echo "FRESH"
    return 0
  fi

  # Drift: spec is older than source (spec age > source age)
  if [[ "$spec_min_age" -gt "$source_min_age" ]]; then
    local delta=$((spec_min_age - source_min_age))
    echo "DRIFT:spec_artifacts:${delta}_days_behind"
  else
    echo "FRESH"
  fi

  return 0
}

# Check session staleness: is HANDOFF.md older than threshold?
# Uses last_session_date field if available, falls back to mtime
# Usage: pdlc_freshness_check_session
# Output: "SESSION:FRESH:age_days" or "SESSION:STALE:age_days:threshold"
# Returns: 0 always (Observer — never fails)
pdlc_freshness_check_session() {
  local threshold="${PDLC_FRESHNESS_THRESHOLD_DAYS}"

  if [[ ! -f "${PDLC_HANDOFF}" ]]; then
    echo "SESSION:NONE:no_handoff"
    return 0
  fi

  local age_days=""

  # Try last_session_date field in HANDOFF.md
  local session_date
  session_date=$(pdlc_get_field "last_session_date")
  if [[ -n "$session_date" ]]; then
    local epoch
    epoch=$(pdlc_freshness_date_to_epoch "$session_date")
    if [[ -n "$epoch" ]]; then
      local now
      now=$(date +%s)
      age_days=$(( (now - epoch) / 86400 ))
    fi
  fi

  # Fallback: file mtime
  if [[ -z "$age_days" ]]; then
    local mtime
    mtime=$(pdlc_get_mtime "${PDLC_HANDOFF}")
    if [[ -z "$mtime" ]]; then
      echo "SESSION:NONE:cannot_determine_age"
      return 0
    fi
    local now
    now=$(date +%s)
    age_days=$(( (now - mtime) / 86400 ))
  fi

  if [[ "$age_days" -gt "$threshold" ]]; then
    echo "SESSION:STALE:${age_days}:${threshold}"
  else
    echo "SESSION:FRESH:${age_days}"
  fi

  return 0
}

# Produce consolidated freshness report
# Usage: pdlc_freshness_report <spec_dir>
# Output: multi-line report with per-artifact ages and overall status
# Returns: 0 always (Observer — never fails)
pdlc_freshness_report() {
  local spec_dir="$1"
  local overall="FRESH"

  echo "=== Context Freshness ==="

  # Per-artifact ages (using embedded dates with mtime fallback)
  local artifact
  for artifact in spec.md plan.md tasks.md; do
    local filepath="${spec_dir}/${artifact}"
    if [[ -f "$filepath" ]]; then
      local age_days
      age_days=$(pdlc_freshness_artifact_age "$filepath")
      if [[ -n "$age_days" ]]; then
        local status="FRESH"
        if [[ "$age_days" -gt "${PDLC_FRESHNESS_THRESHOLD_DAYS}" ]]; then
          status="STALE"
          overall="STALE"
        fi
        echo "${artifact}: ${age_days} days old [${status}]"
      else
        echo "${artifact}: age unknown"
      fi
    else
      echo "${artifact}: not found"
    fi
  done

  # Session check
  local session_result
  session_result=$(pdlc_freshness_check_session)
  echo "HANDOFF.md: ${session_result}"
  if echo "$session_result" | grep -q "STALE"; then
    overall="STALE"
  fi

  # Drift check
  local drift_result
  drift_result=$(pdlc_freshness_check_drift "$spec_dir")
  echo "Drift: ${drift_result}"
  if echo "$drift_result" | grep -q "DRIFT"; then
    overall="STALE"
  fi

  echo "Overall: ${overall}"
  return 0
}
