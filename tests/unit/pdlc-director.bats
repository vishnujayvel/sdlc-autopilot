#!/usr/bin/env bats
# tests/unit/pdlc-director.bats — Unit tests for hooks/lib/pdlc-director.sh

load ../helpers/common-setup

FIXTURES_DIR=""

# Note (#53 resource governance, bugs-first): build_prompt + fallbacks (pdlc_director_decide)
# now embed P2 CRITIC CONSTRAINT ("review Actor's test output/artifacts, NOT re-execute";
# "skipped on resource pressure") + P1 guard reference. Existing prompt tests cover
# structure; "skipped due to resource pressure" language asserted via grep in build_prompt tests.
# See pdlc-resource.sh (new portable lib) + tests/unit/pdlc-resource.bats (memory_mb, count, check+envs, pressure_critical, drain+cleanup safe/force) + outer-loop pre-dispatch/drain/breaker for
# the machine checks + "skipped due to resource pressure" wiring. Integration notes also in outer-loop.bats.

setup() {
  TEST_WORK_DIR="$(mktemp -d)"
  source "${HOOKS_DIR}/lib/pdlc-director.sh"
  PDLC_STATE_DIR="${TEST_WORK_DIR}/.pdlc/state"
  PDLC_HANDOFF="${PDLC_STATE_DIR}/HANDOFF.md"
  PDLC_MARKER="${PDLC_STATE_DIR}/.compact_marker"
  FIXTURES_DIR="${REPO_DIR}/tests/fixtures/spec-lifecycle"
}

# ──────────────────────────────────────────────────────────
# pdlc_director_validate_action
# ──────────────────────────────────────────────────────────

@test "director_validate_action: accepts specify" {
  run pdlc_director_validate_action "specify"
  [[ "$status" -eq 0 ]]
}

@test "director_validate_action: accepts plan" {
  run pdlc_director_validate_action "plan"
  [[ "$status" -eq 0 ]]
}

@test "director_validate_action: accepts generate-tasks" {
  run pdlc_director_validate_action "generate-tasks"
  [[ "$status" -eq 0 ]]
}

@test "director_validate_action: accepts implement" {
  run pdlc_director_validate_action "implement"
  [[ "$status" -eq 0 ]]
}

@test "director_validate_action: accepts review" {
  run pdlc_director_validate_action "review"
  [[ "$status" -eq 0 ]]
}

@test "director_validate_action: accepts archive" {
  run pdlc_director_validate_action "archive"
  [[ "$status" -eq 0 ]]
}

@test "director_validate_action: rejects invalid action" {
  run pdlc_director_validate_action "deploy"
  [[ "$status" -eq 1 ]]
}

# ──────────────────────────────────────────────────────────
# pdlc_director_build_prompt
# ──────────────────────────────────────────────────────────

@test "director_build_prompt: includes lifecycle state" {
  run pdlc_director_build_prompt "${FIXTURES_DIR}/clean" "Tasked"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "Tasked"
}

@test "director_build_prompt: includes task counts when tasks.md exists" {
  run pdlc_director_build_prompt "${FIXTURES_DIR}/implementing" "Implementing"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "task"
}

@test "director_build_prompt: includes budget info" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "total_cost_usd: 10.00
session_count: 3" ""
  PDLC_MAX_COST_USD=50.00
  run pdlc_director_build_prompt "${FIXTURES_DIR}/clean" "Tasked"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "budget\|cost"
}

# ──────────────────────────────────────────────────────────
# pdlc_director_architecture_context
# ──────────────────────────────────────────────────────────

@test "director_architecture_context: returns info when model exists" {
  run pdlc_director_architecture_context "${REPO_DIR}"
  [[ "$status" -eq 0 ]]
  # Should mention containers and components if architecture/ exists in repo
  if [[ -f "${REPO_DIR}/architecture/model.likec4" ]]; then
    echo "$output" | grep -q "containers"
  else
    echo "$output" | grep -q "No architecture model"
  fi
}

@test "director_build_prompt: includes architecture context" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "total_cost_usd: 0.00
session_count: 0" ""
  run pdlc_director_build_prompt "${FIXTURES_DIR}/clean" "Tasked"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "architecture"
}

@test "director_build_prompt: includes test strategy section" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "total_cost_usd: 0.00
session_count: 0" ""
  run pdlc_director_build_prompt "${FIXTURES_DIR}/clean" "Implementing"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "Test Strategy"
  echo "$output" | grep -q "User stories:"
}

@test "director_build_prompt: includes resource governance + canonical #53 skip phrase (P1/P2 #53)" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "total_cost_usd: 0.00
session_count: 0" ""
  run pdlc_director_build_prompt "${FIXTURES_DIR}/clean" "Implementing"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "Resource Governance"
  echo "$output" | grep -q "SKIPPED due to resource pressure — reviewed artifacts only"
}

@test "director_build_prompt: test strategy shows spec metrics" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "total_cost_usd: 0.00
session_count: 0" ""
  run pdlc_director_build_prompt "${FIXTURES_DIR}/clean" "Implementing"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "Acceptance scenarios: 2"
  echo "$output" | grep -q "Requirements: 3"
}

# ──────────────────────────────────────────────────────────
# pdlc_director_parse_response
# ──────────────────────────────────────────────────────────

@test "director_parse_response: extracts action from valid JSON" {
  local json='{"action":"implement","mode":"spawn","rationale":"Heavy work","actor_prompt":"Implement US1"}'
  run pdlc_director_parse_response "$json"
  [[ "$status" -eq 0 ]]
  local RS=$'\x1e'
  IFS="$RS" read -r action mode rationale actor_prompt <<< "$output"
  [[ "$action" == "implement" ]]
}

