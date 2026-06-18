#!/usr/bin/env bats
# tests/integration/stop-check.bats — BATS tests for hooks/pdlc-stop-check.sh

load ../helpers/common-setup

# Helper: create an active spec dir with tasks.md in a workdir
# Usage: create_spec_dir "$workdir" "feature-name" "tasks content" ["full spec.json content"]
# If 4th arg provided, use it verbatim as spec.json (for phase/updated_at tests)
create_spec_dir() {
  local workdir="$1"
  local feature="$2"
  local tasks_content="$3"
  local spec_dir="${workdir}/.claude/specs/${feature}"
  mkdir -p "$spec_dir"
  if [[ -n "${4:-}" ]]; then
    echo "$4" > "${spec_dir}/spec.json"
  else
    echo '{"active_workflow": "pdlc-autopilot"}' > "${spec_dir}/spec.json"
  fi
  printf '%s\n' "$tasks_content" > "${spec_dir}/tasks.md"
}

# Helper: make all files in a spec dir appear old (stale)
# Sets modification time to N+1 days ago to ensure staleness (use margin > threshold)
make_spec_stale() {
  local workdir="$1"
  local feature="$2"
  local days="${3:-10}"
  local spec_dir="${workdir}/.claude/specs/${feature}"
  # Use touch -t with a timestamp days_ago (mac/gnu compat)
  local past_ts
  past_ts="$(date -v-${days}d '+%Y%m%d0000' 2>/dev/null || date -d "${days} days ago" '+%Y%m%d0000' 2>/dev/null)"
  for file in "$spec_dir"/*; do
    [[ -f "$file" ]] && touch -t "$past_ts" "$file"
  done
}

# Helper: run stop-check from a given workdir, capturing stderr and exit code
run_stop_check() {
  local workdir="$1"
  shift
  # Run in subshell from workdir; capture stderr to stdout for assertion
  (cd "$workdir" && env "$@" bash "${HOOKS_DIR}/pdlc-stop-check.sh" 2>&1) || return $?
}

@test "no active spec allows exit (exit 0)" {
  local workdir="${TEST_WORK_DIR}/t1"
  mkdir -p "${workdir}/.claude/specs"
  # No spec.json with pdlc-autopilot workflow
  run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter1"
}

@test "all tasks complete allows exit (exit 0)" {
  local workdir="${TEST_WORK_DIR}/t2"
  create_spec_dir "$workdir" "done-feature" "$(cat <<'EOF'
# Tasks
- [x] Task one
- [x] Task two
- [x] Task three
EOF
)"
  run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter2"
}

@test "non-stale spec with pending tasks blocks exit (exit 1)" {
  local workdir="${TEST_WORK_DIR}/t3"
  create_spec_dir "$workdir" "active-feature" "$(cat <<'EOF'
# Tasks
- [x] Task one
- [ ] Task two
- [ ] Task three
EOF
)"
  # Files just created — not stale (fresh => blocks; expect timeline context too)
  run run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter3" PDLC_STALE_DAYS=3
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"tasks still pending"* ]]
  [[ "$output" == *"days ago"* ]]
}

@test "stale spec with pending tasks warns and allows exit (exit 0)" {
  local workdir="${TEST_WORK_DIR}/t4"
  create_spec_dir "$workdir" "stale-feature" "$(cat <<'EOF'
# Tasks
- [ ] Task one
- [ ] Task two
EOF
)"
  # Make files appear stale (use margin over default 3)
  make_spec_stale "$workdir" "stale-feature" 6

  output="$(run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter4" PDLC_STALE_DAYS=3)"
  [[ "$output" == *"tasks still pending"* ]]
  [[ "$output" == *"days ago"* ]]
  [[ "$output" == *"Tip: Archive"* ]]
}

@test "custom PDLC_STALE_DAYS=1 triggers staleness for 2-day-old spec" {
  local workdir="${TEST_WORK_DIR}/t5"
  create_spec_dir "$workdir" "custom-stale" "$(cat <<'EOF'
# Tasks
- [ ] Pending task
EOF
)"
  # Make files appear 2 days old
  make_spec_stale "$workdir" "custom-stale" 2

  output="$(run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter5" PDLC_STALE_DAYS=1)"
  [[ "$output" == *"tasks still pending"* ]]
  [[ "$output" == *"days ago"* ]]
}

@test "custom PDLC_STALE_DAYS=10 does not trigger staleness for 6-day-old spec" {
  local workdir="${TEST_WORK_DIR}/t6"
  create_spec_dir "$workdir" "not-stale-yet" "$(cat <<'EOF'
# Tasks
- [ ] Pending task
EOF
)"
  # Make files appear 6 days old — but threshold is 10 (fresh)
  make_spec_stale "$workdir" "not-stale-yet" 6

  run run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter6" PDLC_STALE_DAYS=10
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"tasks still pending"* ]]
}

@test "safety limit still works when spec is not stale" {
  local workdir="${TEST_WORK_DIR}/t7"
  create_spec_dir "$workdir" "safety-feature" "$(cat <<'EOF'
# Tasks
- [ ] Pending task
EOF
)"
  # Pre-set counter at the limit
  echo "50" > "${TEST_WORK_DIR}/counter7"

  output="$(run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter7" PDLC_MAX_CONTINUES=50)"
  [[ "$output" == *"Safety limit reached"* ]]
}

@test "stale check runs before safety limit check" {
  local workdir="${TEST_WORK_DIR}/t8"
  create_spec_dir "$workdir" "stale-before-safety" "$(cat <<'EOF'
# Tasks
- [ ] Pending task
EOF
)"
  make_spec_stale "$workdir" "stale-before-safety" 6

  # Even with counter at 0, stale should trigger first
  echo "0" > "${TEST_WORK_DIR}/counter8"

  output="$(run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter8" PDLC_STALE_DAYS=3)"
  [[ "$output" == *"tasks still pending"* ]]
  [[ "$output" == *"Tip: Archive"* ]]
  # Should NOT mention safety limit
  [[ "$output" != *"Safety limit"* ]]
}

@test "stale warning includes pending task count" {
  local workdir="${TEST_WORK_DIR}/t9"
  create_spec_dir "$workdir" "stale-with-count" "$(cat <<'EOF'
# Tasks
- [ ] Task A
- [ ] Task B
- [x] Task C
EOF
)"
  make_spec_stale "$workdir" "stale-with-count" 6

  output="$(run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter9" PDLC_STALE_DAYS=3)"
  [[ "$output" == *"2 tasks still pending"* ]]
}

@test "counter is reset when spec is stale" {
  local workdir="${TEST_WORK_DIR}/t10"
  create_spec_dir "$workdir" "stale-reset" "$(cat <<'EOF'
# Tasks
- [ ] Pending
EOF
)"
  make_spec_stale "$workdir" "stale-reset" 6

  # Pre-set a counter value
  echo "10" > "${TEST_WORK_DIR}/counter10"

  run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter10" PDLC_STALE_DAYS=3
  # Counter file should be removed after stale exit
  [[ ! -f "${TEST_WORK_DIR}/counter10" ]]
}

@test "PDLC_DISABLED=1 bypasses stop-check (allows exit with pending tasks)" {
  local workdir="${TEST_WORK_DIR}/t11"
  create_spec_dir "$workdir" "disabled-feature" "$(cat <<'EOF'
# Tasks
- [ ] Task one
- [ ] Task two
EOF
)"
  # Without PDLC_DISABLED this would block exit; with it, should allow
  run_stop_check "$workdir" PDLC_DISABLED=1 PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter11" PDLC_STALE_DAYS=3
}

# --- New AC tests for #54: explicit phase, archive dir, multi-signal, timeline ---

@test "explicit phase=complete skips guard (allows exit 0 even with pending)" {
  local workdir="${TEST_WORK_DIR}/t12"
  create_spec_dir "$workdir" "complete-phase" "$(cat <<'EOF'
# Tasks
- [ ] leftover
EOF
)" '{"active_workflow": "pdlc-autopilot", "phase": "complete"}'

  run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter12"
  # allow (no block)
}

@test "explicit phase=archived skips guard (allows exit 0 even with pending)" {
  local workdir="${TEST_WORK_DIR}/t13"
  create_spec_dir "$workdir" "archived-phase" "$(cat <<'EOF'
# Tasks
- [ ] leftover
EOF
)" '{"active_workflow": "pdlc-autopilot", "phase": "archived"}'

  run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter13"
}

@test "spec under archive/ dir is skipped (allows exit 0)" {
  local workdir="${TEST_WORK_DIR}/t14"
  local arch_dir="${workdir}/.claude/specs/archive"
  mkdir -p "$arch_dir"
  # One level deep: .claude/specs/archive/spec.json (glob */spec.json); basename archive => skip
  echo '{"active_workflow": "pdlc-autopilot"}' > "${arch_dir}/spec.json"
  printf '%s\n' "- [ ] pending in archive" > "${arch_dir}/tasks.md"

  run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter14"
}

