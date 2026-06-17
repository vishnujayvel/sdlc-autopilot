#!/bin/bash
# hooks/lib/pdlc-resource.sh — Portable machine proprioception & resource governance
#
# Provides pre-execution guards, drain/backpressure, and cleanup for test
# processes and memory to prevent unbounded fan-out / zombie accumulation
# (see GitHub #53: 642 zombies, 93.5 GB OOM crash).
#
# Core logic extracted here for reuse across outer-loop (autonomous) and
# future host adapters / in-skill paths (prompts delegate to Director for checks).
#
# Host adapter / Ralph driver reuse:
# Example call sequence for host /loop or Ralph driver:
#   pdlc_resource_check / pdlc_get_available_memory_mb / pdlc_drain_test_processes
#   (used in director/outer: if ! pdlc_resource_check ... ; Ralph/loop/Grok/Cursor reuse)
#
# Sourced by pdlc-outer-loop.sh (and optionally director for prompt injection).
#   source "$(dirname "$0")/lib/pdlc-resource.sh"
#
# Environment (all PDLC_ prefixed, documented):
#   PDLC_MIN_FREE_MEM_MB     — Abort/skip dispatch if avail < this (default 2048)
#   PDLC_MAX_TEST_PROCS      — Max concurrent test procs before pressure (default 1 for serialize)
#   PDLC_TEST_PROC_PATTERN   — pgrep -f pattern for test binaries (default cross-lang)
#   PDLC_DRAIN_TIMEOUT_S     — Max secs to wait for test drain (default 60)
#   PDLC_RESOURCE_CRITICAL_MB — Critical threshold for circuit breaker (default 512)
#
# Functions (all return 0 on success/info; use output + exit status for decisions):
#   pdlc_get_available_memory_mb
#   pdlc_count_test_processes
#   pdlc_resource_check                # prints status; returns 0=OK, 1=pressure
#   pdlc_drain_test_processes [timeout_s]
#   pdlc_cleanup_test_processes [mode] # mode=safe|force ; always returns 0
#   pdlc_resource_pressure_critical    # returns 0 if critical (for breakers)
#
# Conventions: set -euo in libs; local ONLY inside function bodies;
# PDLC_ envs; no yq; awk for any parsing; always portable (mac+linux).
# This lib is observer-style: does not mutate state except explicit cleanup.
# New-design friendly: small, pure-ish, reusable in Ralph/loop drivers.

set -euo pipefail

RESOURCE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults (override via PDLC_* env)
PDLC_MIN_FREE_MEM_MB="${PDLC_MIN_FREE_MEM_MB:-2048}"
PDLC_MAX_TEST_PROCS="${PDLC_MAX_TEST_PROCS:-1}"
PDLC_TEST_PROC_PATTERN="${PDLC_TEST_PROC_PATTERN:-\\.test$|\\.test |go test|pytest|jest |vitest|mocha |test runner|rspec |cargo test}"
PDLC_DRAIN_TIMEOUT_S="${PDLC_DRAIN_TIMEOUT_S:-60}"
PDLC_RESOURCE_CRITICAL_MB="${PDLC_RESOURCE_CRITICAL_MB:-512}"

# Get available memory in MB (free + inactive on mac for headroom; available on linux)
# Portable: vm_stat (macOS) or free (linux) or /proc/meminfo fallback.
# Output: integer MB or 0 on failure.
pdlc_get_available_memory_mb() {
  local os
  os="$(uname -s 2>/dev/null || echo unknown)"

  if [[ "$os" == "Darwin" ]]; then
    # macOS: vm_stat reports pages; page size typically 16384 on Apple silicon
    local page_size free_pages inactive_pages
    page_size=$(vm_stat 2>/dev/null | awk '/page size of/ {gsub(/\./,""); print $8}' | head -1) || page_size=16384
    [[ -z "$page_size" || "$page_size" -eq 0 ]] && page_size=16384
    free_pages=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub(/\./,""); print $3}' | head -1) || free_pages=0
    inactive_pages=$(vm_stat 2>/dev/null | awk '/Pages inactive/ {gsub(/\./,""); print $3}' | head -1) || inactive_pages=0
    # Use free + inactive for realistic available under pressure
    echo $(( (free_pages + inactive_pages) * page_size / 1024 / 1024 ))
    return 0
  elif command -v free >/dev/null 2>&1; then
    # Linux: available column is best (accounts buffers/cache)
    local avail
    avail=$(free -m 2>/dev/null | awk '/Mem:/ {print $7}' | head -1) || avail=0
    echo "${avail:-0}"
    return 0
  else
    # Fallback: try /proc/meminfo (MemAvailable)
    if [[ -r /proc/meminfo ]]; then
      local kb
      kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null | head -1) || kb=0
      echo $(( ${kb:-0} / 1024 ))
      return 0
    fi
  fi
  echo "0"
}

