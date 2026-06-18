---
name: pdlc-autopilot
description: |
  THE primary entry point for all SDLC and PDLC work. Use when user mentions: "SDLC", "PDLC",
  "build this feature", "implement the spec", "run the SDLC loop", "go back to SDLC",
  "continue implementation", "product context", "document this feature", "launch prep",
  or any spec-related work (requirements, design, tasks, implementation).

  This skill ORCHESTRATES Kiro skills (kiro:spec-*) as sub-operations, wrapped with product
  phases (P0 product context, P1 product skeptic, P2 docs, P3 demo & packaging).

  ⚠️ DO NOT invoke kiro:spec-* skills directly when user wants SDLC/PDLC workflow!
  Always use this skill as the entry point. It will call Kiro skills internally.

  Triggers:
  - "SDLC" or "PDLC" (any mention)
  - "build this feature end-to-end"
  - "implement the spec"
  - "run the SDLC loop"
  - "product context" or "product skeptic review"
  - "document this feature" or "write docs"
  - "launch prep" or "demo script"
  - "continue where we left off"
  - "go back to the spec"
  - "PDLC bug fix" or "fix this bug using the SDLC process"
  - "iterate on this feature using PDLC"
  - "product retrospective" or "context freshness"
  - When spec.json has "active_workflow": "pdlc-autopilot"

  DO NOT USE FOR day planning (use daily-copilot), practice tracking (use practice-tracker),
  skill evaluation (use eval-runner), skill creation/editing (use writing-skills),
  writing a PRD from scratch (this is SDLC/PDLC, not generic product strategy),
  general product management advice, plain "fix this bug" without PDLC mention,
  or "just refactor this function" (generic dev work without SDLC/PDLC context).
---

# PDLC Autopilot v3.6 (Director/Actor/Critic)

**THE ORCHESTRATOR** - This skill is the single entry point for all SDLC and PDLC work. It wraps the SDLC loop with product phases — product context before specs, docs/demos after implementation.

Efficient autonomous PDLC execution using batched implementation with the Director/Actor/Critic pattern.

**Core principle:** Batch tasks by file → one Actor per batch → one Critic per batch = minimal agent overhead.

## Workflow Router (CLASSIFY FIRST)

**Before any work starts, classify the request into one of three paths:**

| Signal | Path | Details |
|--------|------|---------|
| Bug report + PDLC context ("PDLC bug fix") | **Bug Fix** | @ref/lightweight-paths.md |
| "Iterate", "tweak", "add flag" + PDLC context | **Iteration** | @ref/lightweight-paths.md |
| "Build feature", "implement spec", full SDLC | **Full PDLC** | This file (below) |

```text
Classification rules:
  "bug", "fix", "broken", "regression" + PDLC → Bug Fix Path
  "add", "tweak", "iterate", "enhance"  + PDLC → Iteration Path
  "build", "feature", "implement", "spec"       → Full PDLC Path
  Ambiguous                                      → Ask user
```

**ALL paths share:** Context health check → visualization → retrospective + decision log.

## Context Health Check — RUNS ON EVERY INVOCATION

Before ANY path executes, check product context freshness. See @ref/context-health.md for full protocol.

```text
1. Read product-context.md
2. Extract <!-- last_reviewed: YYYY-MM-DD -->
3. Compare against tier threshold (T0=90d, T1=30d, T2=14d)
4. IF stale → WARN (non-blocking), flag for retro
5. IF missing comment → treat as stale, suggest adding it
6. Proceed with selected path
```

## Product Context (Phase P0) — MANDATORY

**Every SDLC run goes through the full PDLC flow.** Product context is not optional.

```text
IF {project}/.claude/product-context.md DOES NOT EXIST:
  → Phase P0 runs FIRST (asks user tier + targeted questions, generates file)
  → See @ref/product-context-template.md for generation protocol

IF {project}/.claude/product-context.md EXISTS:
  → Load it. Extract tier. Proceed to Phase 0a.
```

