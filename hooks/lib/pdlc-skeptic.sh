#!/bin/bash
# hooks/lib/pdlc-skeptic.sh — Product Skeptic 5-lens spec quality checks
#
# Deterministic checks across 5 lenses: Value, Feasibility, Usability,
# Viability, Ethics. Each lens inspects spec.md for specific structural
# markers and produces a PASS/WARN/FAIL result.
# Read-only Observer: reports findings, never blocks.
#
# Host adapter / Ralph driver reuse:
# Example call sequence for host /loop or Ralph driver:
#   pdlc_skeptic_check_value / pdlc_skeptic_check_feasibility / ... / pdlc_skeptic_report
#   (P1 skeptic per pdlc-goal; used in quality + director for portable core; Ralph/loop/Grok/Cursor reuse)
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-skeptic.sh"
# Depends on: pdlc-state.sh

set -euo pipefail

SKEPTIC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! declare -f pdlc_get_field &>/dev/null; then
  source "${SKEPTIC_LIB_DIR}/pdlc-state.sh"
fi

# Vague language word list (pipe-separated for grep -iE)
# Configurable via environment variable
PDLC_SKEPTIC_VAGUE_WORDS="${PDLC_SKEPTIC_VAGUE_WORDS:-fast|scalable|robust|intuitive|efficient|performant|secure|reliable}"

# ──────────────────────────────────────────────────────────
# Lens 1: Value — measurable success criteria
# ──────────────────────────────────────────────────────────

# Check that spec has measurable success criteria (SC- markers)
# and flags vague language in those criteria.
# Usage: pdlc_skeptic_check_value <spec_file>
# Output: STATUS:value:details
# Returns: 0 always (Observer)
pdlc_skeptic_check_value() {
  local spec_file="${1:-}"

  if [[ ! -f "$spec_file" ]]; then
    echo "INFO:value:spec file not found"
    return 0
  fi

  # Count success criteria markers
  local sc_count
  sc_count=$(grep -c "SC-" "$spec_file" 2>/dev/null || echo "0")
  sc_count="${sc_count//[[:space:]]/}"

  if [[ "$sc_count" -eq 0 ]]; then
    echo "FAIL:value:no success criteria found"
    return 0
  fi

  # Check for vague language in success criteria lines
  local vague_lines
  vague_lines=$(grep "SC-" "$spec_file" 2>/dev/null | grep -iE "(${PDLC_SKEPTIC_VAGUE_WORDS})" 2>/dev/null || true)

  if [[ -n "$vague_lines" ]]; then
    # Extract the vague words found
    local vague_found
    vague_found=$(echo "$vague_lines" | grep -ioE "(${PDLC_SKEPTIC_VAGUE_WORDS})" 2>/dev/null | sort -uf | tr '\n' ',' | sed 's/,$//')
    echo "WARN:value:vague language in success criteria: ${vague_found}"
    return 0
  fi

  echo "PASS:value:${sc_count} success criteria found"
  return 0
}

# ──────────────────────────────────────────────────────────
# Lens 2: Feasibility — testable acceptance scenarios
# ──────────────────────────────────────────────────────────

# Check that spec has acceptance scenarios in Given/When/Then format.
# Usage: pdlc_skeptic_check_feasibility <spec_file>
# Output: STATUS:feasibility:details
# Returns: 0 always (Observer)
pdlc_skeptic_check_feasibility() {
  local spec_file="${1:-}"

  if [[ ! -f "$spec_file" ]]; then
    echo "INFO:feasibility:spec file not found"
    return 0
  fi

  local scenario_count
  scenario_count=$(grep -c '\*\*Given\*\*' "$spec_file" 2>/dev/null || echo "0")
  scenario_count="${scenario_count//[[:space:]]/}"

  if [[ "$scenario_count" -eq 0 ]]; then
    echo "WARN:feasibility:no acceptance scenarios (Given/When/Then) found"
    return 0
  fi

  echo "PASS:feasibility:${scenario_count} acceptance scenarios found"
  return 0
}

# ──────────────────────────────────────────────────────────
# Lens 3: Usability — user stories with actors
# ──────────────────────────────────────────────────────────

# Check that spec has user stories with actor descriptions.
# Usage: pdlc_skeptic_check_usability <spec_file>
# Output: STATUS:usability:details
# Returns: 0 always (Observer)
pdlc_skeptic_check_usability() {
  local spec_file="${1:-}"

  if [[ ! -f "$spec_file" ]]; then
    echo "INFO:usability:spec file not found"
    return 0
  fi

  # Check for User Story headers
  local story_count
  story_count=$(grep -c "### .*User Story" "$spec_file" 2>/dev/null || echo "0")
  story_count="${story_count//[[:space:]]/}"

  if [[ "$story_count" -eq 0 ]]; then
    echo "WARN:usability:no user stories found"
    return 0
  fi

  # Check for actor descriptions ("As a" or "As an")
  local actor_count
  actor_count=$(grep -cE "As an? " "$spec_file" 2>/dev/null || echo "0")
  actor_count="${actor_count//[[:space:]]/}"

  if [[ "$actor_count" -eq 0 ]]; then
    echo "WARN:usability:user stories found but no actor descriptions (As a/an)"
    return 0
  fi

  echo "PASS:usability:${story_count} user stories with actors found"
  return 0
}

