# pdlc-goal.md — PDLC Entry for Host /goal + /loop

**Purpose (per loop-simplification-v4 + revival plan Phase 3/4)**: Thin PDLC-specific goal template. User invokes via host `/goal "build X with full PDLC"` (or equivalent in Grok/Cursor). This delegates generic goal decomposition, persistence, and long-running loop mechanics to the host (`/goal` + `/loop` or Ralph driver) while injecting only the PDLC-special behaviors that make the product right (P0 context + skeptic, SpecGate, dual-critic, batching, lifecycle, retros).

**Do not duplicate host loop orchestration here.** This file is the "PDLC payload" / success criteria + sub-protocol entry point.

## Quick Start (Host-Agnostic)

1. Host creates/persists the goal (e.g. `pdlc-goal.md` or in .claude/specs/.../pdlc-goal.md).
2. Activate pdlc-autopilot skill (or equivalent adapter) with this as context.
3. PDLC runs:
   - Context health + product-context (P0) if missing.
   - Product Skeptic (P1) + Kiro SpecGate for artifacts.
   - Then delegates execution loop to host /loop (using pdlc-outer-loop.sh or in-skill equivalent as reference Ralph-style driver).
   - Per-batch: Actor + dual Critics (ADVOCATE + SKEPTIC) with consensus.
   - Resource governance (#53) + circuit breakers.
   - Final validator + retrospective.
   - Only output host-compatible "DONE" (or escalation) when all criteria + independent verification pass.

**Only say DONE after validator + host loop confirms (no pending tasks, no drift, product skeptic lenses passed, tests/artifacts reviewed not just re-run).**

## Classification + Paths (lightweight, from SKILL.md)

Same 3 paths as full PDLC (bug-fix / iteration / full), but start from this goal file + product-context.

## Success Criteria / Oracle (PDLC Special — do not remove)

- Product context (P0) present + fresh.
- Product Skeptic (P1) APPROVE or SCOPE (no KILL).
- Spec artifacts generated via Kiro skills only (SpecGate).
- Dual-critic per batch + final (evidence-based, consensus rules).
- All tasks.md complete (or explicit archive/complete phase).
- No drift vs. product-context + design (context health + Final Validator).
- Resource governance respected (no unbounded fan-out; critics review output where possible).
- Retrospective + decision log captured.

**Linked to GitHub issues closed by this simplification**: #23 (process gaps via better composition + host loop consistency), #39 (SKEPTIC decomp path enabled), prompt-gap bundle (#28/#30/#32 etc. via slim + host verification layers).

## Host Delegation Notes

- Generic "keep working until DONE" + stop hook + fresh-context iteration: use host `/loop` or Ralph.
- State (goal persistence, progress): host /goal + this file + spec.json / progress.md / HANDOFF.
- PDLC adapters (skeptic, critics, batching, gates): invoked as sub-protocols/skills from the host loop.
- Outer-loop (pdlc-outer-loop.sh) serves as reference "PDLC-aware Ralph driver" implementation for hosts without native long-running.

## Example Invocation (Grok / Claude / Cursor)

" /goal build rate limiting with full PDLC (product context, dual-critic, batching, retros) using the pdlc-goal template. Delegate loop to host /loop. Use PDLC sub-protocols for skeptic + critics. Only DONE after validator + no pending tasks + no drift."

Then let the host loop + this payload run.

**Update this file + linked spec/ when new PDLC special behaviors are added (keep the special, slim the generic).**

See loop-simplification-v4 design.md for portable core contract and "keep PDLC special" box.

---

## Persistent pdlc-goal.md File Format (Simple Goal State for Hosts)

When host /goal (Grok/Cursor/Ralph/etc.) creates the goal artifact, use this structure (flat, survives compaction, checked by Final Validator for DONE token):

```markdown
# PDLC Goal: <short feature or task name>
**Product Context:** .claude/product-context.md (or link)
**Spec Dir:** .claude/specs/<name>/
**PDLC Sub-protocols:** Use pdlc-goal + ref/validator-templates.md + product-skeptic.md + critic consensus + SpecGate/CriticGate for all work. Delegate generic loop to host /loop or pdlc-outer-loop reference driver (reuses hooks/lib/pdlc-*.sh).

## Success Criteria (must all hold before completion)
- [ ] P0 product-context present + last_reviewed fresh per context-health.md
- [ ] P1 Product Skeptic: APPROVE or SCOPE (no KILL)
- [ ] Phase 0a: all spec artifacts (requirements/design/tasks) generated exclusively via Kiro Skill (SpecGate provenance recorded in progress.md)
- [ ] Phase 0b: Kiro validate-design GO + parallel ADVOCATE/SKEPTIC + Product Skeptic consensus (all PASS or approved SCOPE)
- [ ] Per-batch: CriticGate — both ADVOCATE + SKEPTIC results recorded; max 2 fix cycles
- [ ] All tasks.md items completed (or archived); progress.md shows no PENDING
- [ ] Final Validator (ADVOCATE + SKEPTIC + PDLC compliance + drift vs product-context) = PASS
- [ ] Resource governance followed (#53: critics review artifacts only)
- [ ] Retrospective + decision log captured
- [ ] No open red flags from pdlc-goal / SKILL

## Execution Log (append-only)
- [YYYY-MM-DD] Phase X / batch N: ...
- ...

## Completion Token
Only the Final Validator (or host validator after full criteria) may append:

**PDLC-DONE-VALIDATED**

(Host /loop must confirm no pending tasks in state + token present before final exit.)
```

**Validator contract:** The final step MUST reference this file's criteria list + echo the exact completion token on success. "Only say DONE after validator".

( Created as part of autopilot Phase 4 / OpenSpec task execution. Dogfooded via this change. )