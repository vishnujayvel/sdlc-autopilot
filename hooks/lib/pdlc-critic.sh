#!/bin/bash
# hooks/lib/pdlc-critic.sh — Dual-perspective validation (ADVOCATE + SKEPTIC)
#
# ADVOCATE: checks implementation against spec requirements — spec compliance.
#   Reuses pdlc_xref_check (requirement coverage), pdlc_placeholder_check
#   (completeness), plus acceptance scenario and success criteria scans.
#
# SKEPTIC: checks production robustness — edge case coverage, error handling
#   patterns (ERR traps in hooks), test file existence.
#
# Consensus: pure logic combining both results into a single verdict:
#   accept, accept-with-caveats, retry, or escalate.
#
# Read-only Observer: reports findings, never blocks. Returns 0 always.
#
# Resource note (#53 P2): This lib evaluates statuses written by Actors/Critics.
# Critics (in SKILL/validator prompts) are constrained to review artifacts only and
# report "skipped due to resource pressure" — this consensus path supports that.
# No test execution happens here.
#
# Host adapter / Ralph driver reuse:
# Example call sequence for host /loop or Ralph driver:
#   pdlc_critic_advocate / pdlc_critic_skeptic / pdlc_critic_consensus / pdlc_critic_report
#   (used by director + outer for portable core; Ralph/loop/Grok/Cursor reuse)
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-critic.sh"
# Depends on: pdlc-state.sh, pdlc-xref.sh, pdlc-placeholder.sh

set -euo pipefail

CRITIC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies if not already loaded
if ! declare -f pdlc_get_field &>/dev/null; then
  source "${CRITIC_LIB_DIR}/pdlc-state.sh"
fi
if ! declare -f pdlc_xref_check &>/dev/null; then
  source "${CRITIC_LIB_DIR}/pdlc-xref.sh"
fi
if ! declare -f pdlc_placeholder_check &>/dev/null; then
  source "${CRITIC_LIB_DIR}/pdlc-placeholder.sh"
fi

# Default retry limit (shared with Director)
PDLC_MAX_RETRIES="${PDLC_MAX_RETRIES:-3}"

# ──────────────────────────────────────────────────────────
# ADVOCATE Critic — spec compliance checks
# ──────────────────────────────────────────────────────────

