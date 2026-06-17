# Audit Prevention Plan

**Date**: 2026-03-18
**Source**: Post-audit investigation of findings F-01, F-02, F-03, and high-severity items from `docs/audit-retrospective-r1-r9.md`
**Purpose**: Prevent recurrence of the quality escapes discovered during the R1-R9 retrospective audit

---

## Root Cause Analysis

### Finding Inventory

| Finding | Description | Category | Severity |
|---------|-------------|----------|----------|
| F-01 | `local` keyword used outside function scope in outer loop (bash 3.2 fatal error) | Testing Gap | Critical |
| F-02 | Dual-critic consensus engine (`pdlc-critic.sh`) never sourced; structured path permanently unreachable | Integration Gap | Critical |
| F-03 | `batch` field never incremented; CriticGate enforcement permanently bypassed | Spec Gap | Critical |
| H-01 | `post-edit-lint.sh` and `post-edit-test.sh` missing `-e` flag and ERR trap | Process Gap | High |
| H-02 | 5 library modules missing from C4 architecture model | Process Gap | High |
| H-03 | `pdlc_count_tasks` and `pdlc_get_mtime` have zero test coverage | Testing Gap | High |

### Category Distribution

| Category | Count | Findings |
|----------|-------|----------|
| **Testing Gap** | 2 | F-01, H-03 |
| **Process Gap** | 2 | H-01, H-02 |
| **Integration Gap** | 1 | F-02 |
| **Spec Gap** | 1 | F-03 |
| **Implementation Gap** | 0 | (contributing factor in F-02 and F-03, but not primary) |

### Systemic Patterns

**Pattern 1: Tests exist but are never executed (F-01).** The e2e tests for the outer loop correctly detect the `local`-outside-function bug, but no CI workflow runs `bats tests/`. The only GitHub Actions workflow is `publish.yml` (release-only, npm publish). Code review (CodeRabbit) catches semantic issues but cannot catch runtime behavior.

**Pattern 2: Unit tests pass in isolation but miss integration wiring (F-02, F-03).** The critic consensus engine has 36 passing unit tests. The director has passing unit tests. But no test verifies that the outer loop's source chain makes `pdlc_critic_consensus` available to the director. Similarly, CriticGate tests hardcode `batch: 2` as a precondition that the outer loop never produces. Components are tested at their boundaries but the contracts between them are untested.

**Pattern 3: Retroactive consistency is never enforced (H-01, H-02, H-03).** When CLAUDE.md conventions were codified, pre-existing hooks were not audited. When the C4 model was created, it was a point-in-time snapshot with no update trigger. When functions were added to existing libraries, test files were not updated. New code gets reviewed; old code is grandfathered in.

**Pattern 4: Abstract spec language masks missing state mutations (F-03).** The spec said "the lifecycle advances" without decomposing that into concrete field changes. The retry path said "increment retry counter" (concrete) and was implemented correctly. The accept path said "advance lifecycle" (abstract) and the batch increment was lost.

---

## Process Improvements

### 1. Testing Gap: CI Must Run the Full Test Suite

**Problem**: Tests exist but are not run before merge. F-01's `local`-outside-function bug was caught by existing e2e tests that were never executed during the PR cycle.

**Process change**:
- Add a GitHub Actions workflow (`ci.yml`) that runs `bats tests/` on every PR targeting `main`.
- The workflow must run on macOS (to use `/bin/bash` 3.2, matching production).
- Gate PR merges on this workflow passing.
- Add ShellCheck (`shellcheck hooks/*.sh hooks/lib/*.sh`) as a CI step. ShellCheck would have flagged `local` outside function scope.

**Concrete deliverable**: `.github/workflows/ci.yml` with jobs for `bats tests/` and `shellcheck`.

### 2. Testing Gap: Coverage Regression Gate

**Problem**: `pdlc_count_tasks` and `pdlc_get_mtime` were added to `pdlc-state.sh` without corresponding tests in `pdlc-state.bats`. No mechanism flags when public functions lack test coverage.

**Process change**:
- Add a CI script that extracts public function names from `hooks/lib/*.sh` (functions not prefixed with `_`) and checks that each has at least one corresponding `@test` in `tests/`.
- This is a coarse coverage gate (name-matching, not line coverage) but catches the zero-coverage case cheaply.

**Concrete deliverable**: `scripts/check-test-coverage.sh` that diffs exported functions against test names.

### 3. Integration Gap: Integration Tests Must Mirror Production Wiring

**Problem**: F-02's dual-critic path is unreachable because `pdlc-critic.sh` is never sourced by the outer loop. Unit tests source each library individually, masking wiring failures. The `declare -f` guard in `pdlc-director.sh:285` always evaluates to false in production.

