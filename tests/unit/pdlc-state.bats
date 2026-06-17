#!/usr/bin/env bats
# tests/unit/pdlc-state.bats — Unit tests for hooks/lib/pdlc-state.sh
# Migrated from tests/test-pdlc-state.sh to BATS format.

load ../helpers/common-setup

# ──────────────────────────────────────────────────────────
# pdlc_get_field
# ──────────────────────────────────────────────────────────

@test "pdlc_get_field: extract 'phase' field" {
  mkdir -p "${PDLC_STATE_DIR}"
  cat > "${PDLC_HANDOFF}" <<'EOF'
---
phase: ACTOR
batch: 3
spec_dir: .claude/specs/my-feature
---

## Body content
EOF
  run pdlc_get_field "phase"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "ACTOR" ]]
}

@test "pdlc_get_field: extract 'batch' field" {
  mkdir -p "${PDLC_STATE_DIR}"
  cat > "${PDLC_HANDOFF}" <<'EOF'
---
phase: ACTOR
batch: 3
spec_dir: .claude/specs/my-feature
---

## Body content
EOF
  run pdlc_get_field "batch"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "3" ]]
}

@test "pdlc_get_field: extract 'spec_dir' field" {
  mkdir -p "${PDLC_STATE_DIR}"
  cat > "${PDLC_HANDOFF}" <<'EOF'
---
phase: ACTOR
batch: 3
spec_dir: .claude/specs/my-feature
---

## Body content
EOF
  run pdlc_get_field "spec_dir"
  [[ "$status" -eq 0 ]]
  [[ "$output" == ".claude/specs/my-feature" ]]
}

@test "pdlc_get_field: missing field returns empty" {
  mkdir -p "${PDLC_STATE_DIR}"
  cat > "${PDLC_HANDOFF}" <<'EOF'
---
phase: ACTOR
batch: 3
spec_dir: .claude/specs/my-feature
---

## Body content
EOF
  run pdlc_get_field "nonexistent"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "pdlc_get_field: empty frontmatter returns empty" {
  mkdir -p "${PDLC_STATE_DIR}"
  cat > "${PDLC_HANDOFF}" <<'EOF'
---
---

Some body
EOF
  run pdlc_get_field "phase"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "pdlc_get_field: no frontmatter returns empty" {
  mkdir -p "${PDLC_STATE_DIR}"
  cat > "${PDLC_HANDOFF}" <<'EOF'
Just plain text, no frontmatter.
EOF
  run pdlc_get_field "phase"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "pdlc_get_field: nonexistent file returns empty" {
  run pdlc_get_field "phase"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "pdlc_get_field: exact field match (no substring bleed)" {
  mkdir -p "${PDLC_STATE_DIR}"
  cat > "${PDLC_HANDOFF}" <<'EOF'
---
batch: 2
batch_1_advocate: DONE
---
EOF
  run pdlc_get_field "batch"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "2" ]]
}

# ──────────────────────────────────────────────────────────
# pdlc_write_handoff
# ──────────────────────────────────────────────────────────

@test "pdlc_write_handoff: file created" {
  pdlc_write_handoff "phase: ACTOR
batch: 1" "## My Body

Content here."
  [[ -f "${PDLC_HANDOFF}" ]]
}

@test "pdlc_write_handoff: starts with ---" {
  pdlc_write_handoff "phase: ACTOR
batch: 1" "## My Body

Content here."
  local first_line
  first_line=$(head -1 "${PDLC_HANDOFF}")
  [[ "$first_line" == "---" ]]
}

@test "pdlc_write_handoff: contains phase field" {
  pdlc_write_handoff "phase: ACTOR
batch: 1" "## My Body

Content here."
  grep -q "phase: ACTOR" "${PDLC_HANDOFF}"
}

@test "pdlc_write_handoff: contains body" {
  pdlc_write_handoff "phase: ACTOR
batch: 1" "## My Body

Content here."
  grep -q "## My Body" "${PDLC_HANDOFF}"
}

@test "pdlc_write_handoff: no .tmp file left" {
  pdlc_write_handoff "phase: ACTOR
batch: 1" "## My Body

Content here."
  [[ ! -f "${PDLC_HANDOFF}.tmp" ]]
}

@test "pdlc_write_handoff: write without body has 3 lines" {
  pdlc_write_handoff "phase: DONE" ""
  local line_count
  line_count=$(wc -l < "${PDLC_HANDOFF}" | tr -d ' ')
  [[ "$line_count" -eq 3 ]]
}

# ──────────────────────────────────────────────────────────
# pdlc_set_field
# ──────────────────────────────────────────────────────────

@test "pdlc_set_field: update existing field" {
  pdlc_write_handoff "phase: ACTOR
batch: 1" "Body text"
  pdlc_set_field "phase" "CRITIC"
  run pdlc_get_field "phase"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "CRITIC" ]]
}

@test "pdlc_set_field: other fields preserved" {
  pdlc_write_handoff "phase: ACTOR
batch: 1" "Body text"
  pdlc_set_field "phase" "CRITIC"
  run pdlc_get_field "batch"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "1" ]]
}

@test "pdlc_set_field: body preserved after set_field" {
  pdlc_write_handoff "phase: ACTOR
batch: 1" "Body text"
  pdlc_set_field "phase" "CRITIC"
  grep -q "Body text" "${PDLC_HANDOFF}"
}

@test "pdlc_set_field: add new field" {
  pdlc_write_handoff "phase: ACTOR" "Body"
  pdlc_set_field "batch" "5"
  run pdlc_get_field "batch"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "5" ]]
}

