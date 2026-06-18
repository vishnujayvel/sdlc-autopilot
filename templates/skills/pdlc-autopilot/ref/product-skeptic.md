# Product Skeptic

**See `templates/ref/pdlc-goal.md` for host-aligned entry ( /goal + pdlc-goal.md for P0/P1 + delegation to host /loop ).** Product Skeptic (P1) is core PDLC special — 5-lens adversarial review preserved verbatim for all hosts (Claude, Grok, Cursor, Ralph). SKILL slim delegates generic orchestration; this + pdlc-goal injects the skeptic behavior.

**What:** Adversarial critic that checks requirements and specs against product-context.md.

**When it runs:** Phase 0b — ALWAYS runs (parallel with ADVOCATE/SKEPTIC) since product-context.md is mandatory.

**Purpose:** Prevent the build trap — catching scope creep, audience drift, and premature features BEFORE implementation starts.

---

## Verdict Types

| Verdict | Meaning | Director Action |
|---------|---------|-----------------|
| `[APPROVE]` | Spec aligns with product context | Proceed to Phase 1+ |
| `[SCOPE]` | Spec is 80%+ bloat — cut to core | Present cuts to user, apply confirmed cuts, proceed |
| `[KILL]` | Spec contradicts product thesis or hits kill criteria | Block. Present reasoning. User can override. |

---

## Tier-Based Scrutiny

The Product Skeptic adjusts its aggressiveness based on tier:

| Tier | Scrutiny Level | Expected Outcome |
|------|---------------|-----------------|
| **Tier 0: Personal** | Light — "Does this serve your stated problem?" | Almost always APPROVE. SCOPE if feature list ballooned. |
| **Tier 1: Community** | Standard — full 5-lens analysis | APPROVE or SCOPE. KILL rare but valid. |
| **Tier 2: Enterprise** | Strict — every feature must justify ROI | SCOPE is common. Features must map to business metrics. |

---

## 5-Lens Analysis

The Product Skeptic evaluates the spec through 5 lenses:

### Lens 1: BUILD TRAP

```text
Question: Is this solving a REAL pain point, or is it technically interesting?

Check against: product-context.md → "Core Thesis & Problem"

Red flags:
- Spec doesn't reference any stated problem
- Feature is architecturally elegant but user-invisible
- "Nice to have" disguised as "must have"
- Solution looking for a problem

Tier 0: Light check — personal tools can be "because I want to"
Tier 1+: Must trace to stated pain point
```

### Lens 2: AUDIENCE ALIGNMENT

```text
Question: Is this serving the target persona, or scope-creeping to a different audience?

Check against: product-context.md → "Audience & Maturity Tier"

Red flags:
- Feature serves enterprise users when product is Tier 0 personal tool
- Adding multi-tenancy to a single-user tool
- Internationalization before product-market fit
- "What if someone wants..." for a persona that isn't the target

Tier 0: "Does this serve ME?"
Tier 1: "Does this serve the stated persona?"
Tier 2: "Does this serve the persona AND justify the investment?"
```

### Lens 3: MVP HYDRATION

```text
Question: Is this V1 Core, or is a Layer 2/3 feature creeping into the current scope?

Check against: product-context.md → "MVP Scope & Hydration Roadmap"

Red flags:
- Spec implements features explicitly listed in Layer 2 or Layer 3
- Current maturity is "MVP" but spec adds polish/optimization features
- Feature depends on other features that aren't built yet
- "While we're at it" additions not in any layer

Tier 0: Flexible — personal tools can re-scope freely
Tier 1+: Strict — Layer 2 features in V1 scope → [SCOPE] verdict
```

### Lens 4: KILL CRITERIA ENFORCEMENT

```text
Question: Has any kill criterion been triggered?

Check against: product-context.md → "Kill Criteria"

Red flags:
- Building features for a product that should be abandoned
- Kill criterion explicitly triggered but work continues
- Maintaining legacy when the world moved on

ALL TIERS: If a kill criterion is met → [KILL] verdict
(Tier 0 with "none" listed → this lens is a no-op)
```

### Lens 5: OUTPUT CONTRACT CONSISTENCY

```text
Question: Can the spec's output descriptions be misinterpreted by consumers?

Check against: requirements.md → acceptance criteria for output-producing features

Red flags:
- Vague output specs ("return a decision", "send a response") without exact format
- Consumer expectation mismatch (spec says one format, consumers expect another)
- Spec references external protocol (e.g., "follow Claude Code hook format") without inline JSON example
- Multiple output modes described ambiguously (block vs. allow described as "return action")

ALL TIERS: Output contract mismatches cause bugs that pass all tests.
Tier 0: Light check — "Is the output shape clear to ME?"
Tier 1+: Strict — every output must have exact shape in ACs
```

---

## Prompt Template

### Required Inputs

| Variable | Source | Description |
|----------|--------|-------------|
| `{product_context_full}` | `{project}/.claude/product-context.md` | Full content of the product context file |
| `{requirements_full}` | `{spec_dir}/requirements.md` | Full content of the requirements file |
| `{tasks_full}` | `{spec_dir}/tasks.md` | Full content of the tasks file (if available) |
| `{tier_level}` | Extracted from product-context.md | Audience tier: 0, 1, or 2 |

