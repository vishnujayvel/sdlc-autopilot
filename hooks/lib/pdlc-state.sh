#!/bin/bash
# hooks/lib/pdlc-state.sh — PDLC state management library
# Sourced by hook scripts: source "$(dirname "$0")/lib/pdlc-state.sh"
#
# Provides helpers for reading/writing HANDOFF.md with flat YAML frontmatter.
# All YAML fields are flat (no nesting). Atomic writes via tmp+mv.
#
# Host adapter / Ralph driver reuse:
# Example call sequence for host /loop or Ralph driver:
#   pdlc_get_field / pdlc_set_field (for HANDOFF state)
#   pdlc_count_tasks (for pending work)
#   (used by director + outer for portable core)

PDLC_STATE_DIR=".pdlc/state"
PDLC_HANDOFF="${PDLC_STATE_DIR}/HANDOFF.md"
PDLC_MARKER="${PDLC_STATE_DIR}/.compact_marker"

# Ensure state directory exists
pdlc_ensure_state_dir() {
  mkdir -p "${PDLC_STATE_DIR}"
}

# Read a flat YAML frontmatter field from HANDOFF.md
# Usage: pdlc_get_field "phase"  →  returns "ACTOR"
# Returns empty string if file or field does not exist.
pdlc_get_field() {
  local field="$1"
  if [[ ! -f "${PDLC_HANDOFF}" ]]; then
    echo ""
    return 0
  fi
  # Extract frontmatter between first pair of --- delimiters
  # Guard: if no closing --- exists, awk stops at EOF (safe — no bleed into body)
  local frontmatter
  frontmatter=$(awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm { print }
  ' "${PDLC_HANDOFF}")
  if [[ -z "${frontmatter}" ]]; then
    echo ""
    return 0
  fi
  # Single awk pass: match exact field name, print value, exit
  echo "${frontmatter}" | awk -F': ' -v key="${field}" '$1 == key { print substr($0, length(key)+3); exit }'
}

# Write HANDOFF.md atomically (write to .tmp, then mv)
# Usage: pdlc_write_handoff "$yaml_content" "$markdown_body"
# $yaml_content should be the raw YAML lines (without --- delimiters).
# $markdown_body is the markdown content after the frontmatter.
pdlc_write_handoff() {
  local yaml_content="$1"
  local markdown_body="${2:-}"
  pdlc_ensure_state_dir
  local tmp="${PDLC_HANDOFF}.tmp.$$"
  {
    echo "---"
    echo "${yaml_content}"
    echo "---"
    if [[ -n "${markdown_body}" ]]; then
      echo ""
      echo "${markdown_body}"
    fi
  } > "${tmp}"
  mv "${tmp}" "${PDLC_HANDOFF}"
}

# Update a single field in existing HANDOFF.md (atomic)
# If the field exists, replace its value. If not, append it to frontmatter.
# If HANDOFF.md does not exist, create it with just that field.
# Usage: pdlc_set_field "phase" "DONE"
pdlc_set_field() {
  local field="$1"
  local value="$2"
  if [[ ! -f "${PDLC_HANDOFF}" ]]; then
    pdlc_write_handoff "${field}: ${value}" ""
    return 0
  fi

  # Guard: if file has fewer than 2 frontmatter delimiters or first line isn't ---, treat as malformed — recreate with field + existing content as body
  local fm_delims
  fm_delims=$(grep -c '^---[[:space:]]*$' "${PDLC_HANDOFF}" 2>/dev/null || true)
  if [[ "${fm_delims}" -lt 2 ]] || ! head -n1 "${PDLC_HANDOFF}" | grep -q '^---[[:space:]]*$'; then
    local existing_content
    existing_content=$(cat "${PDLC_HANDOFF}")
    pdlc_write_handoff "${field}: ${value}" "${existing_content}"
    return 0
  fi

  local tmp="${PDLC_HANDOFF}.tmp.$$"
  local found=0
  local in_fm=0
  local fm_count=0
  local past_fm=0
  # Process line by line, preserving everything
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${past_fm}" -eq 1 ]]; then
      echo "${line}"
      continue
    fi
    if [[ "${line}" =~ ^---[[:space:]]*$ ]]; then
      fm_count=$((fm_count + 1))
      if [[ ${fm_count} -eq 1 ]]; then
        in_fm=1
        echo "${line}"
        continue
      else
        # Closing delimiter — insert field if not found yet
        if [[ ${found} -eq 0 ]]; then
          echo "${field}: ${value}"
        fi
        echo "${line}"
        in_fm=0
        past_fm=1
        continue
      fi
    fi
    # Only match within frontmatter; exact field name match
    if [[ ${in_fm} -eq 1 ]] && [[ "${line%%:*}" == "${field}" ]]; then
      echo "${field}: ${value}"
      found=1
    else
      echo "${line}"
    fi
  done < "${PDLC_HANDOFF}" > "${tmp}"

  # Guard: if only opening --- found (no closing), the tmp file may be incomplete
  # In this case, still mv — the field was either found and replaced or appended
  mv "${tmp}" "${PDLC_HANDOFF}"
}

# Read a field from JSON on stdin via jq
# Usage: local prompt=$(pdlc_read_json_field "tool_input.prompt" <<< "$stdin_json")
pdlc_read_json_field() {
  local field_path="$1"
  jq -r ".${field_path} // empty"
}

# Touch compact marker
pdlc_touch_marker() {
  pdlc_ensure_state_dir
  touch "${PDLC_MARKER}"
}

# Check if marker exists (returns 0 if exists, 1 otherwise)
pdlc_marker_exists() {
  [[ -f "${PDLC_MARKER}" ]]
}

# Delete marker
pdlc_delete_marker() {
  rm -f "${PDLC_MARKER}"
}

# Count tasks in a tasks.md file
# Usage: pdlc_count_tasks <file> <what>
#   what: "total" | "done" | "pending"
# Returns the count as a string
pdlc_count_tasks() {
  local file="$1"
  local what="${2:-total}"
  if [[ ! -f "$file" ]]; then echo "0"; return 0; fi
  local total done
  total=$(grep -c '^\- \[' "$file" 2>/dev/null || true)
  total="${total:-0}"
  total="${total//[[:space:]]/}"
  done=$(grep -c '^\- \[[xX]\]' "$file" 2>/dev/null || true)
  done="${done:-0}"
  done="${done//[[:space:]]/}"
  case "$what" in
    total) echo "$total" ;;
    done) echo "$done" ;;
    pending) echo "$((total - done))" ;;
    *) echo "$total" ;;
  esac
}