# ──────────────────────────────────────────────────────────
# Lens 4: Viability — bounded scope
# ──────────────────────────────────────────────────────────

# Check that spec has bounded scope (Assumptions, Constraints, or Scope section).
# Usage: pdlc_skeptic_check_viability <spec_file>
# Output: STATUS:viability:details
# Returns: 0 always (Observer)
pdlc_skeptic_check_viability() {
  local spec_file="${1:-}"

  if [[ ! -f "$spec_file" ]]; then
    echo "INFO:viability:spec file not found"
    return 0
  fi

  # Check for scope-bounding sections
  local scope_found=0
  local scope_markers=""

  if grep -q "^## Assumptions\|^### Assumptions" "$spec_file" 2>/dev/null; then
    scope_found=1
    scope_markers="Assumptions"
  fi
  if grep -q "^## Constraints\|^### Constraints" "$spec_file" 2>/dev/null; then
    scope_found=1
    scope_markers="${scope_markers:+${scope_markers}, }Constraints"
  fi
  if grep -q "^## Scope\|^### Scope" "$spec_file" 2>/dev/null; then
    scope_found=1
    scope_markers="${scope_markers:+${scope_markers}, }Scope"
  fi

  if [[ "$scope_found" -eq 0 ]]; then
    echo "WARN:viability:no scope-bounding sections found (Assumptions, Constraints, or Scope)"
    return 0
  fi

  echo "PASS:viability:scope bounded by ${scope_markers}"
  return 0
}

# ──────────────────────────────────────────────────────────
# Lens 5: Ethics — edge cases identified
# ──────────────────────────────────────────────────────────

# Check that spec has edge cases section with content.
# Usage: pdlc_skeptic_check_ethics <spec_file>
# Output: STATUS:ethics:details
# Returns: 0 always (Observer)
pdlc_skeptic_check_ethics() {
  local spec_file="${1:-}"

  if [[ ! -f "$spec_file" ]]; then
    echo "INFO:ethics:spec file not found"
    return 0
  fi

  # Check for Edge Cases section
  if ! grep -q "### Edge Cases\|## Edge Cases" "$spec_file" 2>/dev/null; then
    echo "WARN:ethics:no edge cases section found"
    return 0
  fi

  # Check that Edge Cases section has content (at least one list item or paragraph after header)
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
    echo "WARN:ethics:edge cases section is empty"
    return 0
  fi

  echo "PASS:ethics:${edge_content} edge cases identified"
  return 0
}

# ──────────────────────────────────────────────────────────
# Report: run all 5 lenses
# ──────────────────────────────────────────────────────────

# Run all 5 Product Skeptic lenses against a spec file.
# Usage: pdlc_skeptic_report <spec_file>
# Output: per-lens results as STATUS:lens:details, summary line
# Returns: 0 always (Observer — never fails)
pdlc_skeptic_report() {
  local spec_file="${1:-}"

  if [[ ! -f "$spec_file" ]]; then
    echo "INFO:No spec file found for skeptic analysis"
    return 0
  fi

  local results=""
  local fail_count=0
  local warn_count=0

  # Run each lens
  local lens_result

  lens_result=$(pdlc_skeptic_check_value "$spec_file")
  results="${results}${lens_result}"$'\n'
  [[ "$lens_result" == FAIL:* ]] && fail_count=$((fail_count + 1))
  [[ "$lens_result" == WARN:* ]] && warn_count=$((warn_count + 1))

  lens_result=$(pdlc_skeptic_check_feasibility "$spec_file")
  results="${results}${lens_result}"$'\n'
  [[ "$lens_result" == FAIL:* ]] && fail_count=$((fail_count + 1))
  [[ "$lens_result" == WARN:* ]] && warn_count=$((warn_count + 1))

  lens_result=$(pdlc_skeptic_check_usability "$spec_file")
  results="${results}${lens_result}"$'\n'
  [[ "$lens_result" == FAIL:* ]] && fail_count=$((fail_count + 1))
  [[ "$lens_result" == WARN:* ]] && warn_count=$((warn_count + 1))

  lens_result=$(pdlc_skeptic_check_viability "$spec_file")
  results="${results}${lens_result}"$'\n'
  [[ "$lens_result" == FAIL:* ]] && fail_count=$((fail_count + 1))
  [[ "$lens_result" == WARN:* ]] && warn_count=$((warn_count + 1))

  lens_result=$(pdlc_skeptic_check_ethics "$spec_file")
  results="${results}${lens_result}"$'\n'
  [[ "$lens_result" == FAIL:* ]] && fail_count=$((fail_count + 1))
  [[ "$lens_result" == WARN:* ]] && warn_count=$((warn_count + 1))

  # Output results
  echo "$results" | sed '/^$/d'

  # Summary
  local total_findings=$((fail_count + warn_count))
  echo "Skeptic findings: ${total_findings} (${fail_count} fail, ${warn_count} warn)" >&2

  return 0
}
