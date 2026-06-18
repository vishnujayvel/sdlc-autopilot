# Phase Visualization

**See `templates/ref/pdlc-goal.md` for host-aligned entry ( /goal + delegation to /loop; this supplies PDLC viz sub-protocol for full/bug/iter pipelines + retros).** Phase viz templates are retained PDLC special (used in pdlc-goal success + all paths); generic loop viz/execution in host.

Pure markdown/unicode visualization for PDLC progress. No external tools, no Python — just text the Director renders inline.

---

## Phase Markers

| Symbol | Meaning |
|--------|---------|
| ✅ | Done |
| 🔵 | Active (currently executing) |
| ⬜ | Upcoming |
| ❌ | Failed |
| ⏭️ | Skipped |

## Progress Bars

```text
Full:    [████████████████] 8/8
Partial: [████████░░░░░░░░] 4/8
Empty:   [░░░░░░░░░░░░░░░░] 0/8
```

Use █ (full) and ░ (empty). 16 chars total width. Scale to batch count.

---

## Pipeline Templates

### Full PDLC Pipeline

Render on invocation and update after each phase transition.

```text
┌──────────────────────────────────────────────────────────────────────────┐
│  PDLC v3.6 ━ {feature_name} ━ Tier {N}                                  │
├──────────────────────────────────────────────────────────────────────────┤
│  {P0} P0 → {0a} 0a → {0b} 0b → {05} 0.5 → {75} 0.75 → {1+} 1+ → {Fn} Final → {P5} P5 → {Rt} Rt → {P2} P2 → {P3} P3  │
│  ctx    spec   valid  load    test     exec   valid    review  retro   docs   launch                │
│                                                              │
│  Progress: [{bar}] {done}/{total} batches                    │
│  Tests: {N} passing | Critics: ADVOCATE {a} SKEPTIC {s}      │
│  Product Skeptic: {verdict}                                  │
│  Context: {fresh|stale N days}                               │
└──────────────────────────────────────────────────────────────┘
```

**Field substitutions:**
- `{P0}` through `{P3}` (including `{05}`, `{75}`, `{Rt}`): Phase markers (✅🔵⬜❌⏭️)
- `{bar}`: Progress bar scaled to batch count
- `{a}`, `{s}`: Critic summary (e.g., "3/3 ✅" or "2/3 ⚠️")
- `{verdict}`: Product Skeptic result (e.g., "APPROVE", "SCOPE — 2 cuts applied")
- `{fresh|stale N days}`: Context health status

### Bug Fix Pipeline (Compact)

Shorter — bug fixes are lightweight.

```text
┌──────────────────────────────────────────────────────┐
│  PDLC Bug Fix ━ {description}                        │
├──────────────────────────────────────────────────────┤
│  {H} Health → {D} Diagnose → {F} Fix → {V} Validate → {R} Retro │
└──────────────────────────────────────────────────────┘
```

### Iteration Pipeline (Medium)

```text
┌──────────────────────────────────────────────────────┐
│  PDLC Iteration ━ {description} ━ Tier {N}           │
├──────────────────────────────────────────────────────┤
│  {H} Health → {M} Mini-Spec → {E} Execute → {V} Validate → {R} Retro │
│  Criteria: [{bar}] {met}/{total} met | Alignment: {status} │
└──────────────────────────────────────────────────────┘
```

**Alignment status values:**
- `V1 Core ✅` — change is within V1 scope
- `Layer 2 ⚠️` — change is Layer 2 scope, confirm intentional
- `Drift ❌` — change not in any roadmap layer

---

## Render Triggers

The Director renders/updates the pipeline visualization at these moments:

| Event | Action |
|-------|--------|
| Skill invocation | Render full pipeline with current state |
| Phase transition | Update phase marker, re-render |
| Batch completion | Update progress bar and test count |
| Critic completion | Update critic summary |
| Cycle complete | Render final summary box |

---

## Retrospective Summary Box

Rendered at end of any cycle (after retro questions answered):

```text
┌──────────────────────────────────────────────────────┐
│  Retrospective ━ {cycle_type} ━ {feature/description}│
├──────────────────────────────────────────────────────┤
│  Changed: {1-line summary}                           │
│  Learned: {1-line summary}                           │
│  Context: {updated | fresh | stale — deferred}       │
│  Decisions: {N logged | none}                        │
└──────────────────────────────────────────────────────┘
```

## Final Summary Box

Rendered at cycle completion (all paths):

### Full PDLC Final

```text
┌──────────────────────────────────────────────────────────────────────┐
│  PDLC COMPLETE ━ {feature_name} ━ Tier {N}                           │
├──────────────────────────────────────────────────────────────────────┤
│  ✅ P0 → ✅ 0a → ✅ 0b → ✅ 0.5 → ✅ 0.75 → ✅ 1+ → ✅ Final → {P5} P5 → {Rt} Rt → {P2} P2 → {P3} P3 │
│                                                              │
│  Batches: {total} | Tests: {N} passing                       │
│  Critics: ADVOCATE {pass}/{total} | SKEPTIC {pass}/{total}   │
│  Product Skeptic: {verdict} | Scope cuts: {N}                │
│  Fixes applied: {N} | Duration: {time}                       │
│  Decisions logged: {N} | Context: {updated|fresh}            │
└──────────────────────────────────────────────────────────────┘
```

### Bug Fix Final

```text
┌──────────────────────────────────────────────────────┐
│  BUG FIX COMPLETE ━ {description}                    │
├──────────────────────────────────────────────────────┤
│  ✅ Health → ✅ Diagnose → ✅ Fix → ✅ Validate → ✅ Retro │
│  Root cause: {1-line}                                │
│  Fix: {1-line} | Tests: {N} passing                  │
│  Regression test: {added|existing}                   │
│  Decisions: {N logged | none}                        │
└──────────────────────────────────────────────────────┘
```

### Iteration Final

```text
┌──────────────────────────────────────────────────────┐
│  ITERATION COMPLETE ━ {description} ━ Tier {N}       │
├──────────────────────────────────────────────────────┤
│  ✅ Health → ✅ Mini-Spec → ✅ Execute → ✅ Validate → ✅ Retro │
│  Criteria: [{bar}] {met}/{total}                     │
│  Critics: {summary} | Alignment: {status}            │
│  Decisions: {N logged | none}                        │
└──────────────────────────────────────────────────────┘
```

---

## Rendering Rules

1. **Use raw text** — no code fences around the box (render it directly in conversation)
2. **Box width adapts** — fit content, don't pad excessively
3. **Unicode box drawing** — `┌─┐│└─┘├┤` for borders (NOT ASCII `+--+`)
4. **Keep compact** — one pipeline per render, not multiple stacked
5. **Emoji in markers only** — ✅🔵⬜❌⏭️ for phases, nowhere else in the box

**Host-aligned entry (v4 Phase 3):** Visualization used from pdlc-goal.md + host /goal entry or /loop execution. see pdlc-goal.md for host-aligned entry. PDLC special (phase markers for gates, skeptic, critics, batch progress) preserved.
