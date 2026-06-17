# Context Health: Freshness, Decision Log, Retrospective, Drift Detection

**Why:** Products evolve across sessions. Context rots when decisions evaporate with conversation compaction. "Context is a scarce resource" — use automated freshness validation and repository-as-system-of-record.

**Host note (pdlc-goal.md + Phase 4 portability):** For Grok/Cursor/Ralph hosts, pdlc-goal.md (templates/ref/) is the entry that mandates this context health protocol on every invocation + retrospective at end of paths. See templates/ref/pdlc-goal.md (persistent goal + sub-protocols) and adapters. Portable core (lib/pdlc-freshness.sh) reused by any driver. Updated per loop-simplification-v4 Phase 3: see pdlc-goal.md for host-aligned entry notes.

---

## Freshness Protocol

**Mechanism:** HTML comment in product-context.md tracks last review.

```markdown
<!-- last_reviewed: 2026-02-23 -->
<!-- reviewed_by: user|retrospective -->
```

### Staleness Thresholds

| Tier | Stale After | Rationale |
|------|-------------|-----------|
| Tier 0 (Personal) | 90 days | Low churn, personal tools evolve slowly |
| Tier 1 (Community) | 30 days | Community feedback drives faster iteration |
| Tier 2 (Enterprise) | 14 days | Market pressure, customer commitments |

### Freshness Check Protocol

Runs on EVERY PDLC invocation (all paths — full, bug fix, iteration).

```
1. Read product-context.md
2. Extract <!-- last_reviewed: YYYY-MM-DD --> comment
3. Calculate days_since = today - last_reviewed
4. Look up tier from "Audience & Maturity Tier" section
5. Compare days_since against tier threshold

IF last_reviewed MISSING:
  → Treat as stale. Suggest adding it.

IF stale:
  → WARN (non-blocking): "Product context last reviewed N days ago (threshold: M days for Tier X). Consider reviewing after this cycle."
  → Do NOT block execution. Proceed normally.
  → Flag for retrospective reminder.

IF fresh:
  → Silent. No output needed.
```

### Updating Freshness

Freshness is updated when:
- User explicitly reviews product-context.md (`reviewed_by: user`)
- Post-cycle retrospective includes context review (`reviewed_by: retrospective`)
- User dismisses staleness warning and confirms context is still accurate

```
To update: Replace the last_reviewed comment in product-context.md:
<!-- last_reviewed: {today's date YYYY-MM-DD} -->
<!-- reviewed_by: {user|retrospective} -->
```

---

## Decision Log

**What:** Append-only log of significant product decisions. Lives at project level, not spec level.

**Where:** `{project}/.claude/decision-log.md`

**Why:** Decisions made during PDLC cycles evaporate with context. The decision log is the system of record.

### When to Log a Decision

Log when:
- Product Skeptic issues SCOPE (cuts features) or KILL (blocks)
- Retrospective surfaces a learning that changes future approach
- An assumption breaks during implementation
- Scope drift is detected (intentional or not)
- A significant technical trade-off is made

Do NOT log:
- Routine batch completions
- Standard critic PASS results
- Minor code style decisions

### Decision Entry Template

```markdown
## [YYYY-MM-DD] [Title — concise, searchable]

**Context:** [What was happening? What triggered this decision?]

**Decision:** [What was decided? Be specific.]

**Alternatives considered:**
- [Option A] — [why rejected]
- [Option B] — [why rejected]

**Rationale:** [Why this option? What convinced us?]

**PDLC cycle:** [feature-name / bug-fix-description / iteration-description]

**Product context impact:** [none | updated section X | new principle added | scope changed]
```

### Decision Log File Template

```markdown
# Decision Log: [Product Name]

<!-- Append-only, newest first. Each cycle that produces decisions adds entries here. -->

## [Date] [Decision Title]
...entry...

## [Date] [Decision Title]
...entry...
```

### Director Instructions

```
On cycle completion (all paths):
  1. Check if any decisions were made during this cycle
  2. If yes: append entries to {project}/.claude/decision-log.md (create if missing)
  3. Newest entries go at TOP (after the H1 header)
  4. Reference the decision in progress.md "Decisions Logged" section
```

---

## Post-Cycle Retrospective Protocol

**When:** End of EVERY cycle (full PDLC, bug fix, iteration). This is phase B4/I4/Final.

**Duration target:** ~30 seconds. Three questions, concise answers.

### The Three Questions

```
1. WHAT CHANGED? — What was the actual outcome vs. expected?
   (Scope cuts, unexpected complexity, new requirements discovered)

2. WHAT DID WE LEARN? — Any reusable insight?
   (Pattern to repeat, mistake to avoid, assumption that broke)

3. SHOULD CONTEXT UPDATE? — Does product-context.md need changes?
   (New principle, scope shift, persona refinement, kill criteria update)
```

### Retrospective Output

```
Director writes to progress.md:

## Retrospective
- **Changed:** [1-2 sentences]
- **Learned:** [1-2 sentences]
- **Context update needed:** [yes — what section | no]
- **Decisions logged:** [yes — N entries | no]
- **Context freshness:** [updated | still fresh | stale — user deferred]
```

If "Context update needed: yes":
- Apply the update to product-context.md
- Update `<!-- last_reviewed: YYYY-MM-DD -->` and `<!-- reviewed_by: retrospective -->`
- Log the change in decision-log.md

---

## Drift Detection

**What:** Check whether implementation aligns with product-context.md principles and persona.

**When:** Added to Final Validator prompts (both ADVOCATE and SKEPTIC).

### Drift Check Additions to Validator Prompts

Add this section to the Final Validator prompt (both perspectives):

```
DRIFT CHECK — Product Alignment:
1. Read {project}/.claude/product-context.md
2. Compare implementation against:
   - Core Thesis: Does the implementation serve the stated problem?
   - Feature Philosophy: Do choices follow stated principles?
   - MVP Scope: Is everything built within V1 Core scope?
   - Audience Tier: Is complexity appropriate for the tier?
3. Classify any drift:
   - INTENTIONAL: Has a matching entry in decision-log.md → PASS (note it)
   - UNINTENTIONAL: No decision-log entry → FLAG for retrospective
4. Report drift findings in critic output
```

### Drift Classification

| Type | Description | Action |
|------|-------------|--------|
| INTENTIONAL | Decision logged, rationale documented | Note in report, no action needed |
| UNINTENTIONAL | No decision log entry, deviates from context | Flag for retrospective, suggest decision log entry |
| SCOPE CREEP | Feature not in V1 Core or Layer 2 | Flag as potential cut for Product Skeptic |

### Director Handling

```
When drift is flagged:
  IF intentional (in decision-log):
    → Note in progress.md, continue
  IF unintentional:
    → Add to retrospective queue
    → Ask during retro: "Was this drift intentional?"
    → If yes: log decision. If no: plan correction.
```
