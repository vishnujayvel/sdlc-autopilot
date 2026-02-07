# Validation Criteria for [Feature Name]

> **This file survives Claude Code context compaction.** Store your project-specific
> validation rules here. When the SDLC Autopilot's Director loses context due to
> conversation compaction, it re-reads this file at Step 0.5 to restore all validation
> rules, tenet checklists, and custom validator prompts. This is your single source of
> truth for "what does valid mean?" across the entire SDLC loop.
>
> **Location:** Place this file at `{spec_dir}/validation-criteria.md` alongside your
> `requirements.md`, `design.md`, and `tasks.md`.
>
> **How it works:** Every ADVOCATE and SKEPTIC validator receives the full content of
> this file in their prompt. They check your implementation against these criteria
> instead of relying on conversation memory (which gets lost during compaction).

---

## Phase Validation

### Requirements Phase

After generating `requirements.md`, verify:

- [ ] All functional requirements have unique FR-* identifiers
- [ ] Each FR-* has at least one testable acceptance criterion
- [ ] Non-functional requirements (NFR-*) are specified with measurable thresholds
- [ ] No TBD or placeholder text remains in requirements
- [ ] Edge cases and error scenarios are addressed
- [ ] Security and performance considerations are documented
- [ ] Dependencies between requirements are explicitly noted

### Design Phase

After generating `design.md`, verify:

- [ ] Architecture diagram shows all major components and their interactions
- [ ] Each FR-* requirement maps to at least one design component
- [ ] API contracts and data models are fully specified (types, not just descriptions)
- [ ] Error handling strategy is documented for each component boundary
- [ ] Technology choices are justified with rationale
- [ ] Non-goals are explicitly listed (prevents scope creep)
- [ ] Backward compatibility impact is assessed

### Tasks Phase

After generating `tasks.md`, verify:

- [ ] Every task has a unique identifier and clear title
- [ ] Each task includes acceptance criteria with expected inputs/outputs
- [ ] Tasks are mapped to FR-* requirements (traceability)
- [ ] No FR-* requirement is left uncovered by tasks
- [ ] Task dependencies are specified (which tasks block which)
- [ ] Tasks are appropriately sized (no mega-tasks spanning multiple files)
- [ ] File paths mentioned in tasks exist or are clearly marked as new

### Implementation Phase

For each implementation batch, verify:

- [ ] All acceptance criteria from the batch's tasks are satisfied
- [ ] Code compiles/parses without errors
- [ ] No hardcoded secrets, credentials, or personal data in source files
- [ ] Error handling covers the cases specified in the design
- [ ] New public APIs have documentation (comments, docstrings, or JSDoc)
- [ ] Existing tests still pass (no regressions)
- [ ] New code follows the project's established patterns and conventions

---

## Tenet Compliance

> **What are tenets?** Project-specific design principles that every artifact must
> respect. Define your tenets below. Validators will check each artifact against these
> tenets and report violations with file:line evidence.
>
> **Numbering:** Use T0 for the highest priority tenet, T1 for next, etc. In a
> conflict between tenets, lower numbers win.

### T0: [Highest Priority Tenet Name]

> _Example: "Zero runtime dependencies" or "All user input is validated" or "Backward
> compatible with v2.x API"_

```
Description: [One sentence explaining what this tenet means]

Validators check:
- [ ] [Specific, verifiable check for this tenet]
- [ ] [Another verifiable check]
- [ ] [Edge case check]
```

### T1: [Second Priority Tenet Name]

> _Example: "Error messages include actionable recovery steps" or "All file operations
> are idempotent"_

```
Description: [One sentence explaining what this tenet means]

Validators check:
- [ ] [Specific, verifiable check for this tenet]
- [ ] [Another verifiable check]
```

### T2: [Third Priority Tenet Name]

> _Add as many tenets as your project needs. Remove this placeholder if not needed._

```
Description: [One sentence explaining what this tenet means]

Validators check:
- [ ] [Specific, verifiable check for this tenet]
```

---

## Validation Agent Prompt

> **Purpose:** This prompt is injected into every ADVOCATE and SKEPTIC validator. It
> gives them project-specific instructions beyond the default checklist. Use this to
> encode domain knowledge, coding standards, or review priorities that are unique to
> your project.

```
You are the Tenet Validation Agent for [Feature Name].

Your task: Validate [ARTIFACT_TYPE] against the tenets and phase checklists defined
in this file.

Input:
- Artifact to validate: [ARTIFACT_PATH]
- Phase: [requirements | design | tasks | implementation]
- Tenets: See "Tenet Compliance" section above

Process:
1. Read the artifact thoroughly
2. For each item in the relevant Phase Validation checklist, verify compliance
3. For each tenet (T0, T1, ...), check all sub-items
4. Cite file:line evidence for every finding (pass or fail)

Output format:

| Check | Status | Evidence |
|-------|--------|----------|
| [Phase checklist item] | PASS/FAIL/WARN | [file:line or specific quote] |
| T0: [sub-check] | PASS/FAIL/WARN | [file:line or specific quote] |
| T1: [sub-check] | PASS/FAIL/WARN | [file:line or specific quote] |

Summary:
- Total checks: [N]
- Passed: [N]
- Failed: [N]
- Warnings: [N]

Verdict: PASS / PASS WITH WARNINGS / FAIL
```

---

## SDLC Loop Integration

> **How validators use this file:** The SDLC Autopilot Director reads this file at
> Step 0.5 of every loop iteration. It passes the full content to each validator
> (ADVOCATE and SKEPTIC) as their source of truth. The yaml block below documents
> which section applies to which phase.

```yaml
# This block tells the Director which validation section to use at each phase.
# The Director reads this file and routes the relevant section to each validator.

phase_validation:
  requirements:
    artifact: requirements.md
    checklist: "Phase Validation > Requirements Phase"
    tenets: "Tenet Compliance (all)"
    validators:
      - role: ADVOCATE
        focus: "Can these requirements be implemented? Look for strengths."
      - role: SKEPTIC
        focus: "What gaps could cause failure? Look for weaknesses."

  design:
    artifact: design.md
    checklist: "Phase Validation > Design Phase"
    tenets: "Tenet Compliance (all)"
    validators:
      - role: ADVOCATE
        focus: "Is this design feasible and well-structured?"
      - role: SKEPTIC
        focus: "What could break? Missing error handling? Scalability gaps?"

  tasks:
    artifact: tasks.md
    checklist: "Phase Validation > Tasks Phase"
    tenets: "Tenet Compliance (all)"
    validators:
      - role: ADVOCATE
        focus: "Are tasks clear and actionable? Good coverage?"
      - role: SKEPTIC
        focus: "Missing acceptance criteria? Uncovered requirements? Vague items?"

  implementation:
    artifact: "changed files in batch"
    checklist: "Phase Validation > Implementation Phase"
    tenets: "Tenet Compliance (all)"
    validators:
      - role: ADVOCATE
        focus: "Does the code satisfy acceptance criteria? Cite file:line evidence."
      - role: SKEPTIC
        focus: "What's missing? Edge cases? Regressions? Tenet violations?"

# Compaction survival: When context is lost, the Director re-reads this file
# and reconstructs all validation rules from the sections above.
compaction_survival:
  recovery_step: "Step 0.5"
  action: "Re-read {spec_dir}/validation-criteria.md"
  result: "All validation rules, tenets, and prompts restored from disk"
```