@test "director_parse_response: extracts mode from valid JSON" {
  local json='{"action":"implement","mode":"spawn","rationale":"Heavy work","actor_prompt":"Implement US1"}'
  run pdlc_director_parse_response "$json"
  local RS=$'\x1e'
  IFS="$RS" read -r action mode rationale actor_prompt <<< "$output"
  [[ "$mode" == "spawn" ]]
}

@test "director_parse_response: extracts actor_prompt from valid JSON" {
  local json='{"action":"implement","mode":"spawn","rationale":"Heavy work","actor_prompt":"Implement US1"}'
  run pdlc_director_parse_response "$json"
  local RS=$'\x1e'
  IFS="$RS" read -r action mode rationale actor_prompt <<< "$output"
  [[ "$actor_prompt" == "Implement US1" ]]
}

@test "director_parse_response: returns defaults for malformed JSON" {
  run pdlc_director_parse_response "not valid json at all"
  [[ "$status" -eq 0 ]]
  # Should contain fallback values
  local RS=$'\x1e'
  IFS="$RS" read -r action mode rationale actor_prompt <<< "$output"
  [[ "$mode" == "same-session" ]]
}

@test "director_parse_response: handles empty input" {
  run pdlc_director_parse_response ""
  [[ "$status" -eq 0 ]]
  local RS=$'\x1e'
  IFS="$RS" read -r action mode rationale actor_prompt <<< "$output"
  [[ "$mode" == "same-session" ]]
}

# ──────────────────────────────────────────────────────────
# pdlc_director_evaluate_critics
# ──────────────────────────────────────────────────────────

@test "director_evaluate_critics: returns accept when both PASS" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "batch: 1
batch_1_advocate: PASS
batch_1_skeptic: PASS" ""
  run pdlc_director_evaluate_critics "1" "0"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "accept" ]]
}

@test "director_evaluate_critics: returns retry when advocate FAIL" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "batch: 1
batch_1_advocate: FAIL
batch_1_skeptic: PASS" ""
  run pdlc_director_evaluate_critics "1" "0"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "retry" ]]
}

@test "director_evaluate_critics: returns retry when skeptic FAIL" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "batch: 1
batch_1_advocate: PASS
batch_1_skeptic: FAIL" ""
  run pdlc_director_evaluate_critics "1" "0"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "retry" ]]
}

@test "director_evaluate_critics: returns escalate after max retries" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "batch: 1
batch_1_advocate: FAIL
batch_1_skeptic: FAIL" ""
  PDLC_MAX_RETRIES=3
  run pdlc_director_evaluate_critics "1" "3"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "escalate" ]]
}

@test "director_evaluate_critics: returns accept when ADVOCATE PASS and SKEPTIC PASS_WARN" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "batch: 1
batch_1_advocate: PASS
batch_1_skeptic: PASS_WARN" ""
  run pdlc_director_evaluate_critics "1" "0"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "accept" ]]
}

@test "director_evaluate_critics: returns accept when no critic results (first batch)" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "batch: 1" ""
  run pdlc_director_evaluate_critics "1" "0"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "accept" ]]
}

@test "director_evaluate_critics: respects custom retry limit" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "batch: 1
batch_1_advocate: FAIL
batch_1_skeptic: FAIL" ""
  PDLC_MAX_RETRIES=1
  run pdlc_director_evaluate_critics "1" "1"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "escalate" ]]
}

# ──────────────────────────────────────────────────────────
# Adaptive strategy (US4)
# ──────────────────────────────────────────────────────────

@test "director_build_prompt: includes retry context when retry_count > 0" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "retry_count: 2
total_cost_usd: 5.00
session_count: 3" ""
  run pdlc_director_build_prompt "${FIXTURES_DIR}/implementing" "Implementing"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "Retry count: 2"
}

@test "director_build_prompt: includes budget pressure when cost high" {
  mkdir -p "${PDLC_STATE_DIR}"
  pdlc_write_handoff "total_cost_usd: 45.00
session_count: 8" ""
  PDLC_MAX_COST_USD=50.00
  run pdlc_director_build_prompt "${FIXTURES_DIR}/implementing" "Implementing"
  [[ "$status" -eq 0 ]]
  # Budget should show 45.00 of 50.00
  echo "$output" | grep -q "45.00"
}

# ──────────────────────────────────────────────────────────
# pdlc_director_decide fallbacks (#53 canonical skip phrase)
# ──────────────────────────────────────────────────────────

@test "director_decide: Implementing fallback includes canonical #53 skip phrase" {
  PDLC_DIRECTOR_TEST_MODE=1
  run pdlc_director_decide "${FIXTURES_DIR}/implementing" "Implementing"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "SKIPPED due to resource pressure — reviewed artifacts only"
}

@test "director_decide: Complete fallback includes canonical #53 skip phrase" {
  PDLC_DIRECTOR_TEST_MODE=1
  run pdlc_director_decide "${FIXTURES_DIR}/clean" "Complete"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "SKIPPED due to resource pressure — reviewed artifacts only"
}

@test "director_decide: unknown state fallback includes canonical #53 skip phrase" {
  PDLC_DIRECTOR_TEST_MODE=1
  run pdlc_director_decide "${FIXTURES_DIR}/clean" "Mystery"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "SKIPPED due to resource pressure — reviewed artifacts only"
}
