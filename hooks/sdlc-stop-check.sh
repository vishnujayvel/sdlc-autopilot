#!/bin/bash
# =============================================================================
# sdlc-stop-check.sh - SDLC Stop Guard Hook
# v1.1 - Not yet active
# =============================================================================
#
# Stop hook that prevents Claude from exiting when SDLC tasks are incomplete.
#
# How it works:
#   1. Reads tasks.md from the current project directory
#   2. Counts pending (incomplete) tasks
#   3. Blocks exit if any tasks remain incomplete
#
# Interface:
#   Environment variables:
#     CLAUDE_STOP_REASON - The reason Claude is attempting to stop
#                          (e.g., "user_request", "task_complete", "error")
#
#   Exit codes:
#     0 - Allow stop (all tasks complete or no tasks file found)
#     1 - Block stop (incomplete tasks remain)
#
# =============================================================================

# TODO: Implement in v1.1

# --- Configuration ---
# TASKS_FILE="tasks.md"

# --- Read stop reason ---
# STOP_REASON="${CLAUDE_STOP_REASON:-unknown}"

# --- Locate tasks file ---
# TODO: Implement in v1.1 - find tasks.md in project root or .sdlc/ directory

# --- Parse tasks and count pending ---
# TODO: Implement in v1.1 - parse markdown checkboxes, count [ ] vs [x]

# --- Decision logic ---
# TODO: Implement in v1.1 - if pending > 0 and reason != "error", block exit

# --- Placeholder: allow all stops until implemented ---
exit 0