**Process change**:
- Add a mandatory test category: **wiring tests** that source files in the same order as the production entry point (`pdlc-outer-loop.sh`) and assert that expected functions are declared.
- For every `declare -f` guard in the codebase, require a corresponding test that verifies the guard evaluates to true when the full source chain is loaded.
- Add an integration test for every verdict that is only reachable through the structured path (e.g., `accept-with-caveats`). If the test produces the verdict, the wiring is correct; if not, the source chain is incomplete.

**Concrete deliverable**: `tests/integration/source-chain.bats` with tests like:
```bash
@test "outer loop source chain declares pdlc_critic_consensus" {
  source "${HOOKS_DIR}/lib/pdlc-state.sh"
  source "${HOOKS_DIR}/lib/pdlc-director.sh"
  source "${HOOKS_DIR}/lib/pdlc-session.sh"
  # This must also source pdlc-critic.sh to pass:
  declare -f pdlc_critic_consensus
}
```

### 4. Spec Gap: Require Concrete State Mutations in Acceptance Criteria

**Problem**: F-03's batch increment was lost because the spec said "the lifecycle advances" without naming the fields that change. The retry path was concrete ("increment retry counter") and was implemented correctly; the accept path was abstract and was implemented incompletely.

**Process change**:
- Add a Spec Kit governance rule: **every acceptance scenario that implies state mutation must name the specific HANDOFF.md fields that change and their expected values.**
- Ban abstract lifecycle verbs ("advances", "progresses", "continues") in acceptance criteria unless accompanied by a concrete field-change assertion.
- Add a spec review checklist item: "For each state-mutating acceptance scenario, can I write a BATS assertion that checks the field value? If not, the scenario is underspecified."

**Concrete deliverable**: Update `.specify/extensions/pdlc-spec-review.md` (or create if absent) with the concrete-state-mutation rule. Add to the Spec Kit constitution as a tenet.

### 5. Process Gap: Retroactive Compliance Audits

**Problem**: H-01's post-edit hooks predate the CLAUDE.md conventions and were never audited. H-02's C4 model was a snapshot with no update trigger. Old code is exempt from new rules.

**Process change**:
- When a new convention is added to CLAUDE.md, the PR that adds the convention must include a compliance audit of all existing files. Non-compliant files are either fixed in the same PR or tracked as issues with `tech-debt` label.
- When a new library module is added to `hooks/lib/`, the PR must include an update to `architecture/components.likec4` and `docs/maturity-matrix.md`.
- Add a CI script that cross-references `ls hooks/lib/*.sh` against components listed in `architecture/components.likec4` and fails on divergence.

**Concrete deliverable**: `scripts/check-architecture-sync.sh` and a CLAUDE.md addendum requiring retroactive audits.

---

## Proposed Definition of Done

Every feature MUST pass this checklist before being considered complete. This checklist should be integrated into the Spec Kit pipeline as a mandatory gate.

### Code Quality
- [ ] All `.sh` files use `set -euo pipefail`
- [ ] All hook scripts have `trap '...; exit 0' ERR` (if they document "always exits 0")
- [ ] No `local` keyword used outside function bodies
- [ ] ShellCheck passes with zero errors on all modified `.sh` files
- [ ] No hardcoded paths (use `PDLC_` prefixed env vars with defaults)

### Testing
- [ ] Every new public function has at least one `@test` in the corresponding BATS file
- [ ] Unit tests run and pass: `bats tests/unit/`
- [ ] Integration tests run and pass: `bats tests/integration/`
- [ ] E2e tests run and pass: `bats tests/e2e/`
- [ ] If the feature adds a `declare -f` guard, a wiring test verifies the guard evaluates to true under production source chains
- [ ] If the feature adds cross-component state contracts (e.g., "component A writes field X, component B reads field X"), an integration test verifies the contract end-to-end
- [ ] No public functions in modified libraries have zero test coverage

### Spec Compliance
- [ ] Every acceptance scenario that implies state mutation names the specific fields and expected values
- [ ] No abstract lifecycle verbs ("advances", "continues") without concrete field-change assertions
- [ ] All tasks in `tasks.md` are marked done with commit references

### Architecture
- [ ] If a new library module was added: `architecture/components.likec4` updated
- [ ] If a new library module was added: `docs/maturity-matrix.md` row added
- [ ] If a new hook script was added: architecture model updated
- [ ] Source chain (`source` statements in entry points) matches the architecture model's dependency edges

### Process
- [ ] Full test suite (`bats tests/`) passes (not just the tests for the feature under development)
- [ ] If new CLAUDE.md conventions were added: all existing files audited for compliance
- [ ] PR description lists which Definition of Done items were verified and how

