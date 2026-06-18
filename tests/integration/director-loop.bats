#!/usr/bin/env bats
# tests/integration/director-loop.bats — Integration tests for Director decision loop

load ../helpers/common-setup

FIXTURES_DIR=""

setup() {
  TEST_WORK_DIR="$(mktemp -d)"
  export PDLC_DIRECTOR_TEST_MODE=1
  source "${HOOKS_DIR}/lib/pdlc-director.sh"
  PDLC_STATE_DIR="${TEST_WORK_DIR}/.pdlc/state"
  PDLC_HANDOFF="${PDLC_STATE_DIR}/HANDOFF.md"
  PDLC_MARKER="${PDLC_STATE_DIR}/.compact_marker"
  FIXTURES_DIR="${REPO_DIR}/tests/fixtures/spec-lifecycle"
}

teardown() {
  unset PDLC_DIRECTOR_TEST_MODE
  rm -rf "${TEST_WORK_DIR}"
}

# ──────────────────────────────────────────────────────────
# Director loop integration
# ──────────────────────────────────────────────────────────

@test "director_decide: returns valid decision for Tasked state" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "spec_lifecycle: Tasked
session_count: 0
total_cost_usd: 0.00" ""
  run pdlc_director_decide "${FIXTURES_DIR}/clean" "Tasked"
  [[ "$status" -eq 0 ]]
  # Output should be RS-delimited (\x1e): action<RS>mode<RS>rationale<RS>actor_prompt
  local RS=$'\x1e'
  [[ "$output" == *"$RS"* ]]
}

@test "director_decide: returns valid decision for Implementing state" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "spec_lifecycle: Implementing
session_count: 2
total_cost_usd: 5.00" ""
  run pdlc_director_decide "${FIXTURES_DIR}/implementing" "Implementing"
  [[ "$status" -eq 0 ]]
  local RS=$'\x1e'
  [[ "$output" == *"$RS"* ]]
}

@test "director: PDLC_DISABLED bypasses" {
  PDLC_DISABLED=1
  # Should not error — functions should still work, just bypass enforcement
  run pdlc_director_validate_action "implement"
  [[ "$status" -eq 0 ]]
  unset PDLC_DISABLED
}