@test "updated_at in spec.json makes last-active recent (fresh) even if tasks.md mtime is old" {
  local workdir="${TEST_WORK_DIR}/t15"
  local today
  today="$(date +%Y-%m-%d)"
  create_spec_dir "$workdir" "json-date-signal" "$(cat <<'EOF'
# Tasks
- [ ] pending despite date
EOF
)" "{\"active_workflow\": \"pdlc-autopilot\", \"updated_at\": \"${today}\"}"

  # Force mtimes of files old (so mtime signals stale) but json date field keeps it fresh
  make_spec_stale "$workdir" "json-date-signal" 10

  # With STALE_DAYS=3, the parsed updated_at should make it fresh => block (exit1)
  run run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter15" PDLC_STALE_DAYS=3
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"tasks still pending"* ]]
  [[ "$output" == *"days ago"* ]]
}

@test "timeline context appears in blocking (fresh) warning" {
  local workdir="${TEST_WORK_DIR}/t16"
  create_spec_dir "$workdir" "timeline-block" "$(cat <<'EOF'
# Tasks
- [ ] one
EOF
)"

  run run_stop_check "$workdir" PDLC_COUNTER_FILE="${TEST_WORK_DIR}/counter16" PDLC_STALE_DAYS=3
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"Spec created:"* ]]
  [[ "$output" == *"Last updated:"* ]]
  [[ "$output" == *"tasks.md last modified:"* ]]
  [[ "$output" == *"days ago"* ]]
}