# Count processes matching test patterns (zombies from prior uncoordinated runs).
# Uses pgrep -f for command line match (covers go test binaries like foo.test, node test, etc).
# Excludes obvious false positives (the guard script itself).
# Output: integer count.
pdlc_count_test_processes() {
  local pattern="$PDLC_TEST_PROC_PATTERN"
  # pgrep may return nothing; always produce number
  local count
  count=$(pgrep -f "$pattern" 2>/dev/null | wc -l | tr -d '[:space:]') || count=0
  # Guard against counting the resource check or outer itself (rare)
  # If pattern too broad, user can tighten PDLC_TEST_PROC_PATTERN
  echo "${count:-0}"
}

# Core pre-dispatch guard (P1 proprioception).
# Returns 0 if OK to proceed (memory + test proc limits satisfied).
# Prints one-line status for logging (caller can capture or ignore).
# Env-driven thresholds allow project-specific tuning (e.g. large test binaries).
pdlc_resource_check() {
  local avail procs status
  avail=$(pdlc_get_available_memory_mb)
  procs=$(pdlc_count_test_processes)

  if [[ "$avail" -lt "$PDLC_MIN_FREE_MEM_MB" ]]; then
    status="PRESSURE:memory:${avail}MB<${PDLC_MIN_FREE_MEM_MB}MB"
    echo "$status procs=${procs}"
    return 1
  fi
  if [[ "$procs" -gt "$PDLC_MAX_TEST_PROCS" ]]; then
    status="PRESSURE:procs:${procs}>${PDLC_MAX_TEST_PROCS}"
    echo "$status avail=${avail}MB"
    return 1
  fi

  echo "OK:avail=${avail}MB procs=${procs}"
  return 0
}

# Backpressure / drain: wait until test procs <= max or timeout.
# Used between batches (P4) so Director does not dispatch while prior tests linger.
# Prints progress; returns 0 if drained, 1 on timeout (non-fatal).
pdlc_drain_test_processes() {
  local timeout_s="${1:-$PDLC_DRAIN_TIMEOUT_S}"
  local start elapsed procs
  start=$(date +%s 2>/dev/null || echo 0)

  while true; do
    procs=$(pdlc_count_test_processes)
    if [[ "$procs" -le "$PDLC_MAX_TEST_PROCS" ]]; then
      echo "DRAIN:complete procs=${procs}"
      return 0
    fi
    elapsed=$(($(date +%s 2>/dev/null || echo 0) - start))
    if [[ "$elapsed" -ge "$timeout_s" ]]; then
      echo "DRAIN:timeout after ${timeout_s}s (procs=${procs})"
      return 1
    fi
    echo "DRAIN:waiting procs=${procs} (${elapsed}s/${timeout_s}s)..."
    sleep 2
  done
}

# Safe(ish) cleanup of known test processes (P5 + crash recovery).
# mode=safe (SIGTERM then wait) or force (SIGKILL).
# Never fails the caller (always exit 0); used in traps and post-session.
# Only acts on PDLC_TEST_PROC_PATTERN to limit blast radius.
pdlc_cleanup_test_processes() {
  local mode="${1:-safe}"
  local procs_before
  procs_before=$(pdlc_count_test_processes)
  if [[ "$procs_before" -eq 0 ]]; then
    return 0
  fi

  if [[ "$mode" == "force" ]]; then
    pkill -9 -f "$PDLC_TEST_PROC_PATTERN" 2>/dev/null || true
  else
    pkill -f "$PDLC_TEST_PROC_PATTERN" 2>/dev/null || true
    sleep 1
    # second chance for stragglers
    local remaining
    remaining=$(pdlc_count_test_processes)
    if [[ "$remaining" -gt 0 ]]; then
      pkill -9 -f "$PDLC_TEST_PROC_PATTERN" 2>/dev/null || true
    fi
  fi

  local procs_after
  procs_after=$(pdlc_count_test_processes)
  echo "CLEANUP:${mode} before=${procs_before} after=${procs_after}"
  return 0
}

# Critical pressure detector for enhanced circuit breakers (P6).
# Returns 0 (true) if memory below critical or procs way over.
# Outer loop calls this to decide hard stop + state save.
pdlc_resource_pressure_critical() {
  local avail procs
  avail=$(pdlc_get_available_memory_mb)
  procs=$(pdlc_count_test_processes)
  if [[ "$avail" -lt "$PDLC_RESOURCE_CRITICAL_MB" ]] || [[ "$procs" -gt $((PDLC_MAX_TEST_PROCS * 3)) ]]; then
    return 0
  fi
  return 1
}

# End of pdlc-resource.sh — reusable proprioception primitive.
# In new-design (Ralph/loop): host driver can call these before subagent dispatch.
