#!/bin/bash
# hooks/lib/pdlc-review.sh — PR review summary generation
#
# Aggregates quality gate results, test counts, and change diffs
# into a structured markdown summary suitable for PR descriptions.
# Read-only Observer: reports findings, never blocks.
#
# Host adapter / Ralph driver reuse:
# Example call sequence for host /loop or Ralph driver:
#   pdlc_review_summary
#   (used after quality/critics in outer for portable core; Ralph/loop/Grok/Cursor reuse)
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-review.sh"
# Depends on: pdlc-quality.sh

set -euo pipefail

REVIEW_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source quality report if not already loaded
if ! declare -f pdlc_quality_report &>/dev/null; then
  source "${REVIEW_LIB_DIR}/pdlc-quality.sh"
fi

# Generate a structured PR review summary
# Usage: pdlc_review_summary <spec_dir>
# Output: markdown-formatted review summary
# Returns: 0 always (Observer — never fails)
pdlc_review_summary() {
  local spec_dir="${1:-}"

  # ── Header ──────────────────────────────────────────────
  local disabled_note=""
  if [[ "${PDLC_DISABLED:-0}" == "1" ]]; then
    disabled_note=" (PDLC_DISABLED=1 — quality checks bypassed)"
  fi

  echo "## PR Review Summary${disabled_note}"
  echo ""

  # ── Section 1: Summary ──────────────────────────────────
  echo "### Summary"
  echo ""

  if [[ -z "$spec_dir" || ! -d "$spec_dir" ]]; then
    echo "No spec directory found — summary unavailable"
    echo ""
  else
    # Count spec artifacts
    local spec_exists=0
    local plan_exists=0
    local tasks_total=0
    local tasks_done=0

    [[ -f "${spec_dir}/spec.md" ]] && spec_exists=1
    [[ -f "${spec_dir}/plan.md" ]] && plan_exists=1

    if [[ -f "${spec_dir}/tasks.md" ]]; then
      tasks_total=$(grep -c '^\- \[' "${spec_dir}/tasks.md" 2>/dev/null || echo "0")
      tasks_total="${tasks_total//[[:space:]]/}"
      tasks_done=$(grep -c '^\- \[x\]' "${spec_dir}/tasks.md" 2>/dev/null || echo "0")
      tasks_done="${tasks_done//[[:space:]]/}"
    fi

    echo "- Spec: $([ "$spec_exists" -eq 1 ] && echo "present" || echo "missing")"
    echo "- Plan: $([ "$plan_exists" -eq 1 ] && echo "present" || echo "missing")"
    echo "- Tasks: ${tasks_done}/${tasks_total} complete"
    echo ""
  fi

  # ── Section 2: Quality Gate ─────────────────────────────
  echo "### Quality Gate"
  echo ""

  if [[ "${PDLC_DISABLED:-0}" == "1" ]]; then
    echo "Quality checks bypassed (PDLC_DISABLED=1)"
    echo ""
  elif [[ -z "$spec_dir" || ! -d "$spec_dir" ]]; then
    echo "No spec directory — quality checks skipped"
    echo ""
  else
    local quality_output
    quality_output=$(pdlc_quality_report "$spec_dir" 2>&1) || true

    # Extract per-section status
    local lifecycle_status placeholder_status xref_status lint_status semantic_status skeptic_status overall_status

    lifecycle_status=$(echo "$quality_output" | awk '/--- Lifecycle/,/^$/' | grep "Status:" | head -1 | awk '{$1=""; print substr($0,2)}') || true
    placeholder_status=$(echo "$quality_output" | awk '/--- Placeholder/,/^$/' | grep "Status:" | head -1 | awk '{$1=""; print substr($0,2)}') || true
    xref_status=$(echo "$quality_output" | awk '/--- Cross-Reference/,/^$/' | grep "Status:" | head -1 | awk '{$1=""; print substr($0,2)}') || true
    lint_status=$(echo "$quality_output" | awk '/--- Structural Lint/,/^$/' | grep "Status:" | head -1 | awk '{$1=""; print substr($0,2)}') || true
    semantic_status=$(echo "$quality_output" | awk '/--- Semantic/,/^$/' | grep "Status:" | head -1 | awk '{$1=""; print substr($0,2)}') || true
    skeptic_status=$(echo "$quality_output" | awk '/--- Product Skeptic/,/^$/' | grep "Status:" | head -1 | awk '{$1=""; print substr($0,2)}') || true
    overall_status=$(echo "$quality_output" | grep "^Result:" | awk '{$1=""; print substr($0,2)}') || true

    echo "| Check | Status |"
    echo "|-------|--------|"
    echo "| Lifecycle | ${lifecycle_status:-N/A} |"
    echo "| Placeholder | ${placeholder_status:-N/A} |"
    echo "| Cross-reference | ${xref_status:-N/A} |"
    echo "| Lint | ${lint_status:-N/A} |"
    echo "| Semantic | ${semantic_status:-N/A} |"
    echo "| Skeptic | ${skeptic_status:-N/A} |"
    echo ""
    echo "Overall: **${overall_status:-UNKNOWN}**"
    echo ""
  fi

  # ── Section 3: Tests ────────────────────────────────────
  echo "### Tests"
  echo ""

  local test_count=0
  if command -v bats &>/dev/null; then
    # Count test files and individual tests
    local test_files
    test_files=$(find "${REVIEW_LIB_DIR}/../../tests" -name "*.bats" -type f 2>/dev/null | wc -l | tr -d ' ') || true
    test_count="${test_files:-0}"
    echo "- Test files: ${test_count}"
  else
    echo "- BATS not available — test count unavailable"
  fi
  echo ""

  # ── Section 4: Outstanding Issues ───────────────────────
  echo "### Outstanding Issues"
  echo ""

  local has_issues=0

  # Check for uncommitted changes
  if command -v git &>/dev/null; then
    local changed_files
    changed_files=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ') || true
    if [[ "${changed_files:-0}" -gt 0 ]]; then
      echo "- ${changed_files} files with uncommitted changes"
      has_issues=1
    fi
  fi

  if [[ "$has_issues" -eq 0 ]]; then
    echo "- All checks clean"
  fi

  echo ""

  return 0
}