@test "pdlc_set_field: original field preserved after add" {
  pdlc_write_handoff "phase: ACTOR" "Body"
  pdlc_set_field "batch" "5"
  run pdlc_get_field "phase"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "ACTOR" ]]
}

@test "pdlc_set_field: set_field on no-frontmatter file" {
  mkdir -p "${PDLC_STATE_DIR}"
  echo "Just plain text" > "${PDLC_HANDOFF}"
  pdlc_set_field "phase" "INIT"
  run pdlc_get_field "phase"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "INIT" ]]
}

@test "pdlc_set_field: old content preserved as body" {
  mkdir -p "${PDLC_STATE_DIR}"
  echo "Just plain text" > "${PDLC_HANDOFF}"
  pdlc_set_field "phase" "INIT"
  grep -q "Just plain text" "${PDLC_HANDOFF}"
}

@test "pdlc_set_field: creates file if missing" {
  pdlc_set_field "phase" "NEW"
  run pdlc_get_field "phase"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "NEW" ]]
}

@test "pdlc_set_field: no .tmp after set_field" {
  pdlc_set_field "phase" "NEW"
  [[ ! -f "${PDLC_HANDOFF}.tmp" ]]
}

# ──────────────────────────────────────────────────────────
# pdlc_read_json_field
# ──────────────────────────────────────────────────────────

@test "pdlc_read_json_field: read top-level JSON field" {
  local result
  result=$(echo '{"tool_name":"Task","tool_input":{"prompt":"hello world"}}' | pdlc_read_json_field "tool_name")
  [[ "$result" == "Task" ]]
}

@test "pdlc_read_json_field: read nested JSON field" {
  local result
  result=$(echo '{"tool_name":"Task","tool_input":{"prompt":"hello world"}}' | pdlc_read_json_field "tool_input.prompt")
  [[ "$result" == "hello world" ]]
}

@test "pdlc_read_json_field: missing JSON field returns empty" {
  local result
  result=$(echo '{"tool_name":"Task"}' | pdlc_read_json_field "nonexistent")
  [[ -z "$result" ]]
}

@test "pdlc_read_json_field: invalid JSON returns empty" {
  local result
  result=$(echo 'not json' | pdlc_read_json_field "tool_name" 2>/dev/null || echo "")
  [[ -z "$result" ]]
}

# ──────────────────────────────────────────────────────────
# Marker file operations
# ──────────────────────────────────────────────────────────

@test "marker: touch_marker creates file" {
  pdlc_ensure_state_dir
  pdlc_touch_marker
  [[ -f "${PDLC_MARKER}" ]]
}

@test "marker: marker_exists returns 0 when file exists" {
  pdlc_ensure_state_dir
  pdlc_touch_marker
  run pdlc_marker_exists
  [[ "$status" -eq 0 ]]
}

@test "marker: delete_marker removes file" {
  pdlc_ensure_state_dir
  pdlc_touch_marker
  pdlc_delete_marker
  [[ ! -f "${PDLC_MARKER}" ]]
}

@test "marker: marker_exists returns 1 when file missing" {
  pdlc_ensure_state_dir
  run pdlc_marker_exists
  [[ "$status" -eq 1 ]]
}

@test "marker: delete absent marker no error" {
  pdlc_ensure_state_dir
  run pdlc_delete_marker
  [[ "$status" -eq 0 ]]
}

# ──────────────────────────────────────────────────────────
# pdlc_count_tasks
# ──────────────────────────────────────────────────────────

@test "pdlc_count_tasks: total count" {
  local tasks_file="${TEST_WORK_DIR}/tasks.md"
  cat > "$tasks_file" <<'EOF'
- [ ] 1.1 First
- [x] 1.2 Done
- [ ] 2.1 Pending
EOF
  run pdlc_count_tasks "$tasks_file" "total"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "3" ]]
}

@test "pdlc_count_tasks: done count" {
  local tasks_file="${TEST_WORK_DIR}/tasks.md"
  cat > "$tasks_file" <<'EOF'
- [ ] 1.1 First
- [x] 1.2 Done
- [ ] 2.1 Pending
EOF
  run pdlc_count_tasks "$tasks_file" "done"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "1" ]]
}

@test "pdlc_count_tasks: pending count" {
  local tasks_file="${TEST_WORK_DIR}/tasks.md"
  cat > "$tasks_file" <<'EOF'
- [ ] 1.1 First
- [x] 1.2 Done
- [ ] 2.1 Pending
EOF
  run pdlc_count_tasks "$tasks_file" "pending"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "2" ]]
}

@test "pdlc_count_tasks: missing file returns 0" {
  run pdlc_count_tasks "${TEST_WORK_DIR}/no-such-tasks.md" "total"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "0" ]]
}

@test "pdlc_count_tasks: empty file returns 0" {
  local tasks_file="${TEST_WORK_DIR}/empty.md"
  touch "$tasks_file"
  run pdlc_count_tasks "$tasks_file" "total"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "0" ]]
}

# ──────────────────────────────────────────────────────────
# pdlc_get_mtime
# ──────────────────────────────────────────────────────────

@test "pdlc_get_mtime: returns epoch for existing file" {
  local f="${TEST_WORK_DIR}/tfile"
  touch "$f"
  run pdlc_get_mtime "$f"
  [[ "$status" -eq 0 ]]
  # epoch should be a number > 0 and look like seconds since epoch (rough check: >= 8 digits or non-empty numeric)
  [[ -n "$output" ]]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "pdlc_get_mtime: returns empty for missing file" {
  run pdlc_get_mtime "${TEST_WORK_DIR}/no-such-file"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}
