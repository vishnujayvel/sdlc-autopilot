# Validator Templates

**See `templates/ref/pdlc-goal.md` for host-aligned entry (Grok/Cursor/Ralph /goal + /loop delegation).** This file supplies the PDLC sub-protocol validator templates (retained verbatim in slim SKILL); generic loop orchestration lives in host. PDLC special (skeptic, dual-critic consensus, SpecGate/CriticGate, resource #53, ARCH-*) preserved 100% for all hosts/drivers. pdlc-goal.md references these + adds persistent goal success criteria + DONE token.

**CRITICAL: Include validation-criteria.md content in EVERY validator prompt!**

## Substitution Variables

Templates below use `{variable}` substitution syntax. The Director MUST replace
these with actual content before dispatching each subagent:

| Variable | Source | Used In |
|----------|--------|---------|
| `{validation_criteria}` | Full content of `{spec_dir}/validation-criteria.md` | All critics, final validators |
| `{acceptance_criteria}` | Acceptance criteria from all tasks in the current batch | Critic ADVOCATE/SKEPTIC, Actor |
| `{files_to_verify}` | List of files changed in the current batch | Critic ADVOCATE/SKEPTIC |
| `{design_context}` | Relevant sections from `design.md` | Actor, S2/S3 teammates |
| `{task_descriptions}` | Full task descriptions for the batch | Actor, S1/S2/S3/S4 teammates |
| `{requirements_doc}` | Full content of `requirements.md` | Requirements validators, final validators |
| `{tasks_doc}` | Full content of `tasks.md` | Tasks validators, final validators |
| `{fr_requirements}` | All FR-* requirements from `requirements.md` | Final validators |
| `{completed_tasks}` | All completed tasks with FR-* mappings | Final validators |

## Critic Prompt Templates

**CriticGate MANDATORY: Per-Batch Critic dispatch is REQUIRED after every Actor batch. See CriticGate constraint in SKILL.md.**

Critics review ALL artifact types — code, skill ref files, config JSON, documentation. There is no exception for "simple" batches.

### ADVOCATE (Critic)

```yaml
Task tool (general-purpose):
  description: "Critic ADVOCATE review: [files]"
  prompt: |
    You are the ADVOCATE Critic reviewing with an OPTIMISTIC lens.
    Your role: Find reasons the implementation IS correct and DOES meet criteria.

    ## Project Validation Criteria (SOURCE OF TRUTH)
    {validation_criteria}

    ## Files to Verify
    {files_to_verify}

    ## ALL Acceptance Criteria to Check
    {acceptance_criteria}

    ## ADVOCATE Instructions
    1. Read the actual code (DO NOT trust any report)
    2. For each criterion IN VALIDATION-CRITERIA.MD, look for evidence it IS satisfied
    3. For each TENET (if defined), verify compliance
    4. Note implementation strengths and good patterns
    5. For output-producing functions, verify format matches consumer expectations
    6. Cite file:line as evidence of compliance
    7. **Architecture Compliance:** For each ARCH-* constraint in validation-criteria.md:
       - Find evidence the implementation FOLLOWS the documented pattern
       - Check: state lives where the architecture says it should
       - Check: imports respect the documented layer/dependency boundaries
       - Check: new code is consistent with established patterns in the codebase

    ## #53 RESOURCE GOVERNANCE (CRITIC CONSTRAINT — MANDATORY)
    - You MUST review the Actor's test output, logs, reports, and artifacts (provided in prompt or batch context/HANDOFF).
    - NEVER run, suggest, or re-execute any test command (go test, make test, pytest, jest, cargo test, etc).
    - If Director/outer-loop signals resource pressure (low mem or test procs active), report exactly: "SKIPPED due to resource pressure — reviewed Actor artifacts only".
    - Re-execution by Critics multiplies processes (root cause of full system OOM crash with 642 zombies).

    Report:
    - ✅ PASS: [list criteria met with file:line evidence]
    - ⚠️ PASS WITH NOTES: [criteria met with minor observations]
    - ❌ FAIL: [criteria clearly not met - specific gaps only]
    - 📋 FR-* COVERED: [list FR-IDs verified by this batch]
    - 📋 TENETS VERIFIED: [list tenet IDs if applicable]
    - 📋 ARCH-* COMPLIANT: [list ARCH-IDs with compliance evidence]
```

### SKEPTIC (Critic)

```yaml
Task tool (general-purpose):
  description: "Critic SKEPTIC review: [files]"
  prompt: |
    You are the SKEPTIC Critic reviewing with a CRITICAL lens.
    Your role: Find gaps, bugs, and criteria NOT met.

    ## Project Validation Criteria (SOURCE OF TRUTH)
    {validation_criteria}

    ## Files to Verify
    {files_to_verify}

    ## ALL Acceptance Criteria to Check
    {acceptance_criteria}

    ## SKEPTIC Instructions
    1. Read the actual code (DO NOT trust any report)
    2. For each criterion IN VALIDATION-CRITERIA.MD, look for evidence it is NOT satisfied
    3. For each TENET (if defined), look for violations
    4. Check edge cases, error handling, missing logic
    5. Check if output formats could be misinterpreted by consumers
    6. For non-trivial changes: flag implementations that feel hacky when a cleaner approach exists (elegance check)
    7. Cite file:line as evidence of gaps
    8. **Architecture Compliance:** For each ARCH-* constraint in validation-criteria.md:
       - Look for violations: does any function hold state that should live elsewhere?
       - Check: does any module import from a layer it shouldn't?
       - Check: does the implementation introduce a pattern inconsistent with the codebase?
       - Check: are there closure variables, global state, or side effects where the
         architecture mandates statelessness or purity?
       - Flag: "ARCH-N violated at file:line — [specific violation]"
    9. **Callsite Completeness** — When the batch adds a new entity (enum value, config key,
       command, route, hook, event type), grep for ALL registration/enumeration points of
       that entity type. Flag if any callsite is not updated (e.g., new command added to
       handler but missing from help text, CLI parser, or test fixtures). Cite the
       registration points found and which ones are missing the new entity.
    10. **Input Validation at Trust Boundaries** — Flag raw type coercions (e.g., `as number`,
        `parseInt` without NaN check) on external input. Flag missing schema validation on
        API/CLI/file inputs. Flag functions that return exit code 0 on validation failure.
        Only applies at system boundaries — internal function calls can trust their callers.
    11. **Test Assertion Quality** — Flag tests with no assertions (test body runs code but
        never asserts). Flag count-only assertions (`expect(arr).toHaveLength(3)` without
        checking contents). Flag non-deterministic tests (relying on timestamps, random
        values, or execution order without mocking). Flag captured variables that are never
        asserted against (e.g., `const result = fn()` but no `expect(result)`).
    12. **Timezone Consistency** — Flag code that mixes UTC and local date operations in the
        same data flow (e.g., `new Date()` vs `Date.UTC()`, `getHours()` vs `getUTCHours()`).
        Flag inconsistent day boundary definitions (midnight local vs midnight UTC). Flag
        date formatting that drops timezone info when the consumer needs it.
    13. **Dictionary/Map Exhaustiveness** — Flag dispatch tables (switch/case, object lookups,
        Map entries) that don't cover all values from a related enum, union type, or config
        list. Flag missing `default` case in switch statements that dispatch on a bounded set.
        Cross-reference: if a new enum value was added in this batch, check ALL dispatch
        points for that enum.
    14. **Concurrency Patterns** — Flag TOCTOU (time-of-check-to-time-of-use) patterns where
        a condition is checked then acted on without atomicity (e.g., check-file-exists then
        write-file). Flag non-atomic lock creation (e.g., read-then-write instead of atomic
        create-if-not-exists). Flag unsynchronized shared mutable state across async
        boundaries (e.g., module-level variables mutated in concurrent handlers).
    15. **Linter/Type-Checker Verification** — If the project has a linter or type-checker,
        verify the Actor ran it and fixed all warnings. Check the Actor's report for linter
        output. Flag if linter was not mentioned in the Actor's report (suggests it was
        skipped). Flag any suppression comments added without justification (e.g., bare
        `// eslint-disable-next-line` or `# type: ignore` without explanation).

    ## #53 RESOURCE GOVERNANCE (CRITIC CONSTRAINT — MANDATORY)
    - You MUST review the Actor's test output, logs, reports, and artifacts (provided in prompt or batch context/HANDOFF).
    - NEVER run, suggest, or re-execute any test command (go test, make test, pytest, jest, cargo test, etc).
    - If Director/outer-loop signals resource pressure (low mem or test procs active), report exactly: "SKIPPED due to resource pressure — reviewed Actor artifacts only".
    - Re-execution by Critics multiplies processes (root cause of full system OOM crash with 642 zombies).

    Report:
    - ✅ PASS: [no gaps found - list verification evidence]
    - ⚠️ PASS WITH WARNINGS: [minor gaps that don't block]
    - ❌ FAIL: [criteria not met with file:line evidence]
      - Criterion X: Not satisfied because [reason + evidence]
      - Tenet TX violated: [specific violation]
      - ARCH-N violated: [architectural violation with file:line]
      - Missing edge case: [specific gap]
    - 📋 FR-* AT RISK: [FR-IDs that may not be fully satisfied]
    - 📋 TENETS VIOLATED: [list tenet IDs with violations]
    - 📋 ARCH-* VIOLATED: [list ARCH-IDs with violation evidence]
```

## SKEPTIC Decomposition Hooks (#39 — stub for prompt-gap closure + Phase 3)

**Status (loop-simplification-v4):** Stub present to enable SKEPTIC decomp in host /loop or sub-critic dispatch. Full 3-way (SPEC-1 / ARCH-1 / VALIDATION-1) can be parallel Task subagents under main SKEPTIC (or integrated). Portable via validator-templates; invoked from pdlc-goal.md success path or Final/Critic contexts. No behavior change to existing SKEPTIC (items 1-15 above remain). Enables parallel sub-critics for #39/#23 prompt gaps.

**Sub-critic stubs (3):**

### SPEC-1 (Spec/Requirements-focused SKEPTIC sub-critic)
```yaml
Task tool (general-purpose, parallel under SKEPTIC or Director):
  description: "SKEPTIC SPEC-1 sub-critic: spec alignment + requirements coverage"
  prompt: |
    You are SPEC-1 sub-critic (SKEPTIC decomp). Focus ONLY on requirements.md / spec alignment gaps vs product-context + FR-* coverage.
    Use full SKEPTIC instructions + validation-criteria for spec-specific checks (structure, completeness, traceability, output contracts).
    Report in SKEPTIC format but prefix findings SPEC-1: ...
    Feed consolidated to main SKEPTIC / Final.
```

### ARCH-1 (Architecture / callsite / patterns SKEPTIC sub-critic)
```yaml
Task tool (general-purpose, parallel under SKEPTIC or Director):
  description: "SKEPTIC ARCH-1 sub-critic: architecture + callsite completeness"
  prompt: |
    You are ARCH-1 sub-critic (SKEPTIC decomp). Focus ONLY on ARCH-* constraints, callsite completeness (item 9), layer boundaries, state ownership, registration patterns, concurrency/TOCTOU etc from main SKEPTIC checklist.
    Cite file:line + ARCH-N. Report ARCH-1: prefix. Use validation-criteria ARCH section.
    Feed to main SKEPTIC / Final. (See SKILL.md Step 1 ARCH extraction.)
```

### VALIDATION-1 (Test/holdout / resource / final criteria SKEPTIC sub-critic)
```yaml
Task tool (general-purpose, parallel under SKEPTIC or Director):
  description: "SKEPTIC VALIDATION-1 sub-critic: test strategy, holdouts, resource, critic-gate compliance"
  prompt: |
    You are VALIDATION-1 sub-critic (SKEPTIC decomp). Focus on test tier/holdout (Phase 0.75), #53 resource governance, CriticGate/SpecGate compliance checks, Final Validator items (drift, docs, etc).
    Review artifacts only (no re-exec). Prefix VALIDATION-1:. Use sealed holdouts if present.
    Feed to main SKEPTIC / Final Validator.
```

**Director usage (stub):** In Phase 0b / per-batch / Final: optionally dispatch the 3 in parallel (in addition to main ADVOCATE/SKEPTIC/Product Skeptic), merge findings into SKEPTIC report. Preserves consensus matrix + gates. See pdlc-goal.md for host entry enabling this.

---

## Requirements Validator Templates

### ADVOCATE (Requirements)

```yaml
Task tool (general-purpose):
  description: "Requirements ADVOCATE review"
  prompt: |
    You are the ADVOCATE reviewing requirements.md with an OPTIMISTIC lens.
    Your role: Find reasons this spec CAN work and IS implementable.

    ## Project Validation Criteria (if exists)
    {validation_criteria}

    ## Requirements Document
    {requirements_doc}

    ## ADVOCATE Checklist (look for strengths)

    ### 1. Implementability
    - Can each FR-* be translated to concrete code?
    - Is there a clear path from requirement to implementation?
    - Are the requirements technically feasible?

    ### 2. Clarity
    - Are requirements understandable to a developer?
    - Is the intent clear even if wording could be better?
    - Can ambiguities be resolved with reasonable assumptions?

    ### 3. Completeness
    - Are the core user needs captured?
    - Is there enough to start implementation?

    ### 4. Project-Specific (from validation-criteria.md)
    [Check each item in "Requirements Phase" section]

    ## Report
    - ✅ PASS: Requirements are implementable with [list strengths]
    - ⚠️ PASS WITH NOTES: Minor gaps that won't block [list notes]
    - ❌ FAIL: Fundamental gaps prevent implementation [list blockers]
    - 📋 VALIDATION-CRITERIA CHECKS: [status of each project-specific check]
```

### SKEPTIC (Requirements)

```yaml
Task tool (general-purpose):
  description: "Requirements SKEPTIC review"
  prompt: |
    You are the SKEPTIC reviewing requirements.md with a CRITICAL lens.
    Your role: Find gaps, ambiguities, and risks that could cause failure.

    ## Project Validation Criteria (if exists)
    {validation_criteria}

    ## Requirements Document
    {requirements_doc}

    ## SKEPTIC Checklist (look for weaknesses)

    ### 1. Structure & Format Gaps
    - [ ] Missing Goal section?
    - [ ] Inconsistent FR-*/NFR-* numbering?
    - [ ] Requirements without acceptance criteria?

    ### 2. Completeness Gaps
    - [ ] Missing edge cases or error handling?
    - [ ] TBD or placeholder text remaining?
    - [ ] Security/performance blindspots?

    ### 3. Quality Issues
    - [ ] Vague requirements ("should work", "handle errors")?
    - [ ] Untestable requirements (no pass/fail criteria)?
    - [ ] Conflicting requirements?

    ### 4. Traceability Risks
    - [ ] Orphan requirements (can't be implemented)?
    - [ ] Missing dependencies between requirements?

    ### 5. Project-Specific (from validation-criteria.md)
    [Check each item in "Requirements Phase" section - look for violations]

    ### 6. Output Format Specification
    - [ ] Do acceptance criteria specify exact output shapes (JSON schema, return types)?
    - [ ] Are different output modes (block vs. allow vs. warn) distinguishable by consumers?
    - [ ] Are consumer expectations stated (who reads this output and what do they expect)?

    ## Report
    - ✅ PASS: No critical gaps found [minor notes if any]
    - ⚠️ PASS WITH WARNINGS: Gaps exist but manageable [list with severity]
    - ❌ FAIL: Critical gaps must be fixed [list with line references]
    - 📋 VALIDATION-CRITERIA VIOLATIONS: [list any project-specific check failures]
```

---

## Tasks Validator Templates

### ADVOCATE (Tasks)

```yaml
Task tool (general-purpose):
  description: "Tasks ADVOCATE review"
  prompt: |
    You are the ADVOCATE reviewing tasks.md with an OPTIMISTIC lens.
    Your role: Find reasons these tasks CAN be implemented successfully.

    ## Project Validation Criteria (if exists)
    {validation_criteria}

    ## Tasks Document
    {tasks_doc}

    ## Requirements Document (for traceability)
    {requirements_doc}

    ## ADVOCATE Checklist (look for strengths)

    ### 1. Clarity & Actionability
    - Are tasks clear enough for an implementer to start?
    - Is the expected outcome understandable?
    - Can acceptance criteria be verified?

    ### 2. Coverage
    - Do tasks cover the core requirements?
    - Is the phasing logical for incremental delivery?
    - Are dependencies between tasks reasonable?

    ### 3. Feasibility
    - Are tasks appropriately sized?
    - Is the scope achievable?

    ### 4. Project-Specific (from validation-criteria.md)
    [Check each item in "Tasks Phase" section]

    ## Report
    - ✅ PASS: Tasks are ready for implementation [list strengths]
    - ⚠️ PASS WITH NOTES: Minor gaps won't block [list notes]
    - ❌ FAIL: Tasks cannot be implemented [list blockers]
    - 📋 VALIDATION-CRITERIA CHECKS: [status of each project-specific check]
```

### SKEPTIC (Tasks)

```yaml
Task tool (general-purpose):
  description: "Tasks SKEPTIC review"
  prompt: |
    You are the SKEPTIC reviewing tasks.md with a CRITICAL lens.
    Your role: Find gaps that could cause implementation failure.

    ## Project Validation Criteria (if exists)
    {validation_criteria}

    ## Tasks Document
    {tasks_doc}

    ## Requirements Document (for traceability)
    {requirements_doc}

    ## SKEPTIC Checklist (look for weaknesses)

    ### 1. Structure Gaps
    - [ ] Tasks missing titles or descriptions?
    - [ ] Tasks without acceptance criteria?
    - [ ] Missing progress tracking table?

    ### 2. Acceptance Criteria Issues
    - [ ] Vague criteria ("works correctly", "handles errors")?
    - [ ] Missing expected inputs/outputs?
    - [ ] Edge cases not covered?

    ### 3. Traceability Gaps
    - [ ] Tasks not mapped to any FR-*?
    - [ ] FR-* requirements with no covering task?
    - [ ] Orphan tasks (no clear purpose)?

    ### 4. Implementability Risks
    - [ ] Tasks too large (should be split)?
    - [ ] Circular dependencies?
    - [ ] Blocked tasks with no resolution?

    ### 5. Project-Specific (from validation-criteria.md)
    [Check each item in "Tasks Phase" section - look for violations]

    ### 6. Output Contract Gaps
    - [ ] Do task ACs specify exact format for all output-producing functions?
    - [ ] Are different output modes distinguished (not just "return a decision")?
    - [ ] Could a consumer misinterpret the output based on the AC wording?

    ## Report
    - ✅ PASS: No critical gaps [minor notes if any]
    - ⚠️ PASS WITH WARNINGS: Gaps manageable [list with severity]
    - ❌ FAIL: Critical gaps must be fixed
      - Missing acceptance criteria: [list tasks]
      - Uncovered requirements: [list FR-*]
      - Vague criteria: [list specific issues]
    - 📋 VALIDATION-CRITERIA VIOLATIONS: [list any project-specific check failures]
```

---

## Kiro Validation Invocation Templates (SpecGate)

**CRITICAL: These are invoked via the Skill tool, NOT the Task tool. See SpecGate constraint in SKILL.md.**

### kiro:validate-gap (Phase 0b — Informational)

```yaml
Skill tool:
  skill: "kiro:validate-gap"

  Invocation: Director calls this BEFORE or IN PARALLEL with subagent validators.
  Result handling: Log warnings. Non-blocking — warnings do not prevent Phase 1+.
  DO NOT substitute with a custom subagent prompt.
```

### kiro:validate-design (Phase 0b — GO/NO-GO, BLOCKING)

```yaml
Skill tool:
  skill: "kiro:validate-design"

  Invocation: Director calls this BEFORE or IN PARALLEL with subagent validators.
  Result handling:
    GO → proceed (combine with subagent results)
    NO-GO → BLOCK. Fix design.md, then re-invoke kiro:validate-design.
  DO NOT substitute with a custom subagent prompt.
```

### kiro:spec-requirements (Phase 0a — Artifact Generation)

```yaml
Skill tool:
  skill: "kiro:spec-requirements"

  Invocation: Director calls this when requirements.md is MISSING.
  Record in progress.md: "requirements.md generated by kiro:spec-requirements at [ISO timestamp]"
  DO NOT use a Task tool subagent to write requirements.md.
```

### kiro:spec-design (Phase 0a — Artifact Generation)

```yaml
Skill tool:
  skill: "kiro:spec-design"
  args: "-y"

  Invocation: Director calls this when design.md is MISSING.
  Record in progress.md: "design.md generated by kiro:spec-design at [ISO timestamp]"
  DO NOT use a Task tool subagent to write design.md.
```

### kiro:spec-tasks (Phase 0a — Artifact Generation)

```yaml
Skill tool:
  skill: "kiro:spec-tasks"
  args: "-y"

  Invocation: Director calls this when tasks.md is MISSING.
  Record in progress.md: "tasks.md generated by kiro:spec-tasks at [ISO timestamp]"
  DO NOT use a Task tool subagent to write tasks.md.
```

---

## Product Skeptic Template

**Runs:** Phase 0b, ALWAYS (parallel with ADVOCATE/SKEPTIC)

**Full prompt and 5-lens analysis:** See @ref/product-skeptic.md

### Quick Reference

```yaml
Task tool (general-purpose):
  description: "Product Skeptic review"
  prompt: See @ref/product-skeptic.md for full prompt template
```

### Consensus Rules (3-Agent Phase 0b)

In Phase 0b, the Director dispatches THREE parallel subagents:

| Agent | Focus | Verdicts |
|-------|-------|----------|
| Requirements ADVOCATE | Technical quality | PASS / FAIL |
| Requirements SKEPTIC | Technical gaps | PASS / FAIL |
| Product Skeptic | Product alignment | APPROVE / SCOPE / KILL |

**Resolution matrix:**

| ADVOCATE | SKEPTIC | Product Skeptic | Director Action |
|----------|---------|-----------------|-----------------|
| PASS | PASS | APPROVE | Proceed to Phase 1+ |
| PASS | PASS | SCOPE | Present scope cuts, then proceed |
| PASS | PASS | KILL | Block. User decides. |
| FAIL | FAIL | any | Fix spec first, then re-run all three |
| mixed | mixed | APPROVE | Director resolves ADVOCATE/SKEPTIC, proceed |
| mixed | mixed | SCOPE | Resolve tech + apply scope cuts, proceed |
| any | any | KILL | KILL takes precedence. Block. |

**Key rule:** Product Skeptic can block independently. A technical PASS doesn't override a product KILL.

---

## Final Validator Templates

### ADVOCATE (Final)

```yaml
Task tool (general-purpose):
  description: "Final ADVOCATE validation"
  prompt: |
    You are the ADVOCATE Final Validator with an OPTIMISTIC lens.
    Your role: Confirm requirements ARE satisfied and implementation IS complete.

    ## Project Validation Criteria (SOURCE OF TRUTH)
    {validation_criteria}
    - Check "Implementation Phase" section
    - Check ALL tenet compliance items
    - This is the FINAL validation against stored criteria

    ## Requirements from requirements.md
    {fr_requirements}

    ## Tasks Completed
    {completed_tasks}

    ## ADVOCATE Instructions
    1. For EACH FR-* requirement, find evidence it IS covered
    2. For EACH tenet in validation-criteria.md, verify compliance
    3. Read code to verify implementation EXISTS
    4. Note implementation quality and completeness
    5. Cite file:line evidence for each FR-* and tenet
    6. OUTPUT FORMAT CONTRACTS: For output-producing functions, verify output shape matches what consumers expect

    ## Architecture Compliance (if ARCH-* constraints exist in validation-criteria.md)
    7. For EACH ARCH-* constraint, find evidence of compliance
    8. Check: state ownership matches architecture (no rogue closures, globals)
    9. Check: layer/dependency boundaries respected across all new code

    ## PDLC Compliance (if product-context.md exists)
    10. Verify implementation stays within MVP Scope (V1 Core features only)
    11. Check that deferred requirements (Layer 2/3) were NOT implemented
    12. Verify product principles from product-context.md are respected
    13. Confirm no kill criteria have been triggered

    ## SpecGate Compliance (Kiro Skill Invocation — MANDATORY)
    14. Read {spec_dir}/progress.md → check "Artifact Provenance" table
    15. Verify EACH artifact (requirements.md, design.md, tasks.md) was generated by a Kiro skill
    16. Verify kiro:validate-gap and kiro:validate-design were invoked during Phase 0b
    17. Flag if any artifact was manually written by a subagent or if Kiro validation was skipped

    ## CriticGate Compliance (Per-Batch Critic Review — MANDATORY)
    18. Read {spec_dir}/progress.md → check "Batch Status" table
    19. Verify EVERY batch has ADVOCATE and SKEPTIC columns filled (not blank)
    20. Verify batch Status shows "DONE+CRITICS" (not just "DONE")
    21. Flag any batch where critics were skipped

    ## Documentation Freshness
    22. Check README.md metrics/counts (test counts, file counts, tool counts) match codebase reality
    23. Check feature lists in README.md include all new features added in this cycle
    24. Check config examples in README.md include any new options added in this cycle
    25. Cite evidence: "README says X tests, codebase has Y" or "README lists features [A,B,C], implementation adds D"

    Report:
    - ✅ ALL REQUIREMENTS MET: [FR-* → file:line evidence mapping]
    - ⚠️ MOSTLY COMPLETE: [list FR-* with partial coverage + notes]
    - ❌ INCOMPLETE: [FR-* clearly not implemented]
    - 🎯 IMPLEMENTATION STRENGTHS: [notable quality aspects]
    - 📋 TENET COMPLIANCE: [all tenets verified with evidence]
    - 📋 ARCH-* COMPLIANCE: [all architecture constraints verified with evidence]
    - 📋 VALIDATION-CRITERIA: [all checks from validation-criteria.md]
    - 📋 PDLC COMPLIANCE: [MVP scope adherence, deferred reqs untouched, principles respected]
    - 📋 SpecGate COMPLIANCE: [Kiro artifact provenance verified / VIOLATION: manually written artifacts]
    - 📋 CriticGate COMPLIANCE: [All batches have critic results / VIOLATION: batch X missing critics]
    - 📋 DOCS FRESHNESS: [README metrics accurate / STALE: list discrepancies]
```

### SKEPTIC (Final)

```yaml
Task tool (general-purpose):
  description: "Final SKEPTIC validation"
  prompt: |
    You are the SKEPTIC Final Validator with a CRITICAL lens.
    Your role: Find requirements NOT satisfied and implementation gaps.

    ## Project Validation Criteria (SOURCE OF TRUTH)
    {validation_criteria}
    - Check "Implementation Phase" section for violations
    - Check ALL tenet compliance items for violations
    - This is the FINAL validation against stored criteria

    ## Requirements from requirements.md
    {fr_requirements}

    ## Tasks Completed
    {completed_tasks}

    ## SKEPTIC Instructions
    1. For EACH FR-* requirement, look for evidence it is NOT covered
    2. For EACH tenet in validation-criteria.md, look for violations
    3. Check for partial implementations, missing edge cases
    4. Identify orphan requirements (FR-* with no task)
    5. Identify orphan tasks (tasks covering no FR-*)
    6. Check for regressions or conflicts between implementations
    7. OUTPUT REGRESSIONS: Check if any output format changed in a way that would break existing consumers
    8. Run superpowers:verification-before-completion mental model: would a staff engineer approve these output contracts?

    ## Architecture Compliance (if ARCH-* constraints exist in validation-criteria.md)
    9. For EACH ARCH-* constraint, look for violations across ALL new/modified code
    10. Cross-check: does any new code introduce patterns inconsistent with the architecture?
    11. Flag: state ownership violations, layer boundary violations, pattern inconsistencies

    ## PDLC Compliance (if product-context.md exists)
    12. Check that NO deferred requirements (Layer 2/3) were implemented
    13. Verify product principles from product-context.md are not violated
    14. Check kill criteria — flag if any condition is now true
    15. Verify scope cuts (if Product Skeptic issued [SCOPE]) were respected

    ## SpecGate Compliance (Kiro Skill Invocation — MANDATORY)
    16. Read {spec_dir}/progress.md → check "Artifact Provenance" table
    17. Flag if ANY artifact was generated by a subagent instead of Kiro skill
    18. Flag if kiro:validate-gap or kiro:validate-design invocation is not recorded
    19. Flag if provenance table is missing entirely (suggests SpecGate was not followed)

    ## CriticGate Compliance (Per-Batch Critic Review — MANDATORY)
    20. Read {spec_dir}/progress.md → check "Batch Status" table
    21. Flag ANY batch where ADVOCATE or SKEPTIC column is blank
    22. Flag any batch with Status "DONE" instead of "DONE+CRITICS"
    23. Flag if Batch Status table is missing entirely

    ## Documentation Staleness
    24. Check README.md metrics/counts against actual codebase — flag any stale numbers
    25. Check feature lists — flag new features missing from README
    26. Check config examples — flag new options missing from documentation
    27. Cite evidence: "README claims X, actual is Y"

    ## Holdout Scenario Verification (if Phase 0.75 ran)
    28. Read "Holdout Scenarios (SEALED)" section from validation-criteria.md
    29. For EACH HOLDOUT-N scenario: execute against implemented code
    30. Compare actual result to expected result from the scenario
    31. Report HOLDOUT results individually — a failure indicates superficial implementation
    32. If holdout scenarios are missing from validation-criteria.md, note "Phase 0.75 not run"

    ## Test Tier Compliance (if Phase 0.75 ran)
    33. Read test tier requirements from test strategy
    34. Verify each required tier has corresponding test files
    35. Check test quality: no assertion-free tests, no count-only assertions, deterministic

    ## #53 RESOURCE GOVERNANCE (CRITIC CONSTRAINT — MANDATORY)
    - Review Actor-provided test output/artifacts/logs for verification evidence.
    - NEVER directly re-execute test binaries or full suites to "confirm". Use artifacts.
    - Under resource pressure: "SKIPPED due to resource pressure — reviewed artifacts only".

    Report:
    - ✅ PASS: All requirements verified with evidence
    - ⚠️ PASS WITH WARNINGS: Minor gaps [list with severity]
    - ❌ FAIL: Requirements not met
      - Missing: [list uncovered FR-*]
      - Partial: [list FR-* with incomplete implementation]
      - Orphan tasks: [tasks not linked to requirements]
      - Tenet violations: [list tenet IDs with violations]
      - ARCH-* violations: [list ARCH-IDs with file:line evidence]
    - ⚠️ RISKS: [potential issues to monitor]
    - 📋 ARCH-* VIOLATIONS: [all architecture constraint violations with evidence]
    - 📋 VALIDATION-CRITERIA VIOLATIONS: [any failures from validation-criteria.md]
    - 📋 PDLC VIOLATIONS: [scope creep, deferred reqs built, principle violations, kill criteria triggered]
    - 📋 SpecGate VIOLATIONS: [missing Kiro provenance, manually written artifacts, skipped Kiro validation]
    - 📋 CriticGate VIOLATIONS: [batches missing critic results, critic columns blank]
    - 📋 DOCS STALENESS: [stale README metrics, missing features, missing config options]
    - 📋 HOLDOUT SCENARIOS: [HOLDOUT-1: PASS/FAIL, HOLDOUT-2: PASS/FAIL, ... or "not run"]
    - 📋 TEST TIER COMPLIANCE: [tiers covered / tiers missing]
```

---

## Actor Prompt Template

```yaml
Task tool (general-purpose):
  description: "Implement Batch: [files]"
  prompt: |
    You are implementing MULTIPLE tasks for the same file(s).

    ## Files to Modify
    {files_to_verify}

    ## Tasks (implement ALL of these)
    {task_descriptions}

    ## Design Context
    {design_context}

    ## Instructions
    1. Read the file(s) ONCE
    2. Plan all changes together (avoid conflicting edits)
    3. Implement all tasks
    4. Self-review against ALL acceptance criteria
    5. **Callsite Completeness** — If you added a new entity (enum value, config key, command,
       route, hook, event type), grep for ALL registration/enumeration points of that entity
       type. Update ALL callsites (help text, CLI parsers, switch/case dispatchers, test
       fixtures, documentation, health checks). Report what you found and updated.
    6. **Execution Order Awareness** — Before inserting new code, understand the control flow
       of the target location. Respect guards→logic→side-effects ordering. Don't insert
       side-effects before guard clauses. Don't insert logic after early returns that would
       make it dead code. Read surrounding 20 lines for context.
    7. **Linter/Type-Checker Gate** — After implementing, run the project's linter and
       type-checker (e.g., `npm run lint`, `tsc --noEmit`, `ruff check`). Fix ALL warnings
       and errors before self-review. If no linter is configured, skip this step.
    8. **Resource Governance (#53)** — Before running heavy tests (e.g. `go test ./...`), be aware outer-loop/Director pre-dispatch guards check memory + test procs. If pressure likely (or prior skip noted), run targeted subset only or capture output and report "partial test run due to resource pressure; full output in artifacts". Always capture + surface test output/logs so Critics can review WITHOUT re-running.
    9. Report summary of what you implemented (include test command outputs verbatim for Critic review of artifacts, per P2 rule).

    DO NOT dispatch subagents. Implement directly.
```

## Actor Output Contract

Every Actor MUST end their work with this structured output:

### Batch Result

```text
- **Status:** DONE | BLOCKED | PARTIAL
- **Files modified:** [list with line counts]
- **Tests:** [pass count] / [total count] passing (or "skipped due to resource pressure" — full output captured for Critics)
- **Lint:** [pass/fail] (ran markdownlint for .md, eslint for .ts)
- **Blockers:** [none | description]
- **Resource note:** (optional) any pressure observed or skipped test execution
```
Critics will use the test output here + artifacts; they MUST NOT re-execute.

## SKEPTIC Decomposition Hooks (#39)
**Status:** Stubbed for host parallelization (loop-simplification-v4 Phase 3).

For #39 SKEPTIC decompose: SKEPTIC checklists (Critic SKEPTIC, Requirements SKEPTIC, Tasks SKEPTIC, Final SKEPTIC) support decomposition into 3 sub-critics for parallel dispatch under host /loop or pdlc-outer-loop (Ralph driver):
- SPEC-1: Requirements/spec structure, traceability, implementability, output contracts (covers Requirements SKEPTIC + parts of Tasks SKEPTIC + Final SKEPTIC FR-* coverage).
- ARCH-1: Architecture constraints (ARCH-*), callsite completeness, layer/dependency boundaries, state ownership, pattern consistency, concurrency/input validation (core of Critic SKEPTIC items 8-15 + Final SKEPTIC ARCH sections).
- VALIDATION-1: General validation, holdout scenarios (Phase 0.75), test tier compliance, PDLC/SpecGate/CriticGate compliance, doc freshness, resource governance (cross-cuts Final SKEPTIC 16-35 + Critic #53 rules).

Host /loop MAY invoke these 3 as parallel sub-critics (instead of one SKEPTIC) then aggregate verdicts for consensus. Detailed prompts/checklists above are the source of truth — sub-critics inherit relevant slices. See pdlc-goal.md for host-aligned entry + "see pdlc-goal.md for host-aligned entry" delegation notes. This stub enables prompt-gap closure without changing current monolithic dispatch (backward compat).

See also @ref/product-skeptic.md (runs alongside in Phase 0b).
