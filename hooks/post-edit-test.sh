#!/bin/bash
# =============================================================================
# post-edit-test.sh — Run Related Tests After Edits
# =============================================================================
#
# Automatically runs tests related to a file after Claude Code modifies it.
# Detects the project's test framework and runs only the relevant tests,
# not the full suite.
#
# HOW IT WORKS
# ─────────────
# 1. Receives the modified file path from Claude Code via stdin JSON
# 2. Skips non-source files (configs, docs, lock files, etc.)
# 3. Detects the test framework by walking up the directory tree:
#    - package.json with vitest/jest/mocha → vitest/jest/mocha
#    - pyproject.toml / pytest.ini         → pytest
#    - go.mod                              → go test
#    - Cargo.toml                          → cargo test
# 4. Locates the test file that corresponds to the modified source file:
#    - foo.ts  → foo.test.ts, foo.spec.ts, __tests__/foo.test.ts
#    - foo.py  → test_foo.py, tests/test_foo.py
#    - foo.go  → foo_test.go (same directory)
# 5. Runs only the related test file (scoped execution)
# 6. Truncates output to last 30 lines to avoid context pollution
#
# INSTALLATION
# ─────────────
# Add to .claude/settings.json under "hooks.PostToolUse":
#
#   {
#     "hooks": {
#       "PostToolUse": [{
#         "matcher": "Write|Edit",
#         "hooks": [{
#           "type": "command",
#           "command": "bash /path/to/post-edit-test.sh"
#         }]
#       }]
#     }
#   }
#
# ENVIRONMENT VARIABLES
# ─────────────────────
#   PDLC_TEST_DISABLED   — Set to "1" to skip test execution entirely.
#   PDLC_TEST_MAX_LINES  — Max output lines (default: 30).
#   PDLC_TEST_TIMEOUT    — Timeout in seconds (default: 30).
#
# STDIN
# ─────
#   Claude Code passes a JSON object on stdin with tool call details.
#   We extract the file_path from the tool input.
#
# EXIT CODES
# ──────────
#   Always exits 0 (test failures are reported but never block Claude Code).
#
# =============================================================================

set -eo pipefail
trap 'exit 0' ERR

# --- Configuration ---
MAX_LINES="${PDLC_TEST_MAX_LINES:-30}"
TIMEOUT_SECS="${PDLC_TEST_TIMEOUT:-30}"

# --- Check if disabled ---
if [[ "${PDLC_TEST_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

# --- Extract file path from stdin JSON ---
extract_file_path() {
  local input
  input="$(cat)"

  if command -v python3 &>/dev/null; then
    echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    fp = data.get('tool_input', {}).get('file_path', '')
    if fp:
        print(fp)
    else:
        print(data.get('tool_input', {}).get('path', ''))
except:
    pass
" 2>/dev/null
    return
  fi

  echo "$input" | grep -oP '"file_path"\s*:\s*"([^"]+)"' | head -1 | sed 's/.*"file_path"\s*:\s*"\([^"]*\)".*/\1/' 2>/dev/null
}

FILE_PATH="$(extract_file_path)"

if [[ -z "$FILE_PATH" ]] || [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# --- Skip non-source files ---
# Don't run tests for config, docs, lock files, or test files themselves
BASENAME="$(basename "$FILE_PATH")"
case "$BASENAME" in
  *.test.*|*.spec.*|test_*|*_test.go|*.lock|*.md|*.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.env*)
    exit 0
    ;;
  package.json|tsconfig.json|pyproject.toml|Cargo.toml|go.mod|Makefile|Dockerfile|*.sh)
    exit 0
    ;;
esac

# --- Detect test framework ---
# Walk up from the file's directory to find project root indicators
detect_framework() {
  local dir
  dir="$(dirname "$FILE_PATH")"

  while [[ "$dir" != "/" ]]; do
    # Node.js projects
    if [[ -f "${dir}/package.json" ]]; then
      if grep -q '"vitest"' "${dir}/package.json" 2>/dev/null; then
        echo "vitest:${dir}"
        return
      elif grep -q '"jest"' "${dir}/package.json" 2>/dev/null; then
        echo "jest:${dir}"
        return
      elif grep -q '"mocha"' "${dir}/package.json" 2>/dev/null; then
        echo "mocha:${dir}"
        return
      fi
    fi

    # Python projects
    if [[ -f "${dir}/pyproject.toml" ]] || [[ -f "${dir}/pytest.ini" ]] || [[ -f "${dir}/setup.cfg" ]]; then
      echo "pytest:${dir}"
      return
    fi

    # Go projects
    if [[ -f "${dir}/go.mod" ]]; then
      echo "go:${dir}"
      return
    fi

    # Rust projects
    if [[ -f "${dir}/Cargo.toml" ]]; then
      echo "cargo:${dir}"
      return
    fi

    dir="$(dirname "$dir")"
  done

  echo "unknown:"
}

# --- Find related test file ---
find_test_file() {
  local source_file="$1"
  local dir
  dir="$(dirname "$source_file")"
  local name
  name="$(basename "$source_file")"
  local stem="${name%.*}"
  local ext="${name##*.}"

  case "$ext" in
    ts|tsx|js|jsx|mts|mjs)
      # Check common test file patterns
      for pattern in \
        "${dir}/${stem}.test.${ext}" \
        "${dir}/${stem}.spec.${ext}" \
        "${dir}/__tests__/${stem}.test.${ext}" \
        "${dir}/../tests/${stem}.test.${ext}" \
        "${dir}/../test/${stem}.test.${ext}"; do
        if [[ -f "$pattern" ]]; then
          echo "$pattern"
          return
        fi
      done
      ;;
    py)
      # Python test patterns
      for pattern in \
        "${dir}/test_${stem}.py" \
        "${dir}/../tests/test_${stem}.py" \
        "${dir}/../test/test_${stem}.py" \
        "${dir}/tests/test_${stem}.py"; do
        if [[ -f "$pattern" ]]; then
          echo "$pattern"
          return
        fi
      done
      ;;
    go)
      # Go tests are in the same directory with _test.go suffix
      local test_file="${dir}/${stem}_test.go"
      if [[ -f "$test_file" ]]; then
        echo "$test_file"
        return
      fi
      ;;
    rs)
      # Rust: tests are usually inline or in tests/ directory
      local test_file="${dir}/../tests/${stem}.rs"
      if [[ -f "$test_file" ]]; then
        echo "$test_file"
        return
      fi
      ;;
  esac

  # No test file found
  echo ""
}

