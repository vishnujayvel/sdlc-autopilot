# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned for v2.0.0
- Reserved for breaking changes
- cc-sdd 3.x compatibility (if spec format changes)
- Skill format changes (if Claude Code skill system evolves)

### Planned for v1.1.0
- Stop hook (`sdlc-stop-check.sh`) - prevents Claude from exiting when SDLC tasks are incomplete
- Post-edit lint hook (`post-edit-lint.sh`) - auto-formats files after writes using project's configured formatter
- Post-edit test hook (`post-edit-test.sh`) - runs related tests after source file modifications
- Hooks installer (`npx sdlc-autopilot --hooks`) with `.claude/settings.json` integration
- Hooks removal (`npx sdlc-autopilot --hooks --remove`)

## [1.0.0] - 2026-02-06

### Added

#### Core Skill (SKILL.md)
- **Director/Actor/Critic pattern** - Role-separated orchestration: Director reads spec and dispatches, Actors implement in batches, Critics validate with dual perspectives
- **Dual-perspective ADVOCATE + SKEPTIC validation** - Every validation phase runs two parallel subagents: ADVOCATE (optimistic, looks for strengths) and SKEPTIC (critical, looks for gaps), with consensus rules: both pass = proceed, both fail = block, disagree = Director decides
- **Autonomous execution loop** - Single-trigger "SDLC" invocation runs the full loop (generate, validate, batch, execute, review, fix) without asking "shall I proceed?" between phases
- **Task batching by file ownership** - Groups tasks that touch the same files into batches, dispatching one Actor + one Critic pair per batch instead of per-task agents (77-87% agent reduction)
- **Context compaction survival** - `validation-criteria.md` persists to disk and is re-read at Step 0.5 after conversation compaction, restoring all validation rules, tenets, and custom prompts
- **Workflow stickiness** - `active_workflow` and `sdlc_state` persisted in `spec.json` enable session recovery and resume from last known phase
- **Auto-generation protocol (Phase 0a)** - Automatically invokes `kiro:spec-requirements`, `kiro:spec-design`, and `kiro:spec-tasks` as sub-operations when artifacts are missing, instead of asking the user to run them manually
- **Phase 0b dual validation** - Requirements, design, and tasks each validated by ADVOCATE + SKEPTIC before execution begins; includes `kiro:validate-gap` (informational) and `kiro:validate-design` (GO/NO-GO)
- **Max 2 fix cycles per batch** - If Actor fixes fail after 2 Critic re-reviews, execution stops and escalates to user instead of infinite-looping
- **Validation criteria template** - `examples/validation-criteria-template.md` provides a starter template for project-specific validation rules that survive context compaction

#### T-Mode: 5 Parallelization Strategies (S1-S5)
- **S1: File Ownership** - N teammates, each owns exclusive files, maximum parallelism for independent modules
- **S2: Impl + Test** - Builder + Tester pair working in parallel, quality-focused with tests written against design interfaces
- **S3: Full Triad** - Builder + Tester + Product Eye for exploratory features where spec is evolving
- **S4: Pipeline** - Sequential handoff chain (schemas -> handlers -> tests) for tasks with strict dependencies
- **S5: Swarm** - Multiple concerns on the same files (core logic, error paths, edge cases) with Lead reconciliation
- **Strategy selection flowchart** - Director analyzes batch characteristics (file groups, test needs, spec maturity, dependency chains) and presents top 2-3 strategies to user
- **T-Mode auto-detection** via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` environment variable
- **File ownership enforcement** - No two teammates touch the same file in S1/S4; shared files (index.ts, barrels) reserved for Lead

#### CLI Installer
- `npx sdlc-autopilot` installs SKILL.md to `~/.claude/skills/sdlc-autopilot/` (global)
- `npx sdlc-autopilot --project` installs to `.claude/skills/sdlc-autopilot/` (project-level)
- `--dry-run` flag shows what would be installed without writing files
- `--yes` flag skips overwrite confirmation prompts
- `--version` and `--help` flags
- Prerequisite detection: warns if cc-sdd is not installed in the current project
- Zero production npm dependencies (Node.js built-ins only)

#### Documentation & Examples
- Comprehensive README with Mermaid architecture diagrams
- Validation criteria template (`examples/validation-criteria-template.md`)
- MIT license

### Dependencies
- **Runtime prerequisite:** [cc-sdd](https://github.com/gotalab/cc-sdd) >= 2.0.0 (provides kiro:spec-* commands)
- **Tested with:** cc-sdd v2.1.1
- **Node.js:** >= 18
- **Zero production npm dependencies**