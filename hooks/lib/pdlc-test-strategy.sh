#!/bin/bash
# hooks/lib/pdlc-test-strategy.sh — Test strategy recommendation engine
#
# Analyzes spec.md and plan.md to recommend test types, frameworks,
# coverage targets, and TDD guidance for Actor sessions.
# Read-only Observer: reports recommendations, never blocks.
#
# Host adapter / Ralph driver reuse:
# Example call sequence for host /loop or Ralph driver:
#   pdlc_test_strategy
#   (used in director + actor dispatch for portable core; Ralph/loop/Grok/Cursor reuse)
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-test-strategy.sh"
# Depends on: (none — standalone analysis)

set -euo pipefail

# Analyze spec and plan artifacts to produce a test strategy recommendation
# Usage: pdlc_test_strategy <spec_dir>
# Output: structured recommendation as markdown
# Returns: 0 always (Observer — never fails)
pdlc_test_strategy() {
  local spec_dir="${1:-}"

  # Empty or missing spec directory
  if [[ -z "$spec_dir" || ! -d "$spec_dir" ]]; then
    echo "INFO: No spec directory found — skipping test strategy"
    return 0
  fi

  local spec_file="${spec_dir}/spec.md"
  local plan_file="${spec_dir}/plan.md"

  # No spec.md at all — cannot analyze
  if [[ ! -f "$spec_file" ]]; then
    echo "INFO: No spec.md found in ${spec_dir} — skipping test strategy"
    return 0
  fi

  # ── Extract spec metrics ────────────────────────────────
  local user_story_count acceptance_scenario_count requirement_count edge_case_count

  user_story_count=$(grep -c "### .*User Story" "$spec_file" 2>/dev/null) || true
  user_story_count="${user_story_count:-0}"
  user_story_count="${user_story_count//[[:space:]]/}"

  acceptance_scenario_count=$(grep -c '\*\*Given\*\*' "$spec_file" 2>/dev/null) || true
  acceptance_scenario_count="${acceptance_scenario_count:-0}"
  acceptance_scenario_count="${acceptance_scenario_count//[[:space:]]/}"

  requirement_count=$(grep -c '\*\*FR-' "$spec_file" 2>/dev/null) || true
  requirement_count="${requirement_count:-0}"
  requirement_count="${requirement_count//[[:space:]]/}"

  edge_case_count=$(awk '
    /^###? Edge Cases/ { found=1; next }
    found && /^##/ { exit }
    found && /^- / { count++ }
    END { print count+0 }
  ' "$spec_file" 2>/dev/null)

  # ── Extract plan context (if available) ─────────────────
  local test_framework="BATS"
  local has_plan=0

  if [[ -f "$plan_file" ]]; then
    has_plan=1
    # Try to detect test framework from plan
    local detected_framework
    detected_framework=$(grep -ioE '(BATS|Jest|Mocha|pytest|JUnit|RSpec|Go test)' "$plan_file" 2>/dev/null | head -1) || true
    if [[ -n "$detected_framework" ]]; then
      test_framework="$detected_framework"
    fi
  fi

  # ── Determine recommended test types ────────────────────
  local recommend_integration=0
  local recommend_e2e=0

  # Multiple user stories or requirements mentioning interaction → integration tests
  if [[ "$user_story_count" -gt 1 ]]; then
    recommend_integration=1
  fi
  if grep -qiE '(interact|integrat|pipeline|orchestrat|cross-|end.to.end)' "$spec_file" 2>/dev/null; then
    recommend_integration=1
  fi

  # E2E if spec mentions user workflows or acceptance scenarios span multiple components
  if grep -qiE '(workflow|end.to.end|e2e|outer.loop)' "$spec_file" 2>/dev/null; then
    recommend_e2e=1
  fi

  # ── TDD recommendation ──────────────────────────────────
  local tdd_recommendation="yes"
  if [[ "$acceptance_scenario_count" -eq 0 ]]; then
    tdd_recommendation="add acceptance scenarios first"
  fi

  # ── Coverage target ─────────────────────────────────────
  local coverage_target
  if [[ "$acceptance_scenario_count" -gt 0 ]]; then
    coverage_target="${acceptance_scenario_count} acceptance scenarios, ${edge_case_count} edge cases"
  else
    coverage_target="define acceptance scenarios first"
  fi

  # ── Build output ────────────────────────────────────────
  local disabled_note=""
  if [[ "${PDLC_DISABLED:-0}" == "1" ]]; then
    disabled_note=" (informational — PDLC_DISABLED=1)"
  fi

  cat <<EOF
## Test Strategy Recommendation${disabled_note}

### Spec Analysis
- User stories: ${user_story_count}
- Acceptance scenarios: ${acceptance_scenario_count}
- Requirements: ${requirement_count}
- Edge cases: ${edge_case_count}

### Recommended Test Types
EOF

  echo "- Unit tests: yes (framework: ${test_framework})"
  if [[ "$recommend_integration" -eq 1 ]]; then
    echo "- Integration tests: yes"
  else
    echo "- Integration tests: no (single-component feature)"
  fi
  if [[ "$recommend_e2e" -eq 1 ]]; then
    echo "- E2E tests: yes"
  else
    echo "- E2E tests: no"
  fi

  cat <<EOF

### Coverage Targets
- ${coverage_target}

### TDD Recommendation
- ${tdd_recommendation}
EOF

  if [[ "$has_plan" -eq 0 ]]; then
    echo ""
    echo "Note: No plan.md found — recommendations based on spec content alone"
  fi

  return 0
}
