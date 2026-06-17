#!/bin/bash
# =============================================================================
# pdlc-stop-check.sh — PDLC Autopilot Stop Guard
# =============================================================================
#
# Prevents Claude Code from exiting when PDLC tasks are still incomplete.
# Install this as a "Stop" hook in your .claude/settings.json to keep the
# autopilot loop running until all tasks are done.
#
# When a spec is stale (no files modified in PDLC_STALE_DAYS), the hook
# warns but allows exit instead of blocking — stale specs should not trap
# Claude in an infinite loop.
#
# Portable-friendly: drives decisions primarily from spec.json (phase,
# updated_at, created_at, active_workflow) so future core owns the state.
# Supports explicit terminal phases and archive/ layout for lifecycle.
#
# HOW IT WORKS
# ─────────────
# 1. Locates the active spec dir under .claude/specs/ (skips archive/ and
#    specs with phase=complete|archived in spec.json) by matching
#    active_workflow == "pdlc-autopilot" (via spec.json)
# 2. Reads tasks.md from that spec directory; counts pending "- [ ]"
# 3. Computes last-active using MULTIPLE SIGNALS (max wins, new-design friendly):
#      - tasks.md mtime, spec.json mtime
#      - spec.json updated_at / created_at (parsed)
#      - HANDOFF.md mtime (if references the spec)
#      - git log last commit on the spec dir (if available)
# 4. Staleness threshold: PDLC_STALE_DAYS (default 3)
#    Fresh (< threshold): block on pending (exit 1) unless safety
#    Stale (>= threshold): warn with timeline context + allow (exit 0)
# 5. Always includes timeline (dates + "X days ago") in messages.
# 6. Explicit lifecycle (phase complete/archived or archive/ dir) => skip entirely (allow)
#
# INSTALLATION
# ─────────────
# Add to .claude/settings.json under "hooks.Stop":
#
#   {
#     "hooks": {
#       "Stop": [{
#         "hooks": [{
#           "type": "command",
#           "command": "bash /path/to/pdlc-stop-check.sh"
#         }]
#       }]
#     }
#   }
#
# ENVIRONMENT VARIABLES
# ─────────────────────
#   PDLC_MAX_CONTINUES  — Max times to block exit (default: 50).
#                          Safety valve to prevent infinite loops.
#   PDLC_COUNTER_FILE   — Path to the continue counter file.
#                          Default: /tmp/pdlc-stop-counter-$USER
#   PDLC_STALE_DAYS     — Days since last active signal before
#                          considering a spec stale (default: 3).
#                          Stale specs warn (with dates) but do not block exit.
#                          Fresh specs with pending tasks block exit.
#
# EXIT CODES
# ──────────
#   0 — Allow stop (all tasks complete, no tasks file, safety limit hit,
#        or spec is stale / explicitly complete / archived / under archive/)
#   1 — Block stop (incomplete tasks remain and spec is fresh)
#
# =============================================================================

set -eo pipefail
# Note: -u (nounset) deliberately omitted — it bypasses the ERR trap
# and can cause non-zero exit, violating the fail-open guarantee.
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/pdlc-state.sh"

