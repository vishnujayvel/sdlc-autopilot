#!/bin/bash
# hooks/lib/pdlc-session.sh — PDLC session persistence library
#
# Provides checkpoint save/restore for crash-resilient session recovery.
# Persists Director dispatch decisions, quality gate results, and iteration
# state to the HANDOFF.md body section.
#
# Host adapter / Ralph driver reuse:
# Source with pdlc-state; use to checkpoint before/after subagent dispatch in host outer loop. Same HANDOFF format across hosts.
# Example call sequence: pdlc_director_decide; if ! pdlc_resource_check ...; pdlc_director_evaluate_critics; ...; pdlc_session_save
# (portable for Ralph/loop/Grok/Cursor; see pdlc-outer-loop.sh + pdlc-goal.md)
#
# Two public functions:
#   pdlc_session_save  — writes checkpoint to HANDOFF.md body (atomic)
#   pdlc_session_restore — reads checkpoint from HANDOFF.md body
#
# Depends on: pdlc-state.sh (must be sourced first)

set -euo pipefail

# Source state library if not already loaded
if ! declare -f pdlc_get_field &>/dev/null; then
  PDLC_SESSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${PDLC_SESSION_LIB_DIR}/pdlc-state.sh"
fi

# Save session checkpoint to HANDOFF.md body section (atomic write).
#
# Appends/replaces a "### Session Checkpoint" section in the HANDOFF.md body
# with the current iteration's state. Uses pdlc_write_handoff for atomic
# tmp+mv writes.
#
# Usage: pdlc_session_save <iteration> <lifecycle_state> \
#            <director_decision> <actor_result> <critic_verdict>
#
# Arguments:
#   iteration         — current iteration number (integer)
#   lifecycle_state   — inferred lifecycle state (e.g., Implementing)
#   director_decision — "action|mode|rationale" string
#   actor_result      — summary of Actor outcome
#   critic_verdict    — accept, retry, or escalate
pdlc_session_save() {
  local iteration="$1"
  local lifecycle_state="$2"
  local director_decision="$3"
  local actor_result="$4"
  local critic_verdict="$5"

  if [[ ! -f "${PDLC_HANDOFF}" ]]; then
    return 0
  fi

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build quality line from frontmatter critic fields
  local batch quality_line
  batch=$(pdlc_get_field "batch")
  batch="${batch:-1}"
  local advocate skeptic
  advocate=$(pdlc_get_field "batch_${batch}_advocate")
  skeptic=$(pdlc_get_field "batch_${batch}_skeptic")
  if [[ -n "$advocate" || -n "$skeptic" ]]; then
    quality_line="advocate=${advocate:-N/A}, skeptic=${skeptic:-N/A}"
  else
    quality_line="N/A"
  fi

  local checkpoint_block
  checkpoint_block="### Session Checkpoint

- Iteration: ${iteration}
- Lifecycle: ${lifecycle_state}
- Director: ${director_decision}
- Actor: ${actor_result}
- Critic: ${critic_verdict}
- Quality: ${quality_line}
- Timestamp: ${timestamp}"

  # Extract frontmatter (without --- delimiters)
  local frontmatter
  frontmatter=$(awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm { print }
  ' "${PDLC_HANDOFF}")

  # Extract body (everything after second ---)
  local body
  body=$(awk '
    BEGIN { in_fm=0; past=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { past=1; next }
    past { print }
  ' "${PDLC_HANDOFF}")

  # Remove existing checkpoint section from body
  local cleaned_body
  cleaned_body=$(printf '%s\n' "$body" | awk '
    /^### Session Checkpoint/ { skip=1; next }
    skip && /^###? / { skip=0 }
    !skip { print }
  ')

  # Trim trailing blank lines from cleaned body (awk for macOS compat)
  cleaned_body=$(printf '%s\n' "$cleaned_body" | awk '
    { lines[NR] = $0; last = NR }
    END {
      while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = 1; i <= last; i++) print lines[i]
    }
  ')

  # Build new body: cleaned body + checkpoint block
  local new_body
  if [[ -n "$cleaned_body" ]]; then
    new_body="${cleaned_body}

${checkpoint_block}"
  else
    new_body="${checkpoint_block}"
  fi

  # Atomic write via pdlc_write_handoff
  pdlc_write_handoff "$frontmatter" "$new_body"
}

# Restore session checkpoint from HANDOFF.md body section.
#
# Reads the "### Session Checkpoint" section and outputs the checkpoint
# fields as key-value lines suitable for inclusion in Director prompts.
#
# Usage: pdlc_session_restore
# Output: checkpoint lines (one per line, "- Key: value" format) or empty
# Returns: 0 always
pdlc_session_restore() {
  if [[ ! -f "${PDLC_HANDOFF}" ]]; then
    echo ""
    return 0
  fi

  # Extract lines between "### Session Checkpoint" and next heading (or EOF)
  awk '
    /^### Session Checkpoint/ { found=1; next }
    found && /^###? / { exit }
    found && /^- / { print }
  ' "${PDLC_HANDOFF}"
}

# Get a specific field from the restored checkpoint.
#
# Usage: pdlc_session_get_checkpoint_field "Iteration"
# Output: the field value (e.g., "5") or empty
pdlc_session_get_checkpoint_field() {
  local field="$1"
  local restored
  restored=$(pdlc_session_restore)
  if [[ -z "$restored" ]]; then
    echo ""
    return 0
  fi
  echo "$restored" | awk -F': ' -v key="$field" '$0 ~ "^- " key ": " { print substr($0, length(key)+5); exit }'
}
