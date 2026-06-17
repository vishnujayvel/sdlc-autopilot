#!/bin/bash
# hooks/lib/pdlc-semantic.sh — Semantic spec validation
#
# Deterministic validation checking completeness and correctness.
# Coherence (LLM-driven) is a future enhancement — see Dimension 3 note below.
# Read-only Observer: reports findings, never blocks.
#
# Host adapter / Ralph driver reuse:
# Example call sequence for host /loop or Ralph driver:
#   pdlc_semantic_validate
#   (used in quality + critics for portable core; Ralph/loop/Grok/Cursor reuse)
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-semantic.sh"
# Depends on: pdlc-state.sh, pdlc-placeholder.sh, pdlc-xref.sh

set -euo pipefail

SEMANTIC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! declare -f pdlc_placeholder_check &>/dev/null; then
  source "${SEMANTIC_LIB_DIR}/pdlc-placeholder.sh"
fi
if ! declare -f pdlc_xref_check &>/dev/null; then
  source "${SEMANTIC_LIB_DIR}/pdlc-xref.sh"
fi

# Semantic validation severity levels
PDLC_SEVERITY_BLOCKER="BLOCKER"
PDLC_SEVERITY_MAJOR="MAJOR"
PDLC_SEVERITY_MINOR="MINOR"

# Run semantic validation against spec artifacts
# Usage: pdlc_semantic_validate <spec_dir>
# Output: findings as severity:dimension:description lines
# Returns: 0 always (Observer — never fails)
pdlc_semantic_validate() {
  local spec_dir="${1:-}"
  local findings=""

  if [[ ! -d "$spec_dir" ]]; then
    echo "INFO:No spec directory found"
    return 0
  fi

  # Dimension 1: Completeness — requirements have tasks (deterministic)
  local xref_output
  xref_output=$(pdlc_xref_check "$spec_dir" 2>/dev/null) || true
  if echo "$xref_output" | grep -q "UNREFERENCED\|ORPHANED"; then
    local gap_count
    gap_count=$(echo "$xref_output" | grep -c "UNREFERENCED\|ORPHANED" 2>/dev/null || echo "0")
    gap_count="${gap_count//[[:space:]]/}"
    findings="${findings}${PDLC_SEVERITY_MAJOR}:completeness:${gap_count} cross-reference gaps found (requirements without tasks or orphaned references)"$'\n'
  fi

  # Dimension 2: Correctness — no placeholders remain (deterministic)
  local placeholder_output
  placeholder_output=$(pdlc_placeholder_check "$spec_dir" 2>/dev/null) || true
  if [[ -n "$placeholder_output" ]] && ! echo "$placeholder_output" 2>/dev/null | grep -q "^$"; then
    # Check if there are actual findings (not just empty output)
    local placeholder_count
    placeholder_count=$(echo "$placeholder_output" | grep -c ":" 2>/dev/null || echo "0")
    placeholder_count="${placeholder_count//[[:space:]]/}"
    if [[ "$placeholder_count" -gt 0 ]]; then
      findings="${findings}${PDLC_SEVERITY_BLOCKER}:correctness:${placeholder_count} unresolved placeholders found in spec artifacts"$'\n'
    fi
  fi

  # Dimension 3: Coherence — future enhancement
  # NOTE: LLM-based coherence check removed; claude -p cannot read local files
  # from the prompt alone. Revisit when file content can be injected or when a
  # deterministic coherence heuristic is available.

  # Output findings
  if [[ -n "$findings" ]]; then
    echo "$findings" | sed '/^$/d'
    echo "Semantic findings: $(echo "$findings" | sed '/^$/d' | wc -l | tr -d ' ')" >&2
  else
    echo "CLEAN"
  fi

  return 0
}