# Get file modification time as epoch seconds (cross-platform)
# Usage: pdlc_get_mtime <file>
# Returns epoch seconds on stdout, empty string if file missing
pdlc_get_mtime() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo ""
    return 0
  fi
  # macOS uses stat -f %m, Linux uses stat -c %Y
  if stat -f %m "$file" 2>/dev/null; then
    return 0
  fi
  stat -c %Y "$file" 2>/dev/null
}

# Convert epoch seconds to YYYY-MM-DD date string (cross-platform)
# Usage: pdlc_epoch_to_date_str <epoch_seconds>
# Returns date or empty on failure. macOS: date -r ; GNU: date -d @
pdlc_epoch_to_date_str() {
  local epoch="$1"
  if [[ -z "$epoch" ]]; then
    echo ""
    return 0
  fi
  date -r "$epoch" '+%Y-%m-%d' 2>/dev/null || date -d "@$epoch" '+%Y-%m-%d' 2>/dev/null || echo ""
}

# Convert a date string (YYYY-MM-DD or ISO) to epoch seconds (cross-platform)
# Usage: pdlc_date_to_epoch <date_str>
# Extracts first YYYY-MM-DD match; macOS date -j -f ; GNU date -d
pdlc_date_to_epoch() {
  local date_str="$1"
  if [[ -z "$date_str" ]]; then
    echo ""
    return 0
  fi
  # Extract first YYYY-MM-DD to be robust with ISO timestamps etc.
  date_str=$(echo "$date_str" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  if [[ -z "$date_str" ]]; then
    echo ""
    return 0
  fi
  local epoch
  epoch=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null) || \
  epoch=$(date -d "$date_str" +%s 2>/dev/null) || true
  echo "$epoch"
}

# Get a top-level field from spec.json (portable helper for spec-driven logic)
# Future core owns spec.json schema (phase, updated_at, created_at, active_workflow, etc.)
# Usage: pdlc_get_spec_json_field <spec_dir> <field>   e.g. "updated_at" or "phase"
# Returns value or empty. Uses pdlc_read_json_field (jq).
pdlc_get_spec_json_field() {
  local spec_dir="$1"
  local field="$2"
  local json_file="${spec_dir}/spec.json"
  if [[ ! -f "$json_file" ]]; then
    echo ""
    return 0
  fi
  pdlc_read_json_field "$field" < "$json_file" 2>/dev/null || echo ""
}