**No SDLC work starts without product context.** This prevents building the wrong thing efficiently.

The Product Skeptic (Phase P1) ALWAYS runs during Phase 0b validation. See @ref/product-skeptic.md.

## Workflow Stickiness (CRITICAL)

**Problem solved:** When user says "SDLC" or "go back to the spec", context was lost.

**Solution:** This skill is the ORCHESTRATOR. Kiro skills are building blocks it calls internally.

```text
User says "SDLC" → ALWAYS use this skill
User says "go back to spec" → ALWAYS use this skill
User says "implement the feature" → ALWAYS use this skill
```

### Workflow State Protocol

**On skill invocation:**
1. Read spec.json
2. If `active_workflow == "pdlc-autopilot"`: Resume from last known phase (check progress.md)
3. If `active_workflow` missing/different: Set it, start fresh

**State tracking in spec.json:**

```json
{
  "active_workflow": "pdlc-autopilot",
  "pdlc_state": {
    "started_at": "2026-02-04T22:30:00.000Z",
    "current_phase": "execution",
    "last_batch_completed": 2,
    "validation_results": { "requirements": "pass", "design": "pass", "tasks": "pass" },
    "product_skeptic_verdict": "approve",
    "p2_docs": "skipped",
    "p3_launch": "skipped",
    "t_mode": false,              // optional T-Mode fields
    "t_strategy": null,           // selected strategy (S1-S6)
    "worktree_safety": false      // opt-in worktree isolation
  }
}
```

## Quick Start: What To Do When Invoked

**FIRST ACTION (ALWAYS):**

```text
1. Check for product-context.md:
   - Read {project}/.claude/product-context.md
   - IF MISSING → Run Phase P0 (see @ref/product-context-template.md)
   - IF EXISTS → Extract tier, load product context. Continue.

2. Locate spec.json:
   - ⚠️ VAULT GUARD: If cwd is the Obsidian vault (obsibrain-vault/):
     → Specs MUST NOT be created here. Ask: "Which ~/workplace/ repo does this spec belong to?"
     → Use the repo path as {project}, NOT the vault path.
     → Example: user says "life-metrics" → {project} = ~/workplace/life-metrics/
   - Check if user provided feature name → use {project}/.claude/specs/{feature}/spec.json
   - Check if in working directory → use .claude/specs/*/spec.json
   - If multiple specs, ask user which one

3. Read spec.json and check active_workflow field:

   IF active_workflow == "pdlc-autopilot":
     → Read {spec_dir}/progress.md (if exists) for EXACT execution state
     → Read {spec_dir}/validation-criteria.md (if exists) for rules
     → RESUME from where progress.md says (NOT from vague memory)

   IF active_workflow MISSING or DIFFERENT:
     → SET active_workflow = "pdlc-autopilot" in spec.json
     → START fresh from Phase 0a (artifact generation)

4. Run context health check (see above)
5. Classify request → select path (Bug Fix / Iteration / Full PDLC)
6. Render phase visualization for selected path (see @ref/phase-viz.md)
7. Announce: "PDLC Autopilot v3.6 active for {feature_name}. Tier: {tier}. Path: {path}. Phase: {current_phase}"
```

## CRITICAL: Autonomous Execution (NO STOPPING)

**⚠️ DO NOT ask "Would you like me to proceed?" between phases!**

This is an AUTONOMOUS loop. The ONLY valid stopping points are:
1. **Validation BOTH FAIL** - Cannot proceed until fixed
2. **Max 2 fix cycles exceeded** - Report to user, stop
3. **All batches complete** - Final report, done

If you find yourself about to ask "Should I proceed?" — STOP. That's the stickiness problem. Just proceed.

**Plan-before-code:** For Full PDLC tasks, the Director MUST complete Phase 0a/0b (artifact generation + validation) before any code is written. Front-load planning — don't rush to implementation.

