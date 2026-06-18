# Lightweight Paths: Bug Fix & Iteration

**See `templates/ref/pdlc-goal.md` for host-aligned entry.** Bug Fix / Iteration paths (classification + lightweight protocols) are PDLC special and retained in slim SKILL + pdlc-goal.md payload. Host /goal classifies and delegates execution loop; these rules (B1-B4, I1-I4, state via tasks) apply for PDLC context regardless of host (pdlc-outer-loop ref or Ralph). 

**Why:** Full PDLC ceremony (P0 → specs → build → validate) is overkill for fixing a bug or adding a config flag. These paths preserve rigor with less overhead.

**Stickiness gate:** Lightweight paths ONLY activate when user explicitly invokes PDLC context. "PDLC bug fix", "fix this using the PDLC process", "iterate on this feature using PDLC". Plain "fix this bug" is a NON-trigger — it stays in normal Claude Code mode.

---

## Path Selection (Decision Table)

| Signal | Path | Agent Calls | Spec Artifacts |
|--------|------|-------------|----------------|
| Bug report, error trace, regression | **Bug Fix** | ~2 (Actor + SKEPTIC) | None (progress.md only) |
| "Add config flag", "tweak behavior", "small feature" | **Iteration** | ~4-6 (Actor + dual Critics) | Mini-spec in progress.md |
| "Build this feature", "implement the spec", new capability | **Full PDLC** | ~10-30 | requirements.md, design.md, tasks.md |

### Classification Rules

```
IF user mentions "bug", "fix", "broken", "regression", "error" + PDLC context:
  → Bug Fix Path

IF user mentions "add", "tweak", "iterate", "enhance", "config" + PDLC context:
  → Iteration Path

IF user mentions "build", "feature", "implement", "spec", "end-to-end":
  → Full PDLC Path

IF ambiguous:
  → Ask: "Is this a bug fix, a small iteration, or a new feature?"
```

---

## Bug Fix Path (4 Phases)

Lightweight. ~2 agent calls. No spec artifacts. Progress tracked in progress.md.

### B1: Diagnose

**Who:** Director (main Claude) — no subagent needed.

```
1. Context health check (see @ref/context-health.md)
2. Render bug fix pipeline viz (see @ref/phase-viz.md)
3. Read the relevant code — understand the bug
4. Identify root cause
5. State: "Root cause: [1-line description]"
6. Update progress.md with diagnosis
```

### B2: Fix

**Who:** Single Actor subagent (or Director for trivial fixes).

```
Actor prompt includes:
- Root cause from B1
- Product context (loaded, not re-asked)
- Instruction: "Fix the bug AND add a regression test"
- Validation criteria from validation-criteria.md (if exists)

Actor deliverables:
- Code fix
- Regression test (MANDATORY — no fix ships without a test)
- Self-review: "Fix addresses root cause because..."
- If fix changes output format: verify new format matches consumer expectations
- If spec was wrong (not code): flag the spec issue as a follow-up task
```

**Trivial fix shortcut:** If the fix is < 5 lines and obvious, Director can apply it directly without spawning an Actor. Still requires regression test.

### B3: Validate

**Who:** SKEPTIC only. No ADVOCATE, no Product Skeptic — overkill for bugs.

```
SKEPTIC reviews:
- Does the fix address the stated root cause?
- Is the regression test meaningful (not just "it doesn't crash")?
- Are there side effects?
- Does the fix introduce new issues?
- Architecture compliance: If ARCH-* constraints exist in validation-criteria.md,
  does the fix violate any? (State ownership, layer boundaries, pattern consistency)

PASS → proceed to B4
FAIL → one fix cycle, then report to user if still failing
```

**Max fix cycles:** 1 (bugs should be quick — if SKEPTIC fails twice, escalate).

### B4: Retrospective

**Who:** Director. ~30 seconds.

```
Four questions (see @ref/context-health.md retrospective protocol):
1. What changed vs. expected?
2. What did we learn? (Pattern? Recurring bug category?)
3. Should context update? (New principle? Kill criteria?)
4. Did the bug stem from a spec/AC issue? If yes, create follow-up to fix the spec.

Output:
- Retrospective summary in progress.md
- Decision log entry IF learning is reusable
- Auto-memory entry IF lesson is reusable across projects (write to MEMORY.md)
- Context freshness update IF reviewed
- Render final summary box (see @ref/phase-viz.md)
```

---

## Iteration Path (4 Phases)

Medium weight. ~4-6 agent calls. Mini-spec in progress.md (not separate files).

### I1: Mini-Spec

**Who:** Director — no subagent needed.

```
1. Context health check (see @ref/context-health.md)
2. Render iteration pipeline viz (see @ref/phase-viz.md)
3. Write mini-spec in progress.md:

## Iteration Mini-Spec: [description]
- **What's changing:** [1-3 bullet points]
- **Acceptance criteria:** [numbered list]
- **Files affected:** [list]
- **Alignment check:** [V1 Core | Layer 2 | New — not in roadmap]

4. IF alignment is "Layer 2" or "New":
   → Warn: "This is outside V1 Core scope. Proceed intentionally?"
   → Log to decision-log.md if user confirms
```

