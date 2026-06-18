#!/usr/bin/env bats

load ../helpers/common-setup

OUTER_LOOP="${HOOKS_DIR}/pdlc-outer-loop.sh"
STUB_DIR="$(cd "${BATS_TEST_DIRNAME}/../stubs" && pwd)"

# Integration note for #53 resource governance (bugs-first):
# Pre-dispatch guards (pdlc-resource_check), drain, cleanup, resource circuit breakers
# and "skipped (resource pressure)" / "skipped due to resource pressure" paths are exercised via
# pdlc-outer-loop.sh + lib (see: lines 274,298,310,348,440; critical + report to HANDOFF).
# Stubs do not simulate pgrep/vm_stat pressure, so e2e wiring + "skipped due to resource pressure"
# paths covered here; portable unit cases in tests/unit/pdlc-resource.bats (all 5 funcs + envs + fallbacks + safe/force).
# See outer-loop: resource guard before claude -p, drain after actor, critical breaker,
# cleanup in traps/DONE. Director prompts + SKILL.md + validator-templates embed the
# P2 "Critics review artifacts, NOT re-execute; report skipped on pressure".

setup() {
  TEST_WORK_DIR="$(mktemp -d)"
  # Create a minimal spec dir with tasks.md
  mkdir -p "${TEST_WORK_DIR}/.claude/specs/test-feature"
  cat > "${TEST_WORK_DIR}/.claude/specs/test-feature/tasks.md" <<'EOF'
# Tasks

- [ ] 1.1 First task
- [ ] 1.2 Second task
- [ ] 2.1 Third task
EOF
  # Init git repo for progress detection (local identity for CI runners without global git config)
  (cd "$TEST_WORK_DIR" && git init -q && \
    git -c user.email="pdlc-test@example.com" -c user.name="PDLC Test" add -A && \
    git -c user.email="pdlc-test@example.com" -c user.name="PDLC Test" commit -q -m "init")
  # Put stub claude first on PATH
  export PATH="${STUB_DIR}:${PATH}"
  export PDLC_HOOKS_DIR="${HOOKS_DIR}"
  # Director uses deterministic fallback; stub claude only simulates Actor dispatch.
  export PDLC_DIRECTOR_TEST_MODE=1
  # Isolate from host test runners (parallel bats, IDE test watchers, etc.)
  export PDLC_MIN_FREE_MEM_MB=0
  export PDLC_MAX_TEST_PROCS=9999
  export PDLC_RESOURCE_CRITICAL_MB=0
}

teardown() {
  unset PDLC_DIRECTOR_TEST_MODE
  rm -rf "${TEST_WORK_DIR}"
}

@test "outer loop: creates HANDOFF.md on first run" {
  cd "$TEST_WORK_DIR"
  PDLC_SPEC_DIR=".claude/specs/test-feature" \
    PDLC_MAX_SESSIONS=1 \
    STUB_SESSIONS_TO_DONE=99 \
    bash "${OUTER_LOOP}" 2>&1 || true
  # HANDOFF.md should exist with initial state
  [[ -f ".pdlc/state/HANDOFF.md" ]]
  source "${HOOKS_DIR}/lib/pdlc-state.sh"
  spec_dir=$(pdlc_get_field "spec_dir")
  [[ "$spec_dir" == ".claude/specs/test-feature" ]]
}

@test "outer loop: extracts pending tasks from tasks.md" {
  cd "$TEST_WORK_DIR"
  PDLC_SPEC_DIR=".claude/specs/test-feature" \
    PDLC_MAX_SESSIONS=1 \
    STUB_SESSIONS_TO_DONE=99 \
    bash "${OUTER_LOOP}" 2>&1 || true
  source "${HOOKS_DIR}/lib/pdlc-state.sh"
  pending=$(pdlc_get_field "pending_tasks")
  [[ "$pending" == *"T-1.1"* ]]
  [[ "$pending" == *"T-2.1"* ]]
}