# Bypass for PDLC self-development (bootstrapping circularity)
if [[ "${PDLC_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

# --- Configuration ---
MAX_CONTINUES="${PDLC_MAX_CONTINUES:-50}"
COUNTER_FILE="${PDLC_COUNTER_FILE:-/tmp/pdlc-stop-counter-${USER:-unknown}}"
STALE_DAYS="${PDLC_STALE_DAYS:-3}"
PROJECT_DIR="${PWD}"

# --- Find active spec directory ---
# Portable: prefers spec.json fields for active_workflow + phase.
# Skips archive/ layout and terminal phases (complete/archived) per AC.
find_active_spec() {
  local specs_dir="${PROJECT_DIR}/.claude/specs"

  if [[ ! -d "$specs_dir" ]]; then
    return 1
  fi

  for spec_json in "$specs_dir"/*/spec.json; do
    [[ -f "$spec_json" ]] || continue

    local spec_d
    spec_d="$(dirname "$spec_json")"

    # Skip archived layout (explicit dir or any nested under archive/)
    if [[ "$spec_d" == */archive/* || "$(basename "$spec_d")" == "archive" ]]; then
      continue
    fi

    # Skip explicit terminal lifecycle in spec.json (portable, future core owned)
    local phase
    phase="$(pdlc_get_spec_json_field "$spec_d" "phase")"
    case "$phase" in
      complete|archived|Complete|Archived) continue ;;
    esac

    # Check active_workflow via parsed field (not loose grep)
    local wf
    wf="$(pdlc_get_spec_json_field "$spec_d" "active_workflow")"
    if [[ "$wf" == "pdlc-autopilot" ]]; then
      echo "$spec_d"
      return 0
    fi
  done

  return 1
}

# --- Count pending tasks ---
count_pending_tasks() {
  local tasks_file="$1"

  if [[ ! -f "$tasks_file" ]]; then
    echo "0"
    return
  fi

  # Count unchecked markdown checkboxes: "- [ ]"
  # grep -c exits non-zero when count is 0; capture to avoid || adding a second "0"
  local count
  count="$(grep -c '^\s*- \[ \]' "$tasks_file" 2>/dev/null)" || true
  echo "${count:-0}"
}

# --- Staleness / last-active (multiple signals, portable via spec.json) ---
# get_spec_last_active_epoch: returns the most recent epoch across signals.
# Signals (max wins; designed so future spec.json dates can drive):
#   tasks.md mtime, spec.json mtime, spec.json updated_at/created_at,
#   HANDOFF mtime (when it references the spec), git log -- %ct on dir.
get_spec_last_active_epoch() {
  local spec_dir="$1"
  local latest=0
  local m t

  # tasks.md mtime (primary work artifact)
  m="$(pdlc_get_mtime "${spec_dir}/tasks.md" 2>/dev/null || true)"
  if [[ -n "$m" ]] && [[ "$m" -gt "$latest" ]]; then
    latest="$m"
  fi

  # spec.json mtime
  m="$(pdlc_get_mtime "${spec_dir}/spec.json" 2>/dev/null || true)"
  if [[ -n "$m" ]] && [[ "$m" -gt "$latest" ]]; then
    latest="$m"
  fi

  # Prefer explicit dates from spec.json (new-design friendly)
  local ua ca
  ua="$(pdlc_get_spec_json_field "$spec_dir" "updated_at")"
  if [[ -n "$ua" ]]; then
    t="$(pdlc_date_to_epoch "$ua")"
    if [[ -n "$t" ]] && [[ "$t" -gt "$latest" ]]; then
      latest="$t"
    fi
  fi
  ca="$(pdlc_get_spec_json_field "$spec_dir" "created_at")"
  if [[ -n "$ca" ]]; then
    t="$(pdlc_date_to_epoch "$ca")"
    if [[ -n "$t" ]] && [[ "$t" -gt "$latest" ]]; then
      latest="$t"
    fi
  fi

  # HANDOFF mtime (cross-session activity) if it seems to reference this spec
  if [[ -f "${PDLC_HANDOFF:-.pdlc/state/HANDOFF.md}" ]]; then
    local sd
    sd="$(pdlc_get_field "spec_dir" 2>/dev/null || true)"
    if [[ -n "$sd" && ( "$sd" == *"${spec_dir##*/}"* || "$sd" == "$spec_dir" ) ]]; then
      m="$(pdlc_get_mtime "${PDLC_HANDOFF:-.pdlc/state/HANDOFF.md}" 2>/dev/null || true)"
      if [[ -n "$m" ]] && [[ "$m" -gt "$latest" ]]; then
        latest="$m"
      fi
    fi
  fi

  # Git commit time on the spec dir (if repo + history)
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    t="$(git log -1 --format=%ct -- "$spec_dir" 2>/dev/null || true)"
    if [[ -n "$t" ]] && [[ "$t" -gt "$latest" ]]; then
      latest="$t"
    fi
  fi

  echo "$latest"
}

# is_spec_stale: returns 0 (stale) if last active age >= STALE_DAYS, else 1 (fresh).
# Uses multi-signal last active (improved).
is_spec_stale() {
  local spec_dir="$1"
  local stale_days="$2"
  local last
  last="$(get_spec_last_active_epoch "$spec_dir")"
  if [[ -z "$last" || "$last" -eq 0 ]]; then
    return 0  # no signals: treat as stale (safe, allow exit)
  fi

  local now
  now="$(date +%s)"
  local threshold=$(( stale_days * 86400 ))
  local age=$(( now - last ))
  if [[ "$age" -ge "$threshold" ]]; then
    return 0
  fi
  return 1
}

# --- Timeline helpers for rich messages (dates + X days ago) ---
get_spec_created_epoch() {
  local spec_dir="$1"
  local c
  c="$(pdlc_get_spec_json_field "$spec_dir" "created_at")"
  local e
  e="$(pdlc_date_to_epoch "$c")"
  if [[ -n "$e" ]]; then
    echo "$e"
    return 0
  fi
  # fallback to spec.json mtime or tasks mtime
  e="$(pdlc_get_mtime "${spec_dir}/spec.json" 2>/dev/null || true)"
  if [[ -n "$e" ]]; then
    echo "$e"
    return 0
  fi
  e="$(pdlc_get_mtime "${spec_dir}/tasks.md" 2>/dev/null || true)"
  echo "${e:-0}"
}

get_days_ago_str() {
  local epoch="$1"
  local now
  now="$(date +%s)"
  if [[ -z "$epoch" || "$epoch" -eq 0 ]]; then
    echo "?"
    return 0
  fi
  local d=$(( (now - epoch) / 86400 ))
  echo "$d"
}

# --- Safety counter ---
read_counter() {
  if [[ -f "$COUNTER_FILE" ]]; then
    cat "$COUNTER_FILE" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

increment_counter() {
  local current
  current="$(read_counter)"
  echo $(( current + 1 )) > "$COUNTER_FILE"
}

reset_counter() {
  rm -f "$COUNTER_FILE" 2>/dev/null
}

# --- Main logic ---
main() {
  # Find the active PDLC spec
  local spec_dir
  spec_dir="$(find_active_spec)" || {
    # No active PDLC workflow — allow stop
    reset_counter
    exit 0
  }

  local tasks_file="${spec_dir}/tasks.md"
  local pending
  pending="$(count_pending_tasks "$tasks_file")"

  # All tasks complete — allow stop
  if [[ "$pending" -eq 0 ]]; then
    reset_counter
    exit 0
  fi

  # Compute timeline context (always; for both stale and blocking cases)
  local now last_epoch last_date created_epoch created_date tasks_mtime tasks_date age_days tasks_age_days spec_name
  now="$(date +%s)"
  last_epoch="$(get_spec_last_active_epoch "$spec_dir")"
  last_date="$(pdlc_epoch_to_date_str "$last_epoch")"
  age_days="$(get_days_ago_str "$last_epoch")"
  created_epoch="$(get_spec_created_epoch "$spec_dir")"
  created_date="$(pdlc_epoch_to_date_str "$created_epoch")"
  tasks_mtime="$(pdlc_get_mtime "$tasks_file" 2>/dev/null || true)"
  tasks_date="$(pdlc_epoch_to_date_str "$tasks_mtime")"
  tasks_age_days="$(get_days_ago_str "$tasks_mtime")"
  spec_name="$(basename "$spec_dir")"

  local timeline
  timeline="  Spec created: ${created_date:-unknown} | Last updated: ${last_date:-unknown} (${age_days} days ago)
  tasks.md last modified: ${tasks_date:-unknown} (${tasks_age_days} days ago)"

  # Check staleness — stale specs (or archived etc) warn but allow exit (fresh = block)
  if is_spec_stale "$spec_dir" "$STALE_DAYS"; then
    echo "PDLC Stop Guard: ${pending} tasks still pending in ${spec_name}" >&2
    echo "${timeline}" >&2
    echo "  Tip: Archive stale specs with: mv .claude/specs/${spec_name} .claude/specs/archive/" >&2
    reset_counter
    exit 0
  fi

  # Check safety limit
  local counter
  counter="$(read_counter)"

  if [[ "$counter" -ge "$MAX_CONTINUES" ]]; then
    echo "PDLC Stop Guard: Safety limit reached (${MAX_CONTINUES} continues)." >&2
    echo "  ${pending} tasks still pending in ${spec_name}. Allowing exit to prevent infinite loop." >&2
    echo "${timeline}" >&2
    reset_counter
    exit 0
  fi

  # Block exit — tasks remain AND spec is fresh (within STALE_DAYS)
  increment_counter
  echo "PDLC Stop Guard: ${pending} tasks still pending in ${spec_name}" >&2
  echo "${timeline}" >&2
  echo "  Continue #$(( counter + 1 ))/${MAX_CONTINUES}. Complete remaining tasks before stopping." >&2
  exit 1
}

main "$@"
