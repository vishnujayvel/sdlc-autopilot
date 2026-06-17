#!/usr/bin/env bats
# tests/unit/pdlc-resource.bats — Unit tests for hooks/lib/pdlc-resource.sh (#53 portable governance)
# Portable mac+linux cases for memory, procs, check, pressure, drain, cleanup.
# Dogfood: iter on existing #53 (P0 verification); skeptic on edge (fallbacks, 0s timeout, no-op, env force, stub no sidefx); dual-critic self-review of cases pre-write (portable, no real kills, full surface, trap note); batch edits; resource ok (stubs).
# Uses tests/helpers/common-setup.bash pattern (temp fixtures + export/override + direct func after source; no create_handoff). ERR trap N/A (pure unit); set -euo inherited ok from lib.

load ../helpers/common-setup

setup() {
  TEST_WORK_DIR="$(mktemp -d)"
  source "${HOOKS_DIR}/lib/pdlc-resource.sh"
}

teardown() {
  rm -rf "${TEST_WORK_DIR}"
}

# Helper (local inside func per CLAUDE.md): create stub bin dir for pgrep/pkill/sleep/uname/free (portable mock, no system side effects)
create_stub_bin() {
  local d="${TEST_WORK_DIR}/stubbin"
  mkdir -p "$d"
  # Safe no-op stubs for pkill/sleep (cleanup/drain never fail, fast tests)
  for c in pkill sleep; do
    cat >"$d/$c" <<'S'
#!/bin/sh
exit 0
S
    chmod +x "$d/$c"
  done
  echo "$d"
}

# ──────────────────────────────────────────────────────────
# pdlc_get_available_memory_mb (mac + linux paths, numeric or fallback)
# ──────────────────────────────────────────────────────────

@test "pdlc_get_available_memory_mb: returns numeric integer >=0 (real mac/Darwin path)" {
  run pdlc_get_available_memory_mb
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "pdlc_get_available_memory_mb: linux free path yields expected numeric" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/uname" <<'S'
#!/bin/sh
echo "Linux"
S
  cat >"$stubdir/free" <<'S'
#!/bin/sh
# linux free -m Mem: line; $7 = available
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:          32000       12000        4000         200       16000        8000"
S
  chmod +x "$stubdir/uname" "$stubdir/free"
  PATH="$stubdir:$PATH" run pdlc_get_available_memory_mb
  [[ "$status" -eq 0 ]]
  [[ "$output" == "8000" ]]
}

@test "pdlc_get_available_memory_mb: linux without free uses /proc/meminfo or returns 0" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/uname" <<'S'
#!/bin/sh
echo "Linux"
S
  # No 'free' in stub PATH; lib falls through to /proc/meminfo on Linux CI, else 0
  chmod +x "$stubdir/uname"
  PATH="$stubdir:$PATH" run pdlc_get_available_memory_mb
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ ^[0-9]+$ ]]
  if [[ ! -r /proc/meminfo ]]; then
    [[ "$output" == "0" ]]
  fi
}

# ──────────────────────────────────────────────────────────
# pdlc_count_test_processes (counts node/python/pytest etc., numeric)
# ──────────────────────────────────────────────────────────

@test "pdlc_count_test_processes: returns numeric >=0 (real pgrep)" {
  run pdlc_count_test_processes
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "pdlc_count_test_processes: respects PDLC_TEST_PROC_PATTERN (unlikely pattern = 0)" {
  PDLC_TEST_PROC_PATTERN="nonexistent-pdlc-test-proc-xyz123" run pdlc_count_test_processes
  [[ "$status" -eq 0 ]]
  [[ "$output" == "0" ]]
}

@test "pdlc_count_test_processes: stubbed pgrep -f count is numeric and matches lines" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/pgrep" <<'S'
#!/bin/sh
# return 4 matches for test pattern (simulates node|pytest etc)
printf '111\n222\n333\n444\n'
S
  chmod +x "$stubdir/pgrep"
  PATH="$stubdir:$PATH" PDLC_TEST_PROC_PATTERN="pytest|node" run pdlc_count_test_processes
  [[ "$status" -eq 0 ]]
  [[ "$output" == "4" ]]
}

# ──────────────────────────────────────────────────────────
# pdlc_resource_check (0 on ok, 1 on pressure; respects PDLC_MIN_FREE_MEM_MB / PDLC_MAX_TEST_PROCS)
# ──────────────────────────────────────────────────────────

@test "pdlc_resource_check: returns 0 + OK: when mem/procs under thresholds (env relaxed)" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/pgrep" <<'S'
#!/bin/sh
# 0 procs
S
  chmod +x "$stubdir/pgrep"
  PDLC_MIN_FREE_MEM_MB=1 \
  PDLC_MAX_TEST_PROCS=10 \
  PATH="$stubdir:$PATH" run pdlc_resource_check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK:avail="* ]]
  [[ "$output" == *"procs=0"* ]]
}

@test "pdlc_resource_check: returns 1 + PRESSURE:memory when avail < PDLC_MIN_FREE_MEM_MB" {
  PDLC_MIN_FREE_MEM_MB=999999 run pdlc_resource_check
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"PRESSURE:memory:"* ]]
  [[ "$output" == *"<999999MB"* ]]
}

