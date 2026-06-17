#!/bin/bash
# hooks/lib/pdlc-lint.sh — Structural markdown lint wrapper
#
# Runs rumdl (or markdownlint-cli2 / markdownlint fallback) against spec artifacts.
# Read-only Observer: reports violations, never blocks operations.
#
# Host adapter / Ralph driver reuse:
# Example call sequence for host /loop or Ralph driver:
#   pdlc_lint_available / pdlc_lint_check
#   (used in quality report + critic for portable core; Ralph/loop/Grok/Cursor reuse)
#
# Sourced by other scripts: source "$(dirname "$0")/lib/pdlc-lint.sh"
# Depends on: pdlc-state.sh

set -euo pipefail

if ! declare -f pdlc_get_field &>/dev/null; then
  source "$(dirname "${BASH_SOURCE[0]}")/pdlc-state.sh"
fi

# Check if a markdown lint tool is available
# Returns 0 if found (sets PDLC_LINT_CMD), 1 if not
pdlc_lint_available() {
  if command -v rumdl &>/dev/null; then
    PDLC_LINT_CMD="rumdl"
    return 0
  fi
  if command -v markdownlint-cli2 &>/dev/null; then
    PDLC_LINT_CMD="markdownlint-cli2"
    return 0
  fi
  if command -v markdownlint &>/dev/null; then
    PDLC_LINT_CMD="markdownlint"
    return 0
  fi
  PDLC_LINT_CMD=""
  return 1
}

# Run structural lint against spec artifacts
# Usage: pdlc_lint_check <spec_dir>
# Output: violations as file:line:rule:message lines, or empty if clean
# Returns: 0 always (Observer — never fails)
pdlc_lint_check() {
  local spec_dir="${1:-}"

  if [[ ! -d "$spec_dir" ]]; then
    echo "INFO:No spec directory found"
    return 0
  fi

  # Check if lint tool is available
  if ! pdlc_lint_available; then
    echo "WARN:No markdown lint tool installed (install rumdl: brew install rumdl)" >&2
    return 0
  fi

  # Collect existing artifact files
  local files=()
  local artifact
  for artifact in spec.md plan.md tasks.md; do
    if [[ -f "${spec_dir}/${artifact}" ]]; then
      files+=("${spec_dir}/${artifact}")
    fi
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "INFO:No spec artifacts found"
    return 0
  fi

  # Run linter
  local output
  case "$PDLC_LINT_CMD" in
    rumdl)
      output=$(rumdl "${files[@]}" 2>&1) || true
      ;;
    markdownlint-cli2)
      output=$(markdownlint-cli2 "${files[@]}" 2>&1) || true
      ;;
    markdownlint)
      output=$(markdownlint "${files[@]}" 2>&1) || true
      ;;
  esac

  if [[ -n "$output" ]]; then
    echo "$output"
    local count
    count=$(echo "$output" | grep -c "." 2>/dev/null || echo "0")
    count="${count//[[:space:]]/}"
    echo "Lint violations: $count" >&2
  fi

  return 0
}
