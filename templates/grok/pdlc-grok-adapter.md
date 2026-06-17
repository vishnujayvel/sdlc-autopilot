# PDLC Grok Adapter — Host /goal + Subagent Dispatch (Phase 4)

**Scope (loop-simplification-v4 Phase 4 + revival portability)**: Thin adapter for Grok (xAI) environments. Reuses portable core from `hooks/lib/*` (pdlc-state.sh, pdlc-critic.sh, pdlc-director.sh, pdlc-resource.sh, pdlc-lifecycle.sh, pdlc-session.sh) + pdlc-outer-loop.sh as reference driver. Injects PDLC special via `templates/ref/pdlc-goal.md` (and skill ref/ when in Claude context).

**No forking of core PDLC logic.** Grok provides the host /goal (entry + persistence) + /loop (orchestration) + subagent dispatch. PDLC supplies the goal payload + critic/validator sub-protocols + gates + batching rules.

## Skill Definition (register in this env's skills context)

```yaml
name: pdlc-autopilot
description: |
  THE primary entry point for all PDLC/SDLC work in Grok context.
  Triggers on: "PDLC", "build feature with PDLC", "run full SDLC loop", "product skeptic", "continue PDLC", etc.
  Uses pdlc-goal.md as the thin persistent goal + success criteria bridge.
  Enforces: P0 product-context, P1 Product Skeptic (always), SpecGate (Kiro skills only via sub-skill if available), Phase 0b dual + Product Skeptic + Kiro validate consensus.
  Delegates generic loop/batching/resume to host /loop or thin pdlc driver.
  Dispatches subagents/skills for: Director decide, Actor (batched impl), ADVOCATE Critic, SKEPTIC Critic, Product Skeptic, Final Validator.
  Only signals completion (e.g. "DONE" token) after validator confirms success criteria + no drift + tasks complete.
  Complements: existing pdlc-outer-loop for autonomous bash-driven runs.
  DO NOT use for non-PDLC generic dev; always route PDLC mentions here.
```

**Activation:** Host /goal "PDLC: <user goal text> using pdlc-goal.md template. Delegate loop execution. Use PDLC sub-protocols for all critics/skeptic. Only DONE after full validator."

## Dispatch Mapping to Subagents/Skills (Grok-native)

- **Director (decide phase/action/batch + build prompt):** Main context or dedicated subagent call with pdlc_director_decide skeleton + pdlc-goal + product-context + current progress/validation-criteria. Reuses pdlc-director.sh logic for classification/lifecycle.
- **Actor (per file-grouped batch):** Subagent dispatch. Prompt from validator-templates (Actor section) + batch tasks + design + acceptance + {validation_criteria}. One Actor per batch (or T-Mode teammates).
- **Critics (MANDATORY per-batch + final):**
  - ADVOCATE subagent + SKEPTIC subagent (parallel) — consensus via pdlc_critic_consensus (lib) or equivalent logic in prompt.
  - Product Skeptic (P1 and drift checks) — parallel subagent using @ref/product-skeptic.md lenses + product-context.
- **SpecGate (Phase 0a/0b):** If Grok env has Kiro-equivalent skills, dispatch via skill/subagent tool ONLY (never general write). Otherwise, note and use portable path or error with cc-sdd instructions. Record provenance.
- **Final Validator:** Two subagents (ADVOCATE+SKEPTIC) + PDLC compliance + drift + SpecGate/CriticGate provenance check from progress.md + HANDOFF.
- **Other:** Test Strategy Designer, lightweight paths use same subagent matrix as SKILL.md but routed through pdlc-goal success criteria.

**Batching:** Always file-grouped (see pdlc-goal + SKILL batching strategy). Progress recorded to spec progress.md + HANDOFF.md (via pdlc-state).

**Resource / Gates:** Pre-dispatch use pdlc_resource_check (source lib). Enforce CriticGate (both critics before next batch), SpecGate (Kiro provenance). Stop Guard via pdlc-stop-check or host equivalent.

## Thin Driver (Reusable Bash + Grok Subagent Dispatch)

Example minimal driver (can live in project or ~/.grok-pdlc-driver.sh; reuses outer-loop pattern but swaps claude -p for Grok subagent tool):

```bash
#!/bin/bash
# pdlc-grok-driver.sh — thin PDLC-aware reference driver for Grok hosts
# Reuses ALL portable core. Compatible with pdlc-outer-loop.sh logic.
# Usage: PDLC_SPEC_DIR=.claude/specs/foo PDLC_GROK_DISPATCH=1 ./pdlc-grok-driver.sh
# (In Grok session: the "dispatch" steps invoke subagent with constructed prompt.)

set -euo pipefail
if [[ "${PDLC_DISABLED:-0}" == "1" ]]; then exit 0; fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/hooks/lib/pdlc-state.sh"
source "${SCRIPT_DIR}/hooks/lib/pdlc-director.sh"
source "${SCRIPT_DIR}/hooks/lib/pdlc-critic.sh"
source "${SCRIPT_DIR}/hooks/lib/pdlc-resource.sh"
source "${SCRIPT_DIR}/hooks/lib/pdlc-lifecycle.sh"
source "${SCRIPT_DIR}/hooks/lib/pdlc-session.sh"

# ... (same config, HANDOFF init, resource pre-guards, circuit breakers as outer-loop.sh)

# Per iteration (instead of claude -p ...):
#   1. pdlc_director_decide / pdlc_lifecycle_infer → decide action + prompt skeleton
#   2. Inject pdlc-goal.md content + ref/ prompts (portable copy or skill bundle)
#   3. DISPATCH: call Grok subagent(skill="pdlc-autopilot", task=director|actor|advocate|...) with prompt
#   4. pdlc_director_evaluate_critics (or host consensus) + pdlc_critic_consensus
#   5. pdlc_resource_check / drain; pdlc_session_save; advance batch in HANDOFF/progress
#   6. Loop until phase=DONE or circuit. On DONE: require validator "DONE" token.

# On completion: echo "PDLC COMPLETE. Only after validator + success criteria in pdlc-goal.md."
# Resume: same PDLC_SPEC_DIR + HANDOFF state.
```

The driver is deliberately thin: all PDLC intelligence (decide, critics, resource, state, lifecycle) from libs + pdlc-goal.md payload. Grok supplies the subagent primitive + goal persistence.

**Example dogfood on this repo:** "Use PDLC Grok adapter + pdlc-goal.md to implement small test feature (e.g. add one portable note to a lib header)."

## Integration with Existing

- Can invoke pdlc-outer-loop.sh directly for full autonomous (bash + claude) even from Grok terminal.
- pdlc-goal.md is the single source of "PDLC success criteria + DONE rule" for any host.
- When in mixed Claude/Grok: the templates/skills/pdlc-autopilot/SKILL.md remains the Claude Code version (slim in future phases); this adapter is the Grok parallel.
- Keep Ralph (Spec Kit) out of product per CLAUDE.md.

See: templates/ref/pdlc-goal.md , hooks/lib/* headers (host adapter reuse), openspec/changes/loop-simplification-v4/design.md (portable core contract), pdlc-outer-loop.sh (reference driver).

Portable by design: source libs, load pdlc-goal, map dispatches, delegate generic loop.