@test "pdlc_resource_check: returns 1 + PRESSURE:procs when procs > PDLC_MAX_TEST_PROCS" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/pgrep" <<'S'
#!/bin/sh
printf 'a\nb\nc\n'
S
  chmod +x "$stubdir/pgrep"
  PDLC_MIN_FREE_MEM_MB=1 \
  PDLC_MAX_TEST_PROCS=1 \
  PATH="$stubdir:$PATH" run pdlc_resource_check
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"PRESSURE:procs:3>1"* ]]
}

# ──────────────────────────────────────────────────────────
# pdlc_resource_pressure_critical (true=0 / false=1)
# ──────────────────────────────────────────────────────────

@test "pdlc_resource_pressure_critical: returns 1 (not critical) under relaxed thresholds" {
  PDLC_RESOURCE_CRITICAL_MB=1 \
  PDLC_MAX_TEST_PROCS=100 \
  run pdlc_resource_pressure_critical
  [[ "$status" -eq 1 ]]
}

@test "pdlc_resource_pressure_critical: returns 0 (critical) on mem below PDLC_RESOURCE_CRITICAL_MB" {
  PDLC_RESOURCE_CRITICAL_MB=999999 run pdlc_resource_pressure_critical
  [[ "$status" -eq 0 ]]
}

@test "pdlc_resource_pressure_critical: returns 0 (critical) on procs > (MAX*3)" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/pgrep" <<'S'
#!/bin/sh
printf '1\n2\n3\n4\n5\n6\n'
S
  chmod +x "$stubdir/pgrep"
  PDLC_RESOURCE_CRITICAL_MB=999999 \
  PDLC_MAX_TEST_PROCS=1 \
  PATH="$stubdir:$PATH" run pdlc_resource_pressure_critical
  [[ "$status" -eq 0 ]]
}

# ──────────────────────────────────────────────────────────
# pdlc_drain_test_processes + pdlc_cleanup_test_processes (safe vs force; no-op; trap note)
# ──────────────────────────────────────────────────────────

@test "pdlc_drain_test_processes: returns 0 + complete when procs <= MAX (immediate no-op drain)" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/pgrep" <<'S'
#!/bin/sh
# 0 lines = 0 procs
S
  chmod +x "$stubdir/pgrep"
  PDLC_MAX_TEST_PROCS=5 \
  PATH="$stubdir:$PATH" run pdlc_drain_test_processes 30
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"DRAIN:complete procs=0"* ]]
}

@test "pdlc_drain_test_processes: returns 1 + timeout on persistent high procs (timeout_s=0 avoids sleep)" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/pgrep" <<'S'
#!/bin/sh
printf 'x\ny\nz\n'
S
  chmod +x "$stubdir/pgrep"
  PDLC_MAX_TEST_PROCS=0 \
  PATH="$stubdir:$PATH" run pdlc_drain_test_processes 0
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"DRAIN:timeout after 0s (procs=3)"* ]]
}

@test "pdlc_cleanup_test_processes: no-op (0 procs) returns 0 with empty output" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/pgrep" <<'S'
#!/bin/sh
S
  chmod +x "$stubdir/pgrep"
  PATH="$stubdir:$PATH" run pdlc_cleanup_test_processes "safe"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "pdlc_cleanup_test_processes: safe mode always returns 0 and prints CLEANUP:safe (before/after)" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/pgrep" <<'S'
#!/bin/sh
printf 'p1\np2\n'
S
  chmod +x "$stubdir/pgrep"
  PATH="$stubdir:$PATH" run pdlc_cleanup_test_processes "safe"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"CLEANUP:safe before=2 after=2"* ]]
}

@test "pdlc_cleanup_test_processes: force mode always returns 0 and prints CLEANUP:force" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/pgrep" <<'S'
#!/bin/sh
printf 'k1\n'
S
  chmod +x "$stubdir/pgrep"
  PATH="$stubdir:$PATH" run pdlc_cleanup_test_processes "force"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"CLEANUP:force before=1 after=1"* ]]
}

@test "pdlc_cleanup_test_processes: always returns 0 (trap-safe, used in signal/EXIT paths)" {
  local stubdir
  stubdir=$(create_stub_bin)
  cat >"$stubdir/pgrep" <<'S'
#!/bin/sh
printf 'z\n'
S
  chmod +x "$stubdir/pgrep"
  PATH="$stubdir:$PATH" run pdlc_cleanup_test_processes "safe"
  [[ "$status" -eq 0 ]]
  # also force
  PATH="$stubdir:$PATH" run pdlc_cleanup_test_processes "force"
  [[ "$status" -eq 0 ]]
}

# Trap integration note: pdlc_cleanup_test_processes (and drain) are called from traps in
# pdlc-outer-loop.sh (signal cleanup + normal post-actor); always exit 0 so traps never abort.
# See also: outer-loop resource pre-dispatch "SKIPPED due to resource pressure — reviewed artifacts only", critical breaker.

# ──────────────────────────────────────────────────────────
# pdlc_resource_int_or_default (numeric env coercion)
# ──────────────────────────────────────────────────────────

@test "pdlc_resource_int_or_default: accepts valid integer" {
  run pdlc_resource_int_or_default "4096" 2048
  [[ "$status" -eq 0 ]]
  [[ "$output" == "4096" ]]
}

@test "pdlc_resource_int_or_default: non-numeric falls back to default" {
  run pdlc_resource_int_or_default "not-a-number" 2048
  [[ "$status" -eq 0 ]]
  [[ "$output" == "2048" ]]
}

@test "pdlc_resource_int_or_default: empty falls back to default" {
  run pdlc_resource_int_or_default "" 60
  [[ "$status" -eq 0 ]]
  [[ "$output" == "60" ]]
}
