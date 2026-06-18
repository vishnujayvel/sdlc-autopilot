#!/bin/bash
# hooks/lib/pdlc-lifecycle.sh — Spec lifecycle state machine
#
# Implements the 7-state lifecycle verified by Alloy (formal/pdlc-primitives.als):
#   Draft → Specified → Planned → Tasked → Implementing → Complete → Archived
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-lifecycle.sh"
# Depends on: pdlc-state.sh (pdlc_get_field, pdlc_set_field)
#
# Host adapter / Ralph driver reuse:
# Example: pdlc_lifecycle_infer + pdlc_lifecycle_transition
# (used in outer-loop + director for phase decisions)

set -euo pipefail

# Source state library if not already loaded
if ! declare -f pdlc_get_field &>/dev/null; then
  source "$(dirname "${BASH_SOURCE[0]}")/pdlc-state.sh"
fi

# The 7 valid lifecycle states in transition order
PDLC_LIFECYCLE_STATES=(Draft Specified Planned Tasked Implementing Complete Archived)

# Validate a lifecycle state value
# Returns 0 if valid, 1 if invalid
pdlc_lifecycle_validate() {
  local state="$1"
  local s
  for s in "${PDLC_LIFECYCLE_STATES[@]}"; do
    if [[ "$s" == "$state" ]]; then
      return 0
    fi
  done
  return 1
}

# Get current lifecycle state from HANDOFF.md
# Returns Draft if field is missing or empty
pdlc_lifecycle_get() {
  local state
  state=$(pdlc_get_field "spec_lifecycle")
  if [[ -z "$state" ]]; then
    echo "Draft"
  else
    echo "$state"
  fi
}

# Check if current state matches the given state
# Returns 0 if match, 1 if not
pdlc_lifecycle_is() {
  local expected="$1"
  local current
  current=$(pdlc_lifecycle_get)
  [[ "$current" == "$expected" ]]
}

# Check if lifecycle can advance (not Archived)
# Returns 0 if can advance, 1 if Archived (terminal)
pdlc_lifecycle_can_advance() {
  local current
  current=$(pdlc_lifecycle_get)
  [[ "$current" != "Archived" ]]
}

# Transition to a new lifecycle state
# Only allows transition to immediate successor (index + 1)
# Returns 0 on success, 1 on invalid transition
# Bypassed when PDLC_DISABLED=1 (always succeeds, writes state directly)
pdlc_lifecycle_transition() {
  local target="$1"

  if [[ "${PDLC_DISABLED:-0}" == "1" ]]; then
    pdlc_set_field "spec_lifecycle" "$target"
    echo "Lifecycle: → $target (PDLC_DISABLED bypass)" >&2
    return 0
  fi

  # Validate target
  if ! pdlc_lifecycle_validate "$target"; then
    echo "ERROR: Invalid lifecycle state: $target" >&2
    return 1
  fi

  local current
  current=$(pdlc_lifecycle_get)

  # Find current index
  local current_idx=-1
  local target_idx=-1
  local i
  for i in "${!PDLC_LIFECYCLE_STATES[@]}"; do
    if [[ "${PDLC_LIFECYCLE_STATES[$i]}" == "$current" ]]; then
      current_idx=$i
    fi
    if [[ "${PDLC_LIFECYCLE_STATES[$i]}" == "$target" ]]; then
      target_idx=$i
    fi
  done

  # Verify target is immediate successor
  local expected_idx=$((current_idx + 1))
  if [[ $target_idx -ne $expected_idx ]]; then
    echo "ERROR: Invalid transition $current → $target (expected ${PDLC_LIFECYCLE_STATES[$expected_idx]:-none})" >&2
    return 1
  fi

  # Write new state
  pdlc_set_field "spec_lifecycle" "$target"
  echo "Lifecycle: $current → $target" >&2
  return 0
}

# Infer lifecycle state from spec directory artifacts
# Usage: pdlc_lifecycle_infer <spec_dir>
# Output: one of the 7 lifecycle states
# Priority: Archived (explicit) > Complete > Implementing > Tasked > Planned > Specified > Draft
pdlc_lifecycle_infer() {
  local spec_dir="$1"

  # Check for explicit Archived in HANDOFF.md (cannot be inferred from artifacts)
  local handoff_state
  handoff_state=$(pdlc_get_field "spec_lifecycle")
  if [[ "$handoff_state" == "Archived" ]]; then
    echo "Archived"
    return 0
  fi

  # Check tasks.md for implementation state
  local tasks_file="${spec_dir}/tasks.md"
  if [[ -f "$tasks_file" ]]; then
    local total_tasks done_tasks pending_tasks
    total_tasks=$(pdlc_count_tasks "$tasks_file" "total")
    done_tasks=$(pdlc_count_tasks "$tasks_file" "done")
    pending_tasks=$(pdlc_count_tasks "$tasks_file" "pending")

    # Guard: empty tasks.md (no checklist items) — fall through to Planned/Specified/Draft
    if [[ $total_tasks -eq 0 ]]; then
      : # fall through — treat as if tasks.md doesn't exist
    elif [[ $pending_tasks -eq 0 ]]; then
      echo "Complete"
      return 0
    elif [[ $done_tasks -gt 0 ]]; then
      echo "Implementing"
      return 0
    else
      # tasks.md exists with tasks but none done
      echo "Tasked"
      return 0
    fi
  fi

  # Check plan.md
  if [[ -f "${spec_dir}/plan.md" ]]; then
    echo "Planned"
    return 0
  fi

  # Check spec.md
  if [[ -f "${spec_dir}/spec.md" ]]; then
    # Source placeholder library if available
    if ! declare -f pdlc_placeholder_scan &>/dev/null; then
      local lib_dir
      lib_dir="$(dirname "${BASH_SOURCE[0]}")"
      if [[ -f "${lib_dir}/pdlc-placeholder.sh" ]]; then
        source "${lib_dir}/pdlc-placeholder.sh"
      fi
    fi

    # Check for placeholders in spec.md only — if present, still Draft
    if declare -f pdlc_placeholder_scan &>/dev/null; then
      local scan_result
      scan_result=$(pdlc_placeholder_scan "${spec_dir}/spec.md")
      if [[ -z "$scan_result" ]]; then
        # No placeholders — spec is complete
        echo "Specified"
        return 0
      else
        # Has placeholders — still Draft
        echo "Draft"
        return 0
      fi
    fi

    # Fallback if placeholder library not available
    echo "Specified"
    return 0
  fi

  # Nothing exists
  echo "Draft"
  return 0
}
