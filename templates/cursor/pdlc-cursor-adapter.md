# PDLC Cursor Adapter — Prompt Pack + Terminal Agent Driver (Phase 4)

**Scope**: Basic Cursor (VS Code AI agent) portability sketch per loop-simplification-v4 host adapters + revival Phase 4 (Grok/Cursor + dogfood). Reuses exact same portable core (`hooks/lib/pdlc-*.sh`) and `pdlc-outer-loop.sh` reference driver. Uses `templates/ref/pdlc-goal.md` (and copied ref/ validator templates) as the PDLC specialization payload.

Cursor provides: .cursor/rules for persistent prompt injection, chat/agent composer for sub-dispatches, integrated terminal for running bash drivers + sub-processes.

## Basic .cursor/rules / Prompt Pack

Create `.cursor/rules/pdlc-autopilot.md` (or .cursorrules include) with:

```markdown
# PDLC Autopilot (Cursor port of pdlc-goal + core)

Follow templates/ref/pdlc-goal.md exactly for entry, success criteria, and DONE rule.

**Always**:
- Classify bug/iter/full using pdlc-goal router.
- Enforce P0: ensure product-context.md (use product-context-template).
- P1: ALWAYS dispatch Product Skeptic (parallel) using product-skeptic.md lenses against product-context + spec.
- Phase 0a: SpecGate — only generate requirements/design/tasks via Kiro/cc-sdd skills (or equivalent Cursor "spec gen" if mapped; never direct write without provenance).
- Phase 0b: Kiro validate (if avail) + ADVOCATE + SKEPTIC + Product Skeptic consensus before any impl. KILL/NO-GO blocks.
- Batching: file-grouped only. One Actor impl per batch.
- Per batch + final: dispatch BOTH ADVOCATE and SKEPTIC critics (CriticGate). Record in progress.md table (columns for both).
- Use validation-criteria.md for all validators (incl. holdouts from test-strategy).
- Lightweight paths per ref/lightweight-paths.md for bug/iter.
- Resource: before dispatches, run equivalent of pdlc_resource_check (or call the bash lib via terminal cmd). Critics review artifacts/outputs only.
- Lifecycle via pdlc-lifecycle inference on HANDOFF/progress.
- End every major phase with retrospective (context-health protocol).
- ONLY declare DONE / output completion token after Final Validator + explicit check of pdlc-goal.md success criteria + "no pending tasks" + no product drift. Use token like:
  ```
  PDLC-DONE-VALIDATED
  ```
  (Validator must echo similar in final report.)

**Sub-dispatch in Cursor agent**: Use composer / "new agent" / "subtask" for parallel ADVOCATE, SKEPTIC, Product Skeptic. Pass full context (pdlc-goal + product-context + spec files + validation-criteria + current batch).

**State machine**: Use same files — HANDOFF.md (via pdlc-state lib), progress.md, validation-criteria.md, spec.json. Cursor terminal agent can `source hooks/lib/pdlc-state.sh; pdlc_get_field ...` and `pdlc_set_field`.

**Ref prompts (include verbatim or @import)**: validator-templates.md (all sections), product-skeptic.md, context-health.md, lightweight-paths.md, test-strategy.md, phase-viz.md etc. (copy from PDLC templates/ref/ into project or reference absolute).

**Red flags + gates**: Identical to SKILL.md (SpecGate, CriticGate, no per-task agents, max 2 fix cycles, etc.). <error-recovery> framing for self-correction on violations.

See also: pdlc-goal.md for the persistent goal file format + "use PDLC sub-protocols".
```

Cursor will auto-load .cursor/rules/*.md into relevant chat/agent contexts for PDLC work.

## Driver Script Sketch (Terminal Agent Mapping to State Machine)

Cursor's terminal + agent can run a thin driver (or directly the reference pdlc-outer-loop.sh) for long-running autonomous batches when the in-chat composer is not ideal for full loops.

**templates/cursor/pdlc-cursor-driver.sh** (or symlink/copy of outer with notes):

```bash
#!/bin/bash
# pdlc-cursor-driver.sh — Cursor terminal agent thin driver sketch
# Maps directly to same state machine (HANDOFF + progress + pdlc libs).
# In Cursor: open terminal, run this (or PDLC_SPEC_DIR=... ./hooks/pdlc-outer-loop.sh)
# Agent in chat can observe output, or user pastes results back for continuation.
# Reuses 100% portable core — no duplication.

set -euo pipefail
# PDLC_DISABLED etc. honored

# Same sourcing as grok-driver + outer-loop:
# source hooks/lib/pdlc-*.sh
# ... init HANDOFF from tasks if needed (pdlc_write_handoff)
# loop:
#   resource precheck (pdlc_resource_check)
#   decide = pdlc_director_decide (or inline lifecycle + batch logic)
#   # For Cursor: instead of full claude spawn, the "Actor" step can be:
#   #   echo "CURSOR_ACTOR_PROMPT: ..." ; # user/agent performs the batch edit in editor
#   #   or: cursor-agent --prompt "..." if Cursor exposes headless
#   # Then critics similarly via sub-composer or manual review + paste verdict.
#   # Or fall back to full outer-loop for claude-based execution inside Cursor term.
#   pdlc_critic_... + consensus
#   update HANDOFF/progress via pdlc_set_field + append body
#   until pdlc_get_field "phase" == "DONE"

# On full done: require the validator to append/echo the PDLC-DONE-VALIDATED token from pdlc-goal success criteria.
# Resume protocol identical: read progress.md + HANDOFF exactly.

echo "Cursor PDLC driver ready. Use pdlc-goal.md success criteria. Delegate to Cursor agent sub-dispatches or bash loop."
```

**Mapping to Cursor state machine**:
- Persistent goal: project root or `.claude/specs/<feat>/pdlc-goal.md` (or just use the loaded template + spec's progress.md as primary).
- State survives via files (Cursor edits + git + terminal all see same HANDOFF).
- Sub-protocols: Cursor "Apply to ..." or agent spawns for critic roles using the validator templates injected from pdlc-goal / rules.

## Usage Notes + Dogfood

- For a Cursor project: copy templates/ref/pdlc-goal.md -> project/.cursor/pdlc-goal.md (or keep reference), add the rules file, ensure hooks/ (or minimal lib shims) available for state if using bash parts.
- Full portable: no change to libs, outer-loop, critic consensus, product skeptic, batching, gates.
- Example: "In Cursor, /goal or composer: 'PDLC the addition of foo using pdlc-goal.md. Use sub-agents for critics. Only PDLC-DONE-VALIDATED after validator.' Then run pdlc-cursor-driver or manual batches + terminal state checks."

See templates/ref/pdlc-goal.md (core success + DONE), templates/grok/pdlc-grok-adapter.md (sibling), openspec/.../design.md, hooks/lib/pdlc-*.sh (all observer-style + PDLC_* env for host reuse), CLAUDE.md (Ralph separation).

This adapter is a sketch — actual Cursor rules can be generated from pdlc-goal + validator-templates at runtime.
