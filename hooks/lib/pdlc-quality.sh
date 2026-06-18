#!/bin/bash
# hooks/lib/pdlc-quality.sh — Unified spec quality report
#
# Runs all quality checks (lifecycle, placeholder, cross-reference,
# lint, semantic, and Product Skeptic) and produces a consolidated report.
#
# Host adapter / Ralph driver reuse:
# Example call sequence for host /loop or Ralph driver:
#   pdlc_quality_report
#   (used in review + outer for portable core; Ralph/loop/Grok/Cursor reuse)
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-quality.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all quality check libraries
source "${SCRIPT_DIR}/pdlc-lifecycle.sh"
source "${SCRIPT_DIR}/pdlc-placeholder.sh"
source "${SCRIPT_DIR}/pdlc-xref.sh"
source "${SCRIPT_DIR}/pdlc-lint.sh"
source "${SCRIPT_DIR}/pdlc-semantic.sh"
source "${SCRIPT_DIR}/pdlc-skeptic.sh"

# Run all quality checks and produce unified report
# Usage: pdlc_quality_report <spec_dir>
# Returns: 0 if all pass, 1 if any fail
pdlc_quality_report() {
  local spec_dir="$1"
  local overall=0

  echo "=== Spec Quality Report ==="
  echo "Directory: ${spec_dir}"
  echo ""

  # Section 1: Lifecycle State
  echo "--- Lifecycle State ---"
  local state
  state=$(pdlc_lifecycle_get)
  echo "Current state: ${state}"
  if pdlc_lifecycle_validate "$state"; then
    echo "Status: VALID"
  else
    echo "Status: INVALID"
    overall=1
  fi
  echo ""

  # Section 2: Placeholder Detection
  echo "--- Placeholder Detection ---"
  local placeholder_output
  local placeholder_failed=0
  placeholder_output=$(pdlc_placeholder_check "$spec_dir" 2>&1) || {
    placeholder_failed=1
    overall=1
  }
  if [[ $placeholder_failed -eq 0 ]]; then
    echo "Status: CLEAN"
  else
    echo "$placeholder_output" | grep -v "^Placeholders found:" | grep -v "^No placeholders"
    echo "Status: ISSUES FOUND"
  fi
  echo ""

  # Section 3: Cross-Reference Consistency
  echo "--- Cross-Reference Consistency ---"
  local xref_output
  xref_output=$(pdlc_xref_check "$spec_dir" 2>&1) || {
    overall=1
  }
  if echo "$xref_output" | grep -q "All cross-references resolve"; then
    echo "Status: CLEAN"
  elif echo "$xref_output" | grep -q "skipping"; then
    echo "$xref_output" | grep "skipping"
    echo "Status: SKIPPED"
  else
    echo "$xref_output" | grep -v "^Cross-reference gaps:"
    echo "Status: ISSUES FOUND"
    overall=1
  fi
  echo ""

  # Section 4: Structural Lint
  echo "--- Structural Lint ---"
  local lint_output
  lint_output=$(pdlc_lint_check "$spec_dir" 2>&1) || true
  if [[ -z "$lint_output" ]]; then
    echo "Status: CLEAN"
  elif echo "$lint_output" | grep -q "^INFO\|^WARN"; then
    echo "Status: SKIPPED (no lint tool or no artifacts)"
  elif echo "$lint_output" | grep -qE "Lint violations: 0$"; then
    echo "Status: CLEAN"
  else
    echo "$lint_output" | head -10
    echo "Status: ISSUES FOUND"
    overall=1
  fi
  echo ""

  # Section 5: Semantic Validation
  echo "--- Semantic Validation ---"
  local semantic_output
  semantic_output=$(pdlc_semantic_validate "$spec_dir" 2>&1) || true
  if echo "$semantic_output" | grep -q "CLEAN"; then
    echo "Status: CLEAN"
  elif echo "$semantic_output" | grep -q "INFO"; then
    echo "Status: SKIPPED"
  else
    echo "$semantic_output" | head -10
    echo "Status: ISSUES FOUND"
    if echo "$semantic_output" | grep -q "BLOCKER"; then
      overall=1
    fi
  fi
  echo ""

  # Section 6: Product Skeptic
  echo "--- Product Skeptic ---"
  local spec_file="${spec_dir}/spec.md"
  local skeptic_output
  skeptic_output=$(pdlc_skeptic_report "$spec_file" 2>&1) || true
  if echo "$skeptic_output" | grep -q "INFO:No spec file"; then
    echo "Status: SKIPPED (no spec.md)"
  elif echo "$skeptic_output" | grep -q "FAIL:"; then
    echo "$skeptic_output" | grep -E "^(PASS|WARN|FAIL):" | head -10
    echo "Status: ISSUES FOUND"
    overall=1
  elif echo "$skeptic_output" | grep -q "WARN:"; then
    echo "$skeptic_output" | grep -E "^(PASS|WARN|FAIL):" | head -10
    echo "Status: WARNINGS"
  else
    echo "$skeptic_output" | grep -E "^PASS:" | head -10
    echo "Status: CLEAN"
  fi
  echo ""

  # Overall
  echo "=== Overall ==="
  if [[ $overall -eq 0 ]]; then
    echo "Result: PASS"
  else
    echo "Result: FAIL"
  fi

  return $overall
}