## Architecture

**Standard Mode (single Actor per batch):**

```text
┌─────────────────────────────────────────────────────────────┐
│                    DIRECTOR (Main Claude)                    │
│  - Reads spec ONCE, extracts all context                    │
│  - Groups tasks by file/domain                              │
│  - Dispatches Actors with BATCHED tasks                     │
│  - Dispatches Critics to review batch output                │
└─────────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
┌─────────────────┐           ┌─────────────────┐
│     ACTOR       │           │     CRITIC      │
│  (Implementer)  │           │   (Reviewer)    │
│  - ALL tasks    │           │  - ALL criteria │
│  - Self-review  │           │  - Pass/fail    │
└─────────────────┘           └─────────────────┘
```

**T-Mode (parallel Actor teammates per batch):** See @ref/t-mode-strategies.md

## The Loop

### Full PDLC Path (default for new features)

Generic orchestration (Director decide loop, full batch exec pseudocode, generic resume mechanics) is delegated to host `/goal` for entry + host `/loop` (or `pdlc-outer-loop.sh` reference driver) for execution. See `templates/ref/pdlc-goal.md` (host-aligned entry adapter) for classification, P0/P1, SpecGate, delegation notes + PDLC success criteria.

**PDLC special preserved** (all rules, matrices, gates, skeptic, batching, persistence, constraints below apply unchanged regardless of host driver; 100% coverage retained):

- P0 product-context mandatory (Phase P0) + P1 Product Skeptic (adversarial 5-lens vs product-context.md)
- Phase 0a/0b SpecGate: Kiro Skill tool ONLY for artifact gen (requirements/design/tasks) + kiro:validate-*
- Phase 0b: parallel ADVOCATE + SKEPTIC + Product Skeptic for reqs; ADVOCATE + SKEPTIC for tasks; Kiro validate-design GO required; consensus matrix
- Phase 0.5/0.75: validation-criteria load + ARCH-* extraction + test strategy (holdouts sealed)
- Phase 1+: file-group batching (see Batching Strategy); per-batch Actor + dual Critics (CriticGate); max 2 fix cycles
- Final Validator (dual + SpecGate/CriticGate compliance + drift vs product-context) + retrospective (all paths)
- Lightweight paths (bug-fix/iteration) for non-full work (see @ref/lightweight-paths.md)
- PR/P2/P3 opt-in phases as documented in ref/

pdlc-goal.md + retained PDLC sections below supply the special behaviors. Use host /goal + pdlc-goal for PDLC rules. Host supplies generic loop.

### Bug Fix Path (lightweight — ~2 agent calls)

```text
B1: Diagnose → B2: Fix → B3: Validate (SKEPTIC only) → B4: Retrospective
See @ref/lightweight-paths.md for full protocol.
```

### Iteration Path (medium — ~4-6 agent calls)

```text
I1: Mini-Spec → I2: Execute → I3: Validate (adaptive) → I4: Retrospective
See @ref/lightweight-paths.md for full protocol.
```

**ALL paths end with retrospective + decision log.** See @ref/context-health.md.

### Validation Subagent Matrix

| Step | Validator | Invocation Mechanism | Blocks Execution? |
|------|-----------|---------------------|-------------------|
| Requirements | ADVOCATE + SKEPTIC + Product Skeptic | Task tool (3 parallel subagents) | Yes if BOTH FAIL or Product Skeptic KILL |
| Gap Analysis | kiro:validate-gap | **Skill tool** (SpecGate) | Warnings only |
| Design | kiro:validate-design | **Skill tool** (SpecGate) | Yes if NO-GO |
| Tasks | Tasks Validator | Task tool (2 parallel subagents) | Yes if BOTH FAIL |
| Test Strategy | Test Strategy Designer | Task tool (1 subagent) | Produces holdout scenarios |
| Per-Batch | Critic ADVOCATE + SKEPTIC | Task tool (2 parallel subagents) — **CriticGate** | Yes if BOTH FAIL |
| Final | Final Validator | Task tool (2 parallel + SpecGate check) | Reports gaps |