---

## Automation Recommendations

### Priority 1: CI Test Workflow (blocks F-01 class)

**What**: GitHub Actions workflow that runs on every PR.
**Steps**:
1. `shellcheck hooks/*.sh hooks/lib/*.sh` -- catches `local` outside function, missing quotes, etc.
2. `bats tests/unit/` -- unit tests
3. `bats tests/integration/` -- integration tests
4. `bats tests/e2e/` -- e2e tests (stub-based, no API credits)
**Platform**: macOS runner (matches production bash 3.2)
**Gate**: PR merge blocked until all steps pass.
**Effort**: Small (one YAML file)
**Impact**: Would have prevented F-01 entirely.

### Priority 2: Architecture Sync Check (blocks H-02 class)

**What**: CI script that compares `hooks/lib/*.sh` file list against components declared in `architecture/components.likec4`.
**Implementation**:
```bash
# Extract component names from .likec4
likec4_libs=$(grep -oP 'component\s+\K\w+' architecture/components.likec4 | sort)
# Extract actual library names from hooks/lib/
actual_libs=$(ls hooks/lib/pdlc-*.sh | xargs -I{} basename {} .sh | sort)
# Diff
diff <(echo "$likec4_libs") <(echo "$actual_libs")
```
**Gate**: Fails if any library exists on disk but not in the model (or vice versa).
**Effort**: Small (one script + CI step)
**Impact**: Would have caught H-02 the moment R6 was merged.

### Priority 3: Convention Compliance Scanner (blocks H-01 class)

**What**: CI script that checks every `.sh` file in `hooks/` for required patterns.
**Checks**:
- `set -euo pipefail` present (not `set -uo pipefail`, not `set -eu`)
- ERR trap present if file contains `exit 0` at end
- No `local` keyword outside function bodies (regex: `local ` not preceded by a function definition)
**Effort**: Medium (regex-based scanner, some false-positive tuning)
**Impact**: Would have caught H-01 if run retroactively; prevents future convention drift.

### Priority 4: Function Coverage Gate (blocks H-03 class)

**What**: CI script that extracts public function names from `hooks/lib/*.sh` and verifies each has a test.
**Implementation**:
- Extract function names: `grep -oP '^\w+\(\)' hooks/lib/*.sh`
- Filter out internal functions (prefixed with `_`)
- For each function, check that `tests/` contains at least one `@test` referencing it
**Effort**: Medium (name-matching heuristic, not line-level coverage)
**Impact**: Would have flagged `pdlc_count_tasks` and `pdlc_get_mtime` the moment they were added.

### Priority 5: Integration Contract Test Generator (blocks F-02, F-03 class)

**What**: A test template that, for every `declare -f` guard in the codebase, generates a test verifying the guard evaluates to true under the production source chain.
**Implementation**:
- `grep -rn 'declare -f' hooks/lib/*.sh` to find all guards
- For each guard, generate a BATS test that sources the production entry point's source chain and asserts the function is declared
**Effort**: Medium-Large (requires understanding source chains)
**Impact**: Would have caught F-02's dead code path. Combined with state-contract tests (batch increment), would have caught F-03.

### Priority 6: Spec Linter (blocks F-03 class)

**What**: A linter for spec acceptance scenarios that flags abstract state-mutation language.
**Implementation**: Regex scan of `spec.md` acceptance scenarios for verbs like "advances", "progresses", "continues", "updates" without a corresponding field name (e.g., `batch`, `phase`, `retry_count`).
**Effort**: Medium (heuristic, will need tuning)
**Impact**: Would have flagged F-03's "the lifecycle advances" acceptance criterion as underspecified.

---

## Implementation Roadmap

| Priority | Deliverable | Effort | Findings Prevented |
|----------|------------|--------|-------------------|
| P1 | `.github/workflows/ci.yml` (test + shellcheck) | Small | F-01, H-01 |
| P2 | `scripts/check-architecture-sync.sh` | Small | H-02 |
| P3 | `scripts/check-convention-compliance.sh` | Medium | H-01 |
| P4 | `scripts/check-test-coverage.sh` | Medium | H-03 |
| P5 | `tests/integration/source-chain.bats` | Medium | F-02 |
| P5 | `tests/integration/state-contracts.bats` | Medium | F-03 |
| P6 | Spec Kit governance rule: concrete state mutations | Small | F-03 |
| P6 | CLAUDE.md: `local` scope convention | Small | F-01 |
| P7 | CLAUDE.md: retroactive audit requirement | Small | H-01, H-02, H-03 |

**Total coverage**: All 6 findings would be prevented by implementing P1-P6. P7 provides defense-in-depth against the "grandfather clause" anti-pattern.
