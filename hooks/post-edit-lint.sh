#!/bin/bash
# =============================================================================
# post-edit-lint.sh — Auto-Format After Edits
# =============================================================================
#
# Automatically formats files after Claude Code writes or edits them.
# Detects the project's formatter and runs it on the modified file.
#
# HOW IT WORKS
# ─────────────
# 1. Receives the modified file path from Claude Code via stdin JSON
# 2. Determines the file extension
# 3. Walks up the directory tree to detect which formatter is available:
#    - .js/.ts/.jsx/.tsx/.json/.css/.md/.html → prettier
#    - .py                                    → ruff format (fallback: black)
#    - .go                                    → gofmt
#    - .rs                                    → rustfmt
# 4. Runs the detected formatter on the file
# 5. Exits silently if no formatter is found (never blocks execution)
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
#           "command": "bash /path/to/post-edit-lint.sh"
#         }]
#       }]
#     }
#   }
#
# ENVIRONMENT VARIABLES
# ─────────────────────
#   PDLC_LINT_DISABLED  — Set to "1" to skip formatting entirely.
#   PDLC_LINT_VERBOSE   — Set to "1" to print formatter output.
#
# STDIN
# ─────
#   Claude Code passes a JSON object on stdin with tool call details.
#   We extract the file_path from the tool input.
#
# EXIT CODES
# ──────────
#   Always exits 0 (formatting should never block Claude Code).
#
# =============================================================================

set -eo pipefail
trap 'exit 0' ERR

# --- Check if disabled ---
if [[ "${PDLC_LINT_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

# --- Extract file path from stdin JSON ---
# Claude Code passes tool input as JSON on stdin for PostToolUse hooks.
# The file path is in .tool_input.file_path for Write/Edit tools.
extract_file_path() {
  local input
  input="$(cat)"

  # Try to extract file_path using python (most reliable)
  if command -v python3 &>/dev/null; then
    echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Try tool_input.file_path (Write/Edit tools)
    fp = data.get('tool_input', {}).get('file_path', '')
    if fp:
        print(fp)
    else:
        # Try tool_input.path
        print(data.get('tool_input', {}).get('path', ''))
except:
    pass
" 2>/dev/null
    return
  fi

  # Fallback: grep for file_path in JSON
  echo "$input" | grep -oP '"file_path"\s*:\s*"([^"]+)"' | head -1 | sed 's/.*"file_path"\s*:\s*"\([^"]*\)".*/\1/' 2>/dev/null
}

FILE_PATH="$(extract_file_path)"

# No file path found — nothing to format
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# File doesn't exist (might have been deleted)
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# --- Determine file extension ---
EXT="${FILE_PATH##*.}"
EXT="${EXT,,}"  # lowercase

# --- Detect and run formatter ---
format_js_family() {
  # Walk up to find node_modules/.bin/prettier or npx
  local dir
  dir="$(dirname "$FILE_PATH")"
  while [[ "$dir" != "/" ]]; do
    if [[ -x "${dir}/node_modules/.bin/prettier" ]]; then
      "${dir}/node_modules/.bin/prettier" --write "$FILE_PATH" 2>/dev/null
      return
    fi
    dir="$(dirname "$dir")"
  done

  # Fallback: try global prettier
  if command -v prettier &>/dev/null; then
    prettier --write "$FILE_PATH" 2>/dev/null
  fi
}

format_python() {
  if command -v ruff &>/dev/null; then
    ruff format "$FILE_PATH" 2>/dev/null
  elif command -v black &>/dev/null; then
    black --quiet "$FILE_PATH" 2>/dev/null
  fi
}

format_go() {
  if command -v gofmt &>/dev/null; then
    gofmt -w "$FILE_PATH" 2>/dev/null
  fi
}

format_rust() {
  if command -v rustfmt &>/dev/null; then
    rustfmt "$FILE_PATH" 2>/dev/null
  fi
}

# --- Route by extension ---
case "$EXT" in
  js|ts|jsx|tsx|mjs|mts|json|css|scss|less|md|mdx|html|yaml|yml)
    format_js_family
    ;;
  py|pyi)
    format_python
    ;;
  go)
    format_go
    ;;
  rs)
    format_rust
    ;;
  *)
    # No formatter for this extension — skip silently
    ;;
esac

# --- Always exit 0 (never block Claude Code) ---
exit 0
