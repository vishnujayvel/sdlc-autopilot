# CLAUDE.md — PDLC Autopilot

## Project Overview

PDLC Autopilot is a CLI skill for Claude Code that orchestrates autonomous product development lifecycles using a Director/Actor/Critic pattern.

## Code Conventions

### Shell Scripts (hooks/)
- All hook scripts MUST exit 0, even on error. Use `trap 'exit 0' ERR` (or `trap '...; exit 0' ERR` if output is needed).
- Use `set -eo pipefail` at the top of hook scripts that have ERR traps (`-u` / nounset bypasses the ERR trap and breaks fail-open). Use `set -euo pipefail` in library scripts without ERR traps.
- Use `local` **only inside function bodies**. Never use `local` in the main script body or inside loops/conditionals outside functions (macOS bash 3.2 fatal error).
- Atomic writes: write to `.tmp` then `mv` to final path. Never write directly to state files.
- HANDOFF.md uses flat YAML frontmatter (no nested objects). Parse with awk, not yq.
- `pdlc_get_field` / `pdlc_set_field` in `hooks/lib/pdlc-state.sh` are the canonical state accessors. Do not reimplement frontmatter parsing inline.
- Use `substr($0, length(key)+3)` in awk to preserve values containing `: `. Never use just `$2` with `-F': '` for value extraction.
- Prefer single-word values in HANDOFF.md fields (e.g., `PASS_WARN` not `PASS WITH WARNINGS`) to avoid word-splitting issues.
- Environment variable names: `PDLC_` prefix for all configurable vars.

### Process Enforcement
- **SpecGate** (`hooks/spec-gate.sh`): Blocks spec generation via Task tool. Specs must use Kiro skills.
- **CriticGate** (`hooks/critic-gate.sh`): Blocks Actor dispatch without prior critic review.
- **Stop Guard** (`hooks/pdlc-stop-check.sh`): Blocks exit when PDLC tasks are incomplete.
- Deny messages use `<error-recovery>` XML framing for LLM self-correction.
- The `"matcher": "Task"` in settings.json ensures gate hooks only fire for Task tool calls.
- `PDLC_DISABLED=1` bypasses all blocking hooks (SpecGate, CriticGate, Stop Guard, Outer Loop). Used during self-development to avoid bootstrapping circularity. External governance provided by GitHub Spec Kit (`.specify/`).

### Testing
- Framework: BATS-core (`bats tests/`)
- Live e2e tests: `PDLC_LIVE_TESTS=1 bats tests/e2e/hooks-live.bats` (costs API credits)
- Stub tests use `tests/stubs/claude` — no API calls needed.
- Test helpers in `tests/helpers/common-setup.bash` — use `create_handoff`, `run_hook` for consistency.

### State Management
- `.pdlc/state/` is gitignored (runtime state, not version-controlled).
- Only `.pdlc/state/.gitkeep` is tracked.
- HANDOFF.md is the single source of truth for cross-session state.

### Git
- Hook scripts should never block Claude's git operations.
- The outer loop auto-commits to specific directories: `hooks/`, `.pdlc/`, `src/`, `tests/`.
- `.pdlc/state/*` is gitignored so progress detection (`git diff --stat HEAD`) correctly ignores bookkeeping files.

### External Governance (Spec Kit)
- `.specify/` — Spec Kit infrastructure (templates, scripts, specs, constitution). Gitignored (developer-local).
- `.claude/commands/speckit.*.md` — Spec Kit slash commands. Gitignored (developer-local).
- `.specify/memory/constitution.md` — Authoritative principles (26 tenets). Source of truth for trade-off resolution.
- `.envrc` — Contains `PDLC_DISABLED=1` for self-development. Gitignored (developer-local).
- **Ralph** (`.specify/extensions/ralph/`, `.claude/commands/speckit.ralph.*`) — Spec Kit's autonomous implementation loop. This is tooling for *building* pdlc-autopilot, NOT part of the PDLC product. Never mix Ralph code with product code (`hooks/`, `src/`).

### Documentation
- Keep header comments in sync with actual behavior (env vars, defaults, timeouts).
- When listing default values (e.g., pattern lists), list ALL defaults, not a subset.

## Do NOT
- Use `yq` — the project has no yq dependency.
- Use `grep` pipelines for YAML parsing — use awk.
- Add nested YAML to HANDOFF.md — keep it flat.
- Skip ERR traps in hook scripts that document "always exit 0".

## Active Technologies
- Bash (POSIX-compatible shell scripts) + awk, grep, jq, bc (standard Unix tools)
- Alloy 6.2.0 (formal specification language) + Alloy Analyzer (SAT4J solver, bundled), Java 17+
- Flat YAML in HANDOFF.md (via pdlc-state.sh), text file scanning
- Claude CLI for LLM-driven Director reasoning steps

## Loop Engineering (host adapters + portability, Phase 4 revival)
PDLC uses host /goal /loop /Ralph (Spec Kit) for generic orchestration (goal decomposition, outer iteration, session resume, slash plumbing, plain dispatch). 
PDLC provides:
- Portable core: hooks/lib/* (pdlc-state, pdlc-director, pdlc-critic, pdlc-resource, pdlc-lifecycle, pdlc-session etc. — all observer-style, PDLC_* env driven, callable standalone for host reuse; see lib headers for "host adapter / Ralph driver" contract + examples).
- pdlc-goal.md adapter (templates/ref/pdlc-goal.md): thin persistent goal file + PDLC success criteria (P0/P1 mandatory, sub-protocols, gates) + "use PDLC sub-protocols" + completion token (PDLC-DONE-VALIDATED after validator). Hosts load it for entry.
- Reference driver: hooks/pdlc-outer-loop.sh (documented as Ralph-compatible example; thin loop over the libs + HANDOFF + resource guards + critic eval).
Keep Ralph code out of product (never mix into hooks/, src/, templates/). 
PDLC special (non-negotiable invariants, preserved across hosts): Product Skeptic (always Phase P1 parallel, 5 lenses + KILL independent), Dual-Critic (ADVOCATE + SKEPTIC consensus per batch/final; enables future decomp), file-group batching (one Actor + 2 Critics), full PDLC lifecycle (pdlc-lifecycle.sh + phases + gates), SpecGate/CriticGate/StopGuard enforcement, resource governance (#53), lightweight paths, retrospective/context health.
See: openspec/changes/loop-simplification-v4/{design,proposal,tasks}.md , templates/grok/pdlc-grok-adapter.md , templates/cursor/pdlc-cursor-adapter.md , templates/ref/pdlc-goal.md .