```text
Task tool (general-purpose):
  description: "Product Skeptic review"
  prompt: |
    You are the PRODUCT SKEPTIC — an adversarial reviewer checking whether
    this spec should be built AT ALL.

    You are NOT checking code quality or technical design. You are checking
    PRODUCT ALIGNMENT: does this spec serve the product's stated purpose?

    ## Product Context (SOURCE OF TRUTH)
    {product_context_full}

    ## Spec Under Review
    ### Requirements
    {requirements_full}

    ### Tasks (if available)
    {tasks_full}

    ## Your 5-Lens Analysis

    For each lens, provide:
    - ✅ ALIGNED: [evidence from product-context.md]
    - ⚠️ DRIFT: [what's drifting and why]
    - ❌ VIOLATION: [direct contradiction with product context]

    ### Lens 1: BUILD TRAP
    Does every requirement trace to the stated problem in "Core Thesis"?
    [Analysis]

    ### Lens 2: AUDIENCE ALIGNMENT
    Does every feature serve the declared persona at the declared tier?
    [Analysis]

    ### Lens 3: MVP HYDRATION
    Are any Layer 2/3 features sneaking into this scope?
    [Analysis]

    ### Lens 4: KILL CRITERIA
    Has any kill criterion been triggered?
    [Analysis]

    ### Lens 5: OUTPUT CONTRACT CONSISTENCY
    Could any output format be misinterpreted by consumers?
    [Analysis]

    ## Output Format (REQUIRED)

    Return exactly:
    1. LENS_RESULTS: For each of the 5 lenses, state PASS/CONCERN with 1-line evidence
    2. VERDICT: One of APPROVE / SCOPE / KILL
    3. SCOPE_CUTS: (only if SCOPE) Numbered list of specific requirements to defer
    4. KILL_REASON: (only if KILL) 1-line reason why this shouldn't be built
    5. CONFIDENCE: HIGH/MEDIUM/LOW with reasoning

    ## Verdict

    Based on the tier ({tier_level}), apply the appropriate scrutiny level.

    Choose ONE:
    - [APPROVE] — Spec aligns with product context. Proceed.
    - [SCOPE] — Cut these specific requirements to realign: [list FR-* IDs to cut]
      Reasoning: [why each cut is necessary]
    - [KILL] — Do not build this. Reasoning: [specific product-context violation]
```

---

## Director Verdict Handling

### On `[APPROVE]`

```text
Log: "Product Skeptic: APPROVE — spec aligns with product context"
→ Proceed to Phase 1+ (batch execution)
```

### On `[SCOPE]`

```text
1. Present the Product Skeptic's cuts to the user:
   "Product Skeptic recommends cutting these requirements:
    - FR-X: [reason] — this is Layer 2, not V1
    - FR-Y: [reason] — serves enterprise persona, product is Tier 0

    Accept these cuts? [Yes / No / Modify]"

2. Apply confirmed cuts:
   - Remove cut FR-* from requirements.md
   - Remove corresponding tasks from tasks.md
   - Update spec.json: product_skeptic_verdict = "scope"

3. Proceed to Phase 1+ with reduced scope
```

### On `[KILL]`

```text
1. BLOCK execution. Do NOT proceed to Phase 1+.

2. Present reasoning to user:
   "Product Skeptic recommends NOT building this feature:
    [Specific reasoning with product-context.md references]

    Options:
    a) Accept KILL — abandon this spec
    b) Override — proceed anyway (your call)
    c) Revise — update product-context.md and re-evaluate"

3. If user overrides:
   - Log: "Product Skeptic: KILL overridden by user"
   - Update spec.json: product_skeptic_verdict = "kill_overridden"
   - Proceed to Phase 1+
```

---

## Consensus with ADVOCATE/SKEPTIC

The Product Skeptic runs IN PARALLEL with the existing ADVOCATE/SKEPTIC in Phase 0b, but evaluates a different dimension:

| Agent | Evaluates | Can Block? | Blocking Behavior |
|-------|-----------|-----------|-------------------|
| ADVOCATE | Technical quality of spec | Yes if FAIL | Both ADVOCATE and SKEPTIC must not FAIL for Phase 1+ |
| SKEPTIC | Technical gaps in spec | Yes if FAIL | Both ADVOCATE and SKEPTIC must not FAIL for Phase 1+ |
| Product Skeptic | Product alignment of spec | Yes if KILL; conditionally if SCOPE | KILL blocks independently. SCOPE requires presenting cuts to user, then proceeds after confirmation. |

**Blocking rules:**
- **KILL** blocks Phase 1+ independently -- even if ADVOCATE and SKEPTIC both PASS, a KILL verdict stops execution until the user overrides or abandons.
- **SCOPE** is a conditional resolution: the Director presents recommended scope cuts to the user, applies confirmed cuts, then proceeds to Phase 1+. SCOPE does not block on its own.
- **ADVOCATE/SKEPTIC** must not FAIL. If both FAIL, the spec must be fixed and all three re-run.

See @ref/validator-templates.md "Resolution matrix" table for the full 3-agent consensus matrix.

**Host-aligned entry:** see templates/ref/pdlc-goal.md for host /goal entry + pdlc-goal.md supplies PDLC rules + adapters (P1 Product Skeptic is mandatory here; classification + delegation to /loop for execution). All cross-refs updated per loop-simplification-v4 Phase 3.