**#53 Resource Rule (applies to all Critics + Final + Actor test steps):** Critics MUST NOT run test execution commands. Review the Actor's reported test output, artifacts, and logs from the batch. Under resource pressure (signaled by Director pre-guards in autonomous outer-loop or explicit note), output "SKIPPED due to resource pressure — reviewed artifacts only". This is non-negotiable to prevent machine crash from test process multiplication.
| PR Review | Review Comment Actors | Task tool (batched by file) — **CriticGate** | Max 2 cycles |
| P2 Docs | Docs Critic | Task tool (1 subagent) | Opt-in only |

**IMPORTANT:** Rows marked **Skill tool (SpecGate)** MUST be invoked using the Skill tool, NOT the Task tool. See SpecGate constraint above.

## Director Protocol

Generic Director loop mechanics (Step 0-4 orchestration, batch dispatch pseudocode, resume from progress.md) delegated to host `/goal` (entry via pdlc-goal.md) + `/loop` execution (pdlc-outer-loop.sh reference). 

See `templates/ref/pdlc-goal.md` for PDLC payload (success criteria, P0/P1/SpecGate/delegation). 

**PDLC special preserved** (enforced in all hosts/drivers; detailed in retained sections below + ref/):
- SpecGate + CriticGate process constraints (verbatim)
- Validation Subagent Matrix (verbatim)
- Product Skeptic (P1 + 5 lenses)
- Per-batch dual-critic (ADVOCATE+SKEPTIC) + consensus + #53 resource
- ARCH-* extraction, test strategy holdouts, batching by file, session resume protocol
- Red flags, all constraints, lightweight paths, task integration, examples

pdlc-goal.md + this SKILL (slim) + validator-templates supply the PDLC rules; host provides generic decide/loop/resume. No duplication of host orchestration here.

## Prompt Templates

All PDLC validator/actor/critic templates live in @ref/validator-templates.md (and @ref/product-skeptic.md for full 5-lens). 

For host-aligned entry (Grok/Cursor/Ralph /goal): see `templates/ref/pdlc-goal.md` — it references these templates + success criteria + delegation to /loop. Use pdlc-goal.md + validator-templates as the PDLC payload; host loop invokes them as sub-protocols.

- **Actor template:** See @ref/validator-templates.md (Actor section)
- **Critic ADVOCATE/SKEPTIC:** See @ref/validator-templates.md (Critic section)
- **Requirements ADVOCATE/SKEPTIC:** See @ref/validator-templates.md (Requirements section)
- **Product Skeptic:** See @ref/validator-templates.md (Product Skeptic section) + @ref/product-skeptic.md
- **Tasks ADVOCATE/SKEPTIC:** See @ref/validator-templates.md (Tasks section)
- **Final ADVOCATE/SKEPTIC:** See @ref/validator-templates.md (Final section)
- **DevRel Actor / Docs Critic:** See @ref/docs-phases.md (P2 section)
- **Demo Actor:** See @ref/docs-phases.md (P3 section)
- **Test Strategy Designer:** See @ref/test-strategy.md (Phase 0.75)
- **PR Review Cycle:** See @ref/pr-review-cycle.md (Phase 5)

## Task Primitive Integration (Cross-Session)

**Prerequisite:** `CLAUDE_CODE_TASK_LIST_ID=pdlc-autopilot` in shell env (persists tasks across sessions in `~/.claude/tasks/`).

### Implementation Tasks

```text
Director Setup: Parse tasks.md → TaskCreate for each task
Per Batch: TaskUpdate(in_progress) → Actor → Critic → TaskUpdate(completed)
Final: TaskList() to verify all tasks completed
```

### Bug Tracking via Tasks API