### I2: Execute

**Who:** Actor subagent. Standard Actor execution, smaller batches (typically 1-2).

```
Actor prompt includes:
- Mini-spec from I1
- Product context
- Validation criteria (if exists)
- Instruction: follow TDD, write tests for all acceptance criteria
- Output format rule: Never describe output as "return a [action] decision" — specify exact structure

Batch size: 1-2 batches max. If iteration needs 3+ batches, it's probably Full PDLC.
```

### I3: Validate

**Adaptive critic selection:**

```
IF acceptance criteria count >= 3:
  → Dual Critics: ADVOCATE + SKEPTIC (parallel)
  → Standard consensus rules

IF acceptance criteria count < 3:
  → SKEPTIC only (single critic, lightweight)
  → PASS/FAIL, no consensus needed
```

**Drift check:** Both critics check alignment with mini-spec alignment field. If V1 Core was stated but implementation touches Layer 2, flag it.

### I4: Retrospective

Same as Bug Fix B4. Four questions (including spec/AC root cause check), decision log if applicable, context freshness update, auto-memory if lesson is reusable across projects.

---

## State Tracking via Tasks API (Cross-Session)

Lightweight paths use Claude Code's Tasks API for all tracking. Tasks persist across sessions via `CLAUDE_CODE_TASK_LIST_ID=pdlc-autopilot` (stored at `~/.claude/tasks/`).

### Bug Tracking

Bugs are Tasks with `metadata.type: "bug"`:

```
Creating a bug:
  TaskCreate({
    subject: "[BUG] Cache race condition in invalidation",
    description: "Root cause: TTL not checked before merge. Found during Batch 3 SKEPTIC review. Affected files: lib/cache.py:42",
    activeForm: "Fixing cache race condition",
    metadata: { type: "bug", project: "{project}", severity: "high", found_by: "SKEPTIC", batch: "3" }
  })

Finding open bugs:
  TaskList() → filter status != "completed" where subject starts with "[BUG]"

Fixing a bug:
  TaskUpdate(bugId, { status: "in_progress" })   → B1 Diagnose
  TaskUpdate(bugId, { status: "completed", metadata: { fix: "Added TTL check", regression_test: "tests/test_cache.py:87" } })  → B3 passes

Bug dependencies:
  TaskUpdate(bugId, { addBlocks: [featureTaskId] })  → feature blocked until bug fixed
```

### Iteration Tracking

Iterations are Tasks with `metadata.type: "iteration"`:

```
Creating an iteration:
  TaskCreate({
    subject: "[ITER] Add --dry-run flag to ingest command",
    description: "Mini-spec: ...\nCriteria: 3\nAlignment: V1 Core",
    activeForm: "Iterating on ingest command",
    metadata: { type: "iteration", project: "{project}", alignment: "V1 Core", criteria_count: 3 }
  })
```

### Querying Across Sessions

On any PDLC invocation, the Director can:
```
TaskList() → see ALL open bugs, iterations, and implementation tasks
  - [BUG] items → candidates for Bug Fix path
  - [ITER] items → candidates for Iteration path
  - Regular items → implementation tasks from full PDLC
```

This replaces file-based tracking for lightweight cycles. Progress.md is still used for full PDLC batch execution state.

---

## Comparison: Three Paths

| Dimension | Bug Fix | Iteration | Full PDLC |
|-----------|---------|-----------|-----------|
| **Phases** | 4 (B1-B4) | 4 (I1-I4) | 7+ (P0-P3) |
| **Agent calls** | ~2 | ~4-6 | ~10-30 |
| **Spec artifacts** | None | Mini-spec in progress.md | requirements.md, design.md, tasks.md |
| **Critics** | SKEPTIC only | Adaptive (1 or 2) | Dual + Product Skeptic |
| **Product Skeptic** | No | No (alignment check only) | Yes |
| **Context health** | Yes | Yes | Yes |
| **Decision log** | If learning found | If scope decision | Always on SCOPE/KILL |
| **Retrospective** | Yes (4 questions) | Yes (4 questions) | Yes (4 questions) |
| **Visualization** | Compact box | Medium box | Full pipeline |
| **Target duration** | Minutes | ~30 min | Hours to days |
| **Fix cycles** | Max 1 | Max 2 | Max 2 per batch |

**Host-aligned entry note (Phase 3):** Classification (Bug Fix / Iteration / Full) also lives in pdlc-goal.md. For new PDLC work prefer host /goal with pdlc-goal.md (provides router + P0/P1 + SpecGate + delegation to /loop or pdlc-outer-loop reference). see pdlc-goal.md for host-aligned entry. Lightweight paths preserved verbatim for PDLC special.