@test "outer loop: exits 0 when phase is DONE" {
  cd "$TEST_WORK_DIR"
  # Stub will set DONE after 1 session
  PDLC_SPEC_DIR=".claude/specs/test-feature" \
    PDLC_MAX_SESSIONS=5 \
    STUB_SESSIONS_TO_DONE=1 \
    STUB_COST="0.50" \
    bash "${OUTER_LOOP}" 2>&1
  # Should exit 0 (success)
  [[ $? -eq 0 ]]
}

@test "outer loop: circuit breaker fires on max sessions" {
  cd "$TEST_WORK_DIR"
  # Never reach DONE, hit max sessions
  run bash -c "cd '${TEST_WORK_DIR}' && PDLC_SPEC_DIR='.claude/specs/test-feature' PDLC_MAX_SESSIONS=2 STUB_SESSIONS_TO_DONE=99 STUB_COST='0.10' bash '${OUTER_LOOP}' 2>&1"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"CIRCUIT BREAKER"* ]]
  [[ "$output" == *"Max sessions"* ]]
}

@test "outer loop: circuit breaker fires on max cost" {
  cd "$TEST_WORK_DIR"
  # High cost per session, low max cost
  run bash -c "cd '${TEST_WORK_DIR}' && PDLC_SPEC_DIR='.claude/specs/test-feature' PDLC_MAX_SESSIONS=10 PDLC_MAX_COST_USD=1.00 STUB_SESSIONS_TO_DONE=99 STUB_COST='2.00' bash '${OUTER_LOOP}' 2>&1"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"CIRCUIT BREAKER"* ]]
  [[ "$output" == *"Cost limit"* ]]
}

@test "outer loop: tracks session cost in HANDOFF.md" {
  cd "$TEST_WORK_DIR"
  PDLC_SPEC_DIR=".claude/specs/test-feature" \
    PDLC_MAX_SESSIONS=1 \
    STUB_SESSIONS_TO_DONE=99 \
    STUB_COST="2.75" \
    bash "${OUTER_LOOP}" 2>&1 || true
  source "${HOOKS_DIR}/lib/pdlc-state.sh"
  cost=$(pdlc_get_field "total_cost_usd")
  [[ "$cost" == "2.75" ]]
  count=$(pdlc_get_field "session_count")
  [[ "$count" == "1" ]]
}

@test "outer loop: resumes session count from HANDOFF.md" {
  cd "$TEST_WORK_DIR"
  # Pre-create HANDOFF.md with existing state
  mkdir -p ".pdlc/state"
  source "${HOOKS_DIR}/lib/pdlc-state.sh"
  pdlc_write_handoff "phase: ACTOR
batch: 3
spec_dir: .claude/specs/test-feature
pending_tasks: T-2.1
completed_tasks: T-1.1,T-1.2
total_cost_usd: 5.00
session_count: 4" "## Resumed session"
  # Run with max 2 more sessions
  PDLC_SPEC_DIR=".claude/specs/test-feature" \
    PDLC_MAX_SESSIONS=6 \
    STUB_SESSIONS_TO_DONE=1 \
    STUB_COST="1.00" \
    bash "${OUTER_LOOP}" 2>&1
  # Session count should be 5 (4 + 1), not 1
  count=$(pdlc_get_field "session_count")
  [[ "$count" == "5" ]]
}

@test "outer loop: fails with exit 2 when PDLC_SPEC_DIR missing" {
  cd "$TEST_WORK_DIR"
  run bash "${OUTER_LOOP}" 2>&1
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"PDLC_SPEC_DIR is required"* ]]
}

@test "outer loop: no-progress circuit breaker after 3 no-change sessions" {
  cd "$TEST_WORK_DIR"
  # The stub doesn't create real file changes, so git diff will show nothing
  # after the first commit. No-progress should fire after 3 sessions.
  run bash -c "cd '${TEST_WORK_DIR}' && PDLC_SPEC_DIR='.claude/specs/test-feature' PDLC_MAX_SESSIONS=10 PDLC_MAX_NO_PROGRESS=3 STUB_SESSIONS_TO_DONE=99 STUB_COST='0.10' bash '${OUTER_LOOP}' 2>&1"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"No progress"* ]]
}