```text
Bug discovered (by Critic, test, or user):
  → TaskCreate with metadata: { "type": "bug", "project": "{project}", "severity": "high|medium|low", "found_by": "SKEPTIC|ADVOCATE|test|user", "batch": "N" }
  → Subject: "[BUG] {concise description}"
  → Description: root cause (if known), reproduction, affected files

Bug Fix path (B1 Diagnose):
  → TaskList() → filter for metadata.type == "bug" and status != "completed"
  → TaskGet(bugId) → read full context
  → TaskUpdate(bugId, status: "in_progress")

Bug fixed (B3 Validate passes):
  → TaskUpdate(bugId, status: "completed", metadata: { "fix": "description", "regression_test": "file:line" })

Retrospective:
  → TaskList() → count open bugs, report in retro summary
```

## Batching Strategy

**Group tasks that touch the same files:**

```text
Tasks 1.1-1.4 all modify transform_snapshot.py → BATCH A (1 Actor, not 4)
Tasks 2.3 modifies app.js → BATCH B
→ Run A and B in PARALLEL if no file overlap
```

## Session Persistence

See @ref/session-persistence.md for compaction survival, progress.md template, context budget management, and validation-criteria.md template.

**Key files that survive compaction:**
- `{project}/.claude/product-context.md` — product strategy
- `{project}/.claude/decision-log.md` — decisions (append-only)
- `{spec_dir}/validation-criteria.md` — rules
- `{spec_dir}/progress.md` — execution state

### Resume Protocol

```text
1. Read spec.json → get spec_dir, current_phase
2. Read {spec_dir}/progress.md → EXACT execution state
3. Read {spec_dir}/validation-criteria.md → rules
4. Do NOT re-read completed batch files
5. Resume from EXACTLY where progress.md says
```

## Examples

See @ref/examples.md for full standard mode and T-Mode execution walkthroughs.

## Process Constraints (Named — reference in validators)

### SpecGate: Kiro Skill Invocation Is MANDATORY (BLOCKING)

**What:** All spec artifact generation (Phase 0a) and design/gap validation (Phase 0b) MUST use the Skill tool to invoke Kiro skills. General-purpose subagents MUST NOT write spec artifacts directly.

**Why this exists:** During the Formation Fellowship build (Mar 2, 2026), Kiro skills were prescribed but not invoked — general-purpose subagents wrote artifacts directly, bypassing Kiro's structured generation and validation. This produced artifacts that lacked Kiro's format discipline and missed Kiro's built-in validation checks.

**Phase 0a — Artifact Generation:**

```text
BLOCKING REQUIREMENT: When requirements.md, design.md, or tasks.md is MISSING,
the Director MUST invoke the Kiro skill via the Skill tool:

  Skill tool: skill="kiro:spec-requirements"    → generates requirements.md
  Skill tool: skill="kiro:spec-design", args="-y" → generates design.md
  Skill tool: skill="kiro:spec-tasks", args="-y"  → generates tasks.md

VIOLATION: Using a Task tool (general-purpose subagent) to WRITE these artifacts
is a SpecGate violation. Subagents may READ and VALIDATE artifacts, but Kiro skills
MUST generate them.
```

**Phase 0b — Validation:**

```text
BLOCKING REQUIREMENT: Before proceeding to Phase 1+ execution, the Director MUST invoke:

  Skill tool: skill="kiro:validate-gap"     → gap analysis (informational, non-blocking)
  Skill tool: skill="kiro:validate-design"  → design review (GO/NO-GO, BLOCKING)

VIOLATION: Using custom subagent prompts for gap analysis or design validation
instead of Kiro validation skills is a SpecGate violation.

NOTE: ADVOCATE/SKEPTIC/Product Skeptic subagents run IN ADDITION to Kiro validation
skills, not as replacements.
```

**Provenance Gate (Phase 0a → 0b transition):**