# Check implementation against spec requirements.
# Reuses pdlc_xref_check for requirement coverage, pdlc_placeholder_check
# for completeness, plus scans for acceptance scenarios and success criteria.
#
# Usage: pdlc_critic_advocate <spec_dir>
# Output: STATUS:category:severity:description lines
#   Final summary line: ADVOCATE:STATUS:coverage_pct:finding_count
# Returns: 0 always (Observer)
pdlc_critic_advocate() {
  local spec_dir="${1:-}"
  local findings=""
  local fail_count=0
  local warn_count=0
  local total_checks=0
  local passed_checks=0

  if [[ ! -d "$spec_dir" ]]; then
    echo "INFO:advocate:MINOR:spec directory not found"
    echo "ADVOCATE:INFO:0:0"
    return 0
  fi

  local spec_file="${spec_dir}/spec.md"
  local tasks_file="${spec_dir}/tasks.md"

  # Check 1: Cross-reference coverage (FR-XXX in spec covered by tasks)
  total_checks=$((total_checks + 1))
  if [[ -f "$spec_file" ]] && [[ -f "$tasks_file" ]]; then
    local xref_output
    xref_output=$(pdlc_xref_check "$spec_dir" 2>/dev/null) || true
    if echo "$xref_output" | grep -q "UNREFERENCED\|ORPHANED"; then
      local gap_count
      gap_count=$(echo "$xref_output" | grep -c "UNREFERENCED\|ORPHANED" 2>/dev/null || echo "0")
      gap_count="${gap_count//[[:space:]]/}"
      findings="${findings}FAIL:requirement-gap:BLOCKER:${gap_count} cross-reference gaps (requirements without tasks or orphaned references)"$'\n'
      fail_count=$((fail_count + 1))
    else
      passed_checks=$((passed_checks + 1))
    fi
  else
    if [[ ! -f "$spec_file" ]]; then
      findings="${findings}INFO:requirement-gap:MINOR:spec.md not found, skipping xref check"$'\n'
    fi
    if [[ ! -f "$tasks_file" ]]; then
      findings="${findings}INFO:requirement-gap:MINOR:tasks.md not found, skipping xref check"$'\n'
    fi
    passed_checks=$((passed_checks + 1))
  fi

  # Check 2: Placeholder completeness
  total_checks=$((total_checks + 1))
  if [[ -d "$spec_dir" ]]; then
    local placeholder_output
    placeholder_output=$(PDLC_DISABLED=1 pdlc_placeholder_check "$spec_dir" 2>/dev/null) || true
    if [[ -n "$placeholder_output" ]] && echo "$placeholder_output" | grep -q ":TEMPLATE:\|:TODO:\|:CLARIFICATION:\|:ACTION_REQUIRED:"; then
      local ph_count
      ph_count=$(echo "$placeholder_output" | grep -c ":" 2>/dev/null || echo "0")
      ph_count="${ph_count//[[:space:]]/}"
      findings="${findings}FAIL:completeness:BLOCKER:${ph_count} unresolved placeholders in spec artifacts"$'\n'
      fail_count=$((fail_count + 1))
    else
      passed_checks=$((passed_checks + 1))
    fi
  fi

  # Check 3: Acceptance scenario presence
  total_checks=$((total_checks + 1))
  if [[ -f "$spec_file" ]]; then
    local scenario_count
    scenario_count=$(grep -c '\*\*Given\*\*' "$spec_file" 2>/dev/null || echo "0")
    scenario_count="${scenario_count//[[:space:]]/}"
    if [[ "$scenario_count" -eq 0 ]]; then
      findings="${findings}WARN:scenario-coverage:MAJOR:no acceptance scenarios (Given/When/Then) found in spec"$'\n'
      warn_count=$((warn_count + 1))
    else
      passed_checks=$((passed_checks + 1))
    fi
  else
    passed_checks=$((passed_checks + 1))
  fi

  # Check 4: Success criteria presence
  total_checks=$((total_checks + 1))
  if [[ -f "$spec_file" ]]; then
    local sc_count
    sc_count=$(grep -c "SC-" "$spec_file" 2>/dev/null || echo "0")
    sc_count="${sc_count//[[:space:]]/}"
    if [[ "$sc_count" -eq 0 ]]; then
      findings="${findings}WARN:success-criteria:MAJOR:no success criteria (SC-XXX) found in spec"$'\n'
      warn_count=$((warn_count + 1))
    else
      passed_checks=$((passed_checks + 1))
    fi
  else
    passed_checks=$((passed_checks + 1))
  fi

  # Compute coverage percentage
  local coverage_pct=0
  if [[ "$total_checks" -gt 0 ]]; then
    coverage_pct=$(( (passed_checks * 100) / total_checks ))
  fi

  # Determine overall status
  local status="PASS"
  local finding_count=$((fail_count + warn_count))
  if [[ "$fail_count" -gt 0 ]]; then
    status="FAIL"
  elif [[ "$warn_count" -gt 0 ]]; then
    status="WARN"
  fi

  # Output findings
  if [[ -n "$findings" ]]; then
    echo "$findings" | sed '/^$/d'
  fi

  # Summary line
  echo "ADVOCATE:${status}:${coverage_pct}:${finding_count}"
  return 0
}

# ──────────────────────────────────────────────────────────
# SKEPTIC Critic — production robustness checks
# ──────────────────────────────────────────────────────────

