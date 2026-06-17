#!/usr/bin/env bats
# tests/e2e/hooks-live.bats — Live Claude Code tests for hook behavior
#
# Runs real `claude -p` sessions with inline --settings to verify hooks
# fire correctly during actual agent conversations.
#
# USAGE:
#   PDLC_LIVE_TESTS=1 bats tests/e2e/hooks-live.bats
#
# These tests consume API credits (~$0.05-0.15 per test). Skipped by default.

load ../helpers/common-setup

# Build the hooks settings JSON once (used by all tests)
HOOKS_SETTINGS='{"hooks":{"PreToolUse":[{"matcher":"Task","hooks":[{"type":"command","command":"bash hooks/spec-gate.sh","timeout":10000},{"type":"command","command":"bash hooks/critic-gate.sh","timeout":10000}]}]}}'

setup_file() {
  if [[ "${PDLC_LIVE_TESTS:-}" != "1" ]]; then
    skip "Live tests disabled. Set PDLC_LIVE_TESTS=1 to run."
  fi
  if ! command -v claude &>/dev/null; then
    skip "claude CLI not found in PATH"
  fi
}

setup() {
  TEST_WORK_DIR="$(mktemp -d)"
}

teardown() {
  if [[ -n "${TEST_WORK_DIR:-}" && -d "${TEST_WORK_DIR}" ]]; then
    rm -rf "${TEST_WORK_DIR}"
  fi
}

# Helper: run claude -p with our hooks and capture JSON output
run_claude_with_hooks() {
  local prompt="$1"
  local allowed_tools="${2:-Task,Read}"
  local extra_settings="${3:-$HOOKS_SETTINGS}"
  claude -p "${prompt}" \
    --output-format json \
    --max-budget-usd 0.50 \
    --settings "${extra_settings}" \
    --allowedTools "${allowed_tools}" \
    --no-session-persistence \
    --append-system-prompt "You are in a test environment. Working directory has hooks/ with PDLC enforcement hooks." \
    2>/dev/null
}

# --- SpecGate Tests: Block spec generation via Task tool ---

@test "SpecGate live: hook blocks 'generate requirements' via Task tool" {
  output=$(run_claude_with_hooks \
    "Use the Task tool to generate requirements.md for a login feature. You must use the Task tool, not any other approach." \
    "Task,Read")
  # The result should mention SpecGate violation or that the tool was denied
  result=$(echo "$output" | jq -r '.result // empty')
  # Look for evidence the hook blocked it or Claude acknowledged the block
  [[ "$result" == *"SpecGate"* ]] || \
  [[ "$result" == *"denied"* ]] || \
  [[ "$result" == *"blocked"* ]] || \
  [[ "$result" == *"Skill tool"* ]] || \
  [[ "$result" == *"kiro"* ]] || \
  [[ "$result" == *"cannot"* ]] || \
  [[ "$result" == *"not allowed"* ]]
}

@test "SpecGate live: hook allows non-spec Task tool calls" {
  output=$(run_claude_with_hooks \
    "Use the Task tool to search for all .sh files in the hooks/ directory and list them." \
    "Task,Read,Glob,Grep")
  result=$(echo "$output" | jq -r '.result // empty')
  # Should NOT mention SpecGate violation
  [[ "$result" != *"SpecGate VIOLATION"* ]]
}

@test "SpecGate live: hook blocks 'write design.md' via Task tool" {
  output=$(run_claude_with_hooks \
    "Use the Task tool with this exact prompt: 'write design.md for the authentication module'. Do not use any other tool." \
    "Task,Read")
  result=$(echo "$output" | jq -r '.result // empty')
  [[ "$result" == *"SpecGate"* ]] || \
  [[ "$result" == *"denied"* ]] || \
  [[ "$result" == *"blocked"* ]] || \
  [[ "$result" == *"Skill"* ]] || \
  [[ "$result" == *"not allowed"* ]] || \
  [[ "$result" == *"cannot"* ]]
}

# --- CriticGate Tests: Block Actor dispatch without critic review ---

@test "CriticGate live: hook blocks Actor dispatch without prior critic results" {
  # Set up HANDOFF.md with batch 2 but no critic results for batch 1
  mkdir -p "${TEST_WORK_DIR}/.pdlc/state"
  cat > "${TEST_WORK_DIR}/.pdlc/state/HANDOFF.md" <<'HANDOFF'
---
phase: ACTOR
batch: 2
spec_dir: .claude/specs/test
pending_tasks: T-2.1
completed_tasks: T-1.1
---

## Batch 2
Starting next batch.
HANDOFF

  cd "${TEST_WORK_DIR}"
  # Copy hooks directory so the hook scripts can be found
  cp -r "${HOOKS_DIR}" "${TEST_WORK_DIR}/hooks"

  output=$(run_claude_with_hooks \
    "Use the Task tool to dispatch an Actor for batch 2. Your prompt to the Task tool MUST start with '[ACTOR: Batch 2]'. Do not do anything else." \
    "Task,Read")
  result=$(echo "$output" | jq -r '.result // empty')
  [[ "$result" == *"CriticGate"* ]] || \
  [[ "$result" == *"denied"* ]] || \
  [[ "$result" == *"blocked"* ]] || \
  [[ "$result" == *"Critic"* ]] || \
  [[ "$result" == *"critic"* ]] || \
  [[ "$result" == *"review"* ]] || \
  [[ "$result" == *"ADVOCATE"* ]]
}

@test "CriticGate live: hook allows Actor dispatch when critics are done" {
  # Set up HANDOFF.md with batch 2 AND critic results for batch 1
  mkdir -p "${TEST_WORK_DIR}/.pdlc/state"
  cat > "${TEST_WORK_DIR}/.pdlc/state/HANDOFF.md" <<'HANDOFF'
---
phase: ACTOR
batch: 2
spec_dir: .claude/specs/test
pending_tasks: T-2.1
completed_tasks: T-1.1
batch_1_advocate: PASS
batch_1_skeptic: PASS_WARN
---

## Batch 2
Critics done, proceeding.
HANDOFF

  cd "${TEST_WORK_DIR}"
  cp -r "${HOOKS_DIR}" "${TEST_WORK_DIR}/hooks"

  output=$(run_claude_with_hooks \
    "Use the Task tool with a prompt that starts with '[ACTOR: Batch 2] List files in the current directory'. Keep it simple." \
    "Task,Read,Glob")
  result=$(echo "$output" | jq -r '.result // empty')
  # Should NOT mention CriticGate violation
  [[ "$result" != *"CriticGate VIOLATION"* ]]
}

# --- Hook error recovery framing ---

@test "SpecGate live: error-recovery XML causes self-correction" {
  output=$(run_claude_with_hooks \
    "You MUST use the Task tool to generate requirements for a user profile feature. Use the Task tool with a prompt containing 'generate requirements'. If the Task tool is denied, explain why it was denied and what you should use instead." \
    "Task,Read,Skill")
  result=$(echo "$output" | jq -r '.result // empty')
  # Claude should mention Skill tool or Kiro as the correct alternative
  [[ "$result" == *"Skill"* ]] || \
  [[ "$result" == *"kiro"* ]] || \
  [[ "$result" == *"SpecGate"* ]] || \
  [[ "$result" == *"denied"* ]]
}