```text
BEFORE entering Phase 0b, the Director MUST verify:
  1. Each artifact (requirements.md, design.md, tasks.md) exists
  2. Each artifact was generated by a Kiro skill invocation (not manually written)
  3. Record provenance in progress.md:
     ## Artifact Provenance
     | Artifact | Generated By | Timestamp |
     |----------|-------------|-----------|
     | requirements.md | kiro:spec-requirements | [ISO] |
     | design.md | kiro:spec-design | [ISO] |
     | tasks.md | kiro:spec-tasks | [ISO] |

IF any artifact was written by a subagent instead of Kiro:
  → STOP. Re-generate it using the correct Kiro skill.
  → Do NOT proceed to Phase 0b with manually-written artifacts.
```

**Verification in Final Validator:**

```text
Final ADVOCATE/SKEPTIC prompts MUST include this check:
  "SpecGate COMPLIANCE: Verify that spec artifacts in {spec_dir}/ were generated
   by Kiro skills (check progress.md Artifact Provenance table). Flag if provenance
   is missing or shows manual generation."
```

### CriticGate: Per-Batch Critic Review Is MANDATORY (BLOCKING)

**What:** After every Actor batch completes, the Director MUST dispatch BOTH Critic ADVOCATE and Critic SKEPTIC subagents. This applies to ALL artifact types — code, skill ref files, config files, documentation, any Actor output.

**Why this exists:** During the Formation Fellowship build (Mar 2, 2026), the Director dispatched Actor subagents for all 5 batches but never dispatched Critic ADVOCATE/SKEPTIC for any batch. The "Never skip Critic review" red flag existed but had no enforcement mechanism. Bugs that Critics would have caught (schema path inconsistencies, field name errors) were only found by the Final Validator, requiring post-completion rework.

**Per-Batch Enforcement:**

```text
BLOCKING REQUIREMENT: After EACH Actor batch returns, the Director MUST:
1. Dispatch Critic ADVOCATE subagent (parallel)
2. Dispatch Critic SKEPTIC subagent (parallel)
3. Apply consensus rules (both pass / both fail / disagree)
4. Record results in progress.md Batch Status table
5. ONLY THEN mark batch as complete

VIOLATION: Marking a batch as complete without dispatching BOTH Critics.
VIOLATION: Skipping Critics for "simple" or "config-only" batches.
VIOLATION: Substituting Actor self-review for Critic dispatch.
```

**Artifact-Agnostic Scope:**

```text
SCOPE: Critics review ALL artifact types produced by Actors:
- Source code (functions, modules, tests)
- Skill files (SKILL.md, ref/ protocols, config/ JSON)
- Documentation (docs, README, guides)
- Configuration (JSON, YAML, selectors)

There is no "too simple for Critic review" exception. Every batch gets Critics.
```

**Provenance in progress.md:**

```text
Batch Status table MUST have ADVOCATE and SKEPTIC columns with PASS/FAIL/PASS_WARN values.
A batch with status "DONE" but blank ADVOCATE/SKEPTIC columns is a CriticGate violation.
Valid status progression: PENDING → ACTOR_DONE → DONE+CRITICS
```

**Verification in Final Validator:**

```text
Final ADVOCATE/SKEPTIC prompts MUST include this check:
  "CriticGate COMPLIANCE: Check progress.md Batch Status table. Every batch MUST have
   ADVOCATE and SKEPTIC results filled in. Flag any batch with blank critic columns
   or status showing 'DONE' without 'DONE+CRITICS'."
```

---

## Red Flags