# Check production robustness: edge case coverage, error handling
# patterns, and test file existence.
#
# Usage: pdlc_critic_skeptic <spec_dir>
# Output: STATUS:category:severity:description lines
#   Final summary line: SKEPTIC:STATUS:finding_count
# Returns: 0 always (Observer)
pdlc_critic_skeptic() {
  local spec_dir="${1:-}"
  local findings=""
  local fail_count=0
  local warn_count=0

  if [[ ! -d "$spec_dir" ]]; then
    echo "INFO:skeptic:MINOR:spec directory not found"
    echo "SKEPTIC:INFO:0"
    return 0
  fi

  local spec_file="${spec_dir}/spec.md"

  # Check 1: Edge case coverage
  if [[ -f "$spec_file" ]]; then
    if ! grep -q "### Edge Cases\|## Edge Cases" "$spec_file" 2>/dev/null; then
      findings="${findings}WARN:edge-case:MAJOR:no edge cases section found in spec"$'\n'
      warn_count=$((warn_count + 1))
    else
      # Check that edge cases have content
      local edge_content
      edge_content=$(awk '
        /^###? Edge Cases/ { found=1; next }
        found && /^##/ { exit }
        found && /^-/ { count++ }
        found && /^[0-9]+\./ { count++ }
        found && /^[A-Za-z]/ { count++ }
        END { print count+0 }
      ' "$spec_file" 2>/dev/null)
      if [[ "$edge_content" -eq 0 ]]; then
        findings="${findings}WARN:edge-case:MAJOR:edge cases section is empty"$'\n'
        warn_count=$((warn_count + 1))
      fi
    fi
  fi

  # Check 2: Error handling patterns (ERR traps in hook scripts)
  # Look for .sh files referenced in the spec directory's parent hooks
  local hooks_dir="${CRITIC_LIB_DIR}/.."
  if [[ -d "$hooks_dir" ]]; then
    local hook_files
    hook_files=$(find "$hooks_dir" -maxdepth 1 -name "*.sh" -type f 2>/dev/null) || true
    if [[ -n "$hook_files" ]]; then
      local missing_trap_files=""
      local hook_file
      while IFS= read -r hook_file; do
        [[ -z "$hook_file" ]] && continue
        # Check if file has set -e or set -euo pipefail but no ERR trap
        if grep -q "set -e" "$hook_file" 2>/dev/null; then
          if ! grep -q "trap.*ERR\|trap.*err" "$hook_file" 2>/dev/null; then
            # Only flag scripts that have "exit 0" documentation (claim to always exit 0)
            if grep -qi "always exit 0\|exit 0" "$hook_file" 2>/dev/null; then
              local basename_file
              basename_file=$(basename "$hook_file")
              missing_trap_files="${missing_trap_files}${basename_file}, "
            fi
          fi
        fi
      done <<< "$hook_files"
      if [[ -n "$missing_trap_files" ]]; then
        missing_trap_files="${missing_trap_files%, }"
        findings="${findings}WARN:error-handling:MINOR:hook scripts claiming 'always exit 0' without ERR trap: ${missing_trap_files}"$'\n'
        warn_count=$((warn_count + 1))
      fi
    fi
  fi

  # Check 3: Test file existence
  # Check if there are .bats test files in the repo's tests/ directory
  local repo_root="${CRITIC_LIB_DIR}/../.."
  local tests_dir="${repo_root}/tests"
  if [[ -d "$tests_dir" ]]; then
    local bats_count
    bats_count=$(find "$tests_dir" -name "*.bats" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$bats_count" -eq 0 ]]; then
      findings="${findings}FAIL:test-coverage:BLOCKER:no test files (.bats) found in tests/"$'\n'
      fail_count=$((fail_count + 1))
    fi
  else
    findings="${findings}WARN:test-coverage:MAJOR:no tests/ directory found"$'\n'
    warn_count=$((warn_count + 1))
  fi

  # Determine overall status
  local status="PASS"
  local finding_count=$((fail_count + warn_count))
  if [[ "$fail_count" -gt 0 ]]; then
    status="FAIL"
  elif [[ "$warn_count" -gt 0 ]]; then
    status="WARN"
  fi

  # Output findings
  if [[ -n "$findings" ]]; then
    echo "$findings" | sed '/^$/d'
  fi

  # Summary line
  echo "SKEPTIC:${status}:${finding_count}"
  return 0
}

# ──────────────────────────────────────────────────────────
# Consensus — combine ADVOCATE + SKEPTIC into verdict
# ──────────────────────────────────────────────────────────

# Pure logic: map (advocate_status, skeptic_status, retry_count) to verdict.
#
# Rules:
#   ADVOCATE FAIL = mandatory retry (spec compliance is non-negotiable)
#   SKEPTIC FAIL  = warning only (production concerns can be deferred)
#   Both PASS     = accept
#   ADVOCATE PASS + SKEPTIC WARN = accept-with-caveats
#   ADVOCATE WARN + SKEPTIC PASS = accept-with-caveats
#   ADVOCATE WARN + SKEPTIC WARN = accept-with-caveats
#   Retry count >= limit = escalate (regardless of status)
#
# Usage: pdlc_critic_consensus <advocate_status> <skeptic_status> <retry_count>
# Output: verdict string (accept, accept-with-caveats, retry, escalate)
# Returns: 0 always (Observer)
pdlc_critic_consensus() {
  local advocate_status="${1:-PASS}"
  local skeptic_status="${2:-PASS}"
  local retry_count="${3:-0}"
  local max_retries="${PDLC_MAX_RETRIES:-3}"

  # PDLC_DISABLED: always accept (informational only)
  if [[ "${PDLC_DISABLED:-0}" == "1" ]]; then
    echo "accept"
    return 0
  fi

  # Retry limit exceeded — escalate regardless
  if [[ "$retry_count" -ge "$max_retries" ]]; then
    echo "escalate"
    return 0
  fi

  # ADVOCATE FAIL = mandatory retry
  if [[ "$advocate_status" == "FAIL" ]]; then
    echo "retry"
    return 0
  fi

  # Both PASS = accept
  if [[ "$advocate_status" == "PASS" ]] && [[ "$skeptic_status" == "PASS" ]]; then
    echo "accept"
    return 0
  fi

  # Any WARN combination (but no FAIL from ADVOCATE) = accept-with-caveats
  # SKEPTIC FAIL is treated as a warning (production concerns advisory)
  echo "accept-with-caveats"
  return 0
}

# ──────────────────────────────────────────────────────────
# Report — run both critics and produce unified verdict
# ──────────────────────────────────────────────────────────

# Run ADVOCATE and SKEPTIC, call consensus, return unified report.
#
# Usage: pdlc_critic_report <spec_dir> [retry_count]
# Output: advocate findings, skeptic findings, consensus verdict
# Returns: 0 always (Observer)
pdlc_critic_report() {
  local spec_dir="${1:-}"
  local retry_count="${2:-0}"

  if [[ ! -d "$spec_dir" ]]; then
    echo "INFO:No spec directory found for critic analysis"
    echo "CONSENSUS:accept"
    return 0
  fi

  # Run ADVOCATE
  local advocate_output
  advocate_output=$(pdlc_critic_advocate "$spec_dir") || true

  # Extract ADVOCATE status from summary line
  local advocate_status
  advocate_status=$(echo "$advocate_output" | grep "^ADVOCATE:" | awk -F: '{print $2}')
  advocate_status="${advocate_status:-PASS}"

  # Run SKEPTIC
  local skeptic_output
  skeptic_output=$(pdlc_critic_skeptic "$spec_dir") || true

  # Extract SKEPTIC status from summary line
  local skeptic_status
  skeptic_status=$(echo "$skeptic_output" | grep "^SKEPTIC:" | awk -F: '{print $2}')
  skeptic_status="${skeptic_status:-PASS}"

  # Output all findings
  echo "$advocate_output" | sed '/^$/d'
  echo "$skeptic_output" | sed '/^$/d'

  # Run consensus
  local verdict
  verdict=$(pdlc_critic_consensus "$advocate_status" "$skeptic_status" "$retry_count")
  echo "CONSENSUS:${verdict}"

  return 0
}