# --- Run tests with timeout and truncated output ---
run_scoped_test() {
  local framework="$1"
  local project_root="$2"
  local test_file="$3"
  local output

  case "$framework" in
    vitest)
      output="$(cd "$project_root" && timeout "$TIMEOUT_SECS" \
        npx vitest run "$test_file" --reporter=verbose 2>&1)" || true
      ;;
    jest)
      output="$(cd "$project_root" && timeout "$TIMEOUT_SECS" \
        npx jest "$test_file" --verbose 2>&1)" || true
      ;;
    mocha)
      output="$(cd "$project_root" && timeout "$TIMEOUT_SECS" \
        npx mocha "$test_file" 2>&1)" || true
      ;;
    pytest)
      output="$(cd "$project_root" && timeout "$TIMEOUT_SECS" \
        python3 -m pytest "$test_file" -x -v 2>&1)" || true
      ;;
    go)
      local pkg_dir
      pkg_dir="$(dirname "$test_file")"
      output="$(cd "$project_root" && timeout "$TIMEOUT_SECS" \
        go test -v "./${pkg_dir#$project_root/}/..." 2>&1)" || true
      ;;
    cargo)
      output="$(cd "$project_root" && timeout "$TIMEOUT_SECS" \
        cargo test 2>&1)" || true
      ;;
    *)
      return
      ;;
  esac

  # Truncate output to last N lines
  if [[ -n "$output" ]]; then
    local line_count
    line_count="$(echo "$output" | wc -l)"
    if [[ "$line_count" -gt "$MAX_LINES" ]]; then
      echo "... (${line_count} lines, showing last ${MAX_LINES})" >&2
      echo "$output" | tail -n "$MAX_LINES" >&2
    else
      echo "$output" >&2
    fi
  fi
}

# --- Main logic ---
main() {
  local framework_info
  framework_info="$(detect_framework)"

  local framework="${framework_info%%:*}"
  local project_root="${framework_info#*:}"

  if [[ "$framework" == "unknown" ]] || [[ -z "$project_root" ]]; then
    exit 0
  fi

  local test_file
  test_file="$(find_test_file "$FILE_PATH")"

  if [[ -z "$test_file" ]]; then
    # No related test file found — skip silently
    exit 0
  fi

  run_scoped_test "$framework" "$project_root" "$test_file"
}

main "$@"

# Always exit 0 — test failures are informational, not blocking
exit 0