**Never:**
- Dispatch per-task agents (use batches)
- Have Actor dispatch sub-agents (defeats purpose)
- Skip Critic review
- Mark a batch "DONE" without both ADVOCATE and SKEPTIC critic results (CriticGate violation)
- Skip critics for "simple" batches — all batches get critics regardless of artifact type (CriticGate violation)
- Run parallel batches that touch same file
- Let two teammates modify the same file (T-Mode)
- Use general-purpose subagents to WRITE spec artifacts (SpecGate violation)
- Skip Kiro validation skills and substitute custom subagent prompts (SpecGate violation)
- **Resource violation (#53):** Have Critics re-execute tests (`go test`, pytest, etc) or Actors spawn without pre-check. Critics review OUTPUT/ARTIFACTS only. Report "SKIPPED due to resource pressure — reviewed artifacts only" on guard signal. Unbounded test fan-out = kernel panic.

**Fix cycles:** Max 2 Critic cycles per batch. If still failing, report to user.

## Integration

**Required:** Kiro spec with requirements.md, design.md, tasks.md
**Required (PDLC):** `{project}/.claude/product-context.md` — auto-generated by Phase P0 if missing
**Optional but RECOMMENDED:** validation-criteria.md for session persistence

**Kiro Skills (SpecGate — MUST invoke via Skill tool, NOT Task tool):**
- `kiro:spec-requirements` — Generate requirements.md (Phase 0a)
- `kiro:spec-design` — Generate design.md (Phase 0a)
- `kiro:spec-tasks` — Generate tasks.md (Phase 0a)
- `kiro:validate-gap` — Analyze implementation gaps (Phase 0b, informational)
- `kiro:validate-design` — GO/NO-GO design decision (Phase 0b, BLOCKING)

**Uses:** Task tool with general-purpose subagent type

**Complements:**
- `superpowers:test-driven-development` (Actors should follow TDD)
- `superpowers:verification-before-completion` (Critic verifies)

**PDLC Phases (ref/ files):**
- `templates/ref/pdlc-goal.md` — Host /goal entry adapter (portable; thin PDLC payload + success criteria + DONE token + delegation to host /loop or pdlc-outer-loop reference). Use for Grok/Cursor/Ralph hosts + all new PDLC work. Classification + P0/P1/SpecGate here; generic loop delegated. See pdlc-goal.md for host-aligned entry.
- @ref/product-context-template.md — Phase P0: product-context.md generation
- @ref/product-skeptic.md — Phase P1: adversarial product alignment review
- @ref/docs-phases.md — Phase P2 (Document) + P3 (Demo & Package)
- @ref/lightweight-paths.md — Bug Fix + Iteration paths (lightweight alternatives to full PDLC)
- @ref/context-health.md — Freshness validation, decision log, retrospective, drift detection
- @ref/test-strategy.md — Phase 0.75: Test Strategy Designer, holdout scenarios, anti-gaming
- @ref/pr-review-cycle.md — Phase 5: PR review ingestion, gap classification, false positive detection
- @ref/phase-viz.md — Phase visualization templates (pipelines, progress bars, summary boxes)

## When NOT to Use Kiro Skills Directly

| If user says... | DON'T use... | DO use... |
|-----------------|--------------|-----------|
| "SDLC", "go back to spec" | kiro:spec-* directly | pdlc-autopilot (or host /goal + pdlc-goal.md for PDLC rules: classif/P0/P1/SpecGate/success) |
| "implement the feature" | kiro:spec-tasks | pdlc-autopilot (or /goal + pdlc-goal.md for PDLC rules) |
| "continue where we left off" | kiro:spec-* | pdlc-autopilot (or /goal + pdlc-goal.md for PDLC rules) |

**Host /goal preference (per loop-simplification-v4 Phase 3/4/5):** For new PDLC work, prefer host /goal with pdlc-goal.md template (provides classification, P0/P1, SpecGate, delegation to /loop or PDLC outer reference; injects PDLC special: skeptic, dual-critic, batching, lifecycle, gates, persistence). SKILL.md slimmed; generic orchestration removed (see pdlc-goal.md + delegation notes). Use pdlc-autopilot skill for Claude hosts or equivalent adapters.

**When IS it OK to use Kiro skills directly?**
- User explicitly says "just generate requirements" (no full SDLC)
- User wants to re-generate a specific artifact without running the loop
- Debugging/inspecting a single phase
