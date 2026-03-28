---
name: executing-qa
description: Executes QA verification and documentation reconciliation from a test plan. Use when the user says "execute qa", "run qa", "verify implementation", or wants to validate a PR against its requirements.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
hooks:
  Stop:
    - hooks:
        - type: prompt
          prompt: "You are evaluating whether Claude should stop. Context: $ARGUMENTS\n\nA prompt hook is a single-turn LLM call with no tool access — you can only evaluate based on the input fields provided, not by reading files.\n\nIf stop_hook_active is true in the input, respond {\"ok\": true} immediately to prevent infinite loops.\n\nOtherwise, examine last_assistant_message to determine the current phase:\n(1) If QA verification is in progress: does Claude's message indicate the qa-verifier returned a clean pass verdict with no remaining issues?\n(2) If verification passed and documentation reconciliation is in progress: does Claude's message indicate all reconciliation areas are covered (affected files updated, acceptance criteria modifications documented, implementation steps updated, deviation summary added where needed)?\n\nRespond {\"ok\": true} if the current phase is complete based on Claude's message, or {\"ok\": false, \"reason\": \"what appears to remain\"} if not."
          model: haiku
---

# Executing QA

Execute QA verification against a test plan, then reconcile requirements documents with the actual implementation. This skill orchestrates two sequential ralph loops — verification and reconciliation — each driven by the Stop hook.

## When to Use This Skill

- User says "execute qa", "run qa", or "verify implementation"
- User wants to validate a PR against its requirements
- After implementation is complete and `documenting-qa` has produced a test plan
- Before merging — as a final QA gate

## Quick Start

1. Accept a requirement ID as input
2. Load the test plan produced by `documenting-qa`
3. Run the verification ralph loop (verify entries + fix until clean pass)
4. Run the reconciliation loop (update requirements docs to match implementation)
5. Save results and present to user

## Input

The user provides a requirement ID in one of these formats:

- `FEAT-XXX` — Feature requirement
- `CHORE-XXX` — Chore/maintenance task
- `BUG-XXX` — Bug report

If no ID is provided, ask the user for one.

## Step 1: Parse ID and Load Documents

Parse the requirement ID to determine the type:

| ID Prefix | Type | Requirements Directory | Additional Documents |
|-----------|------|----------------------|---------------------|
| `FEAT-` | Feature | `requirements/features/` | `requirements/implementation/` (if exists) |
| `CHORE-` | Chore | `requirements/chores/` | — |
| `BUG-` | Bug | `requirements/bugs/` | — |

Load the test plan from `qa/test-plans/QA-plan-{id}.md` where `{type}` is lowercase (`feat`, `chore`, `bug`).

**If the test plan does not exist**, stop and inform the user:
> No test plan found at `qa/test-plans/QA-plan-{id}.md`. Run `documenting-qa` first to generate a test plan for this requirement.

Also load the source requirements document(s) for use during verification and reconciliation.

## Step 2: Verification Ralph Loop

This loop directly verifies each test plan entry, identifies failed entries, fixes the underlying issues, and re-verifies until all entries pass.

### Each Iteration

1. **Delegate to qa-verifier subagent** using the Agent tool:
   - Provide the test plan content
   - Provide the source requirements document(s) content
   - Instruct the subagent to directly verify each test plan entry by checking the described condition (reading files, running targeted commands, searching for patterns) and return a per-entry PASS/FAIL verdict

2. **Evaluate the verdict**:
   - If **PASS** with all entries verified → verification is complete, proceed to Step 3
   - If **FAIL** with specific entries failing → fix the underlying issues (see below)

3. **Fix issues** underlying failed entries:
   - For entries that failed because code or configuration is wrong — fix the code
   - For entries that failed because expected files or sections are missing — add or correct them
   - For entries that failed because behavior doesn't match — address the root cause
   - Do NOT write automated tests to fill coverage gaps — directly fix what the entry describes

4. **After each fix-and-verify round, attempt to finish.** The Stop hook evaluates your last message:
   - If verification passed cleanly → the hook allows stop (you proceed to reconciliation)
   - If issues remain → the hook blocks with `{"ok": false, "reason": "..."}` and feeds remaining issues back to you
   - Continue fixing and re-verifying until the hook allows completion of this phase

### Type-Specific Verification

#### FEAT (Features)
- Verify each functional requirement (FR-N) by checking the implementing code path directly
- Validate acceptance criteria against actual implementation behavior
- Confirm phase deliverables from the implementation plan exist at expected paths

#### CHORE (Maintenance Tasks)
- Verify each acceptance criterion by directly checking the described condition
- Confirm changes are minimal and correctly scoped
- Validate no unrelated modifications were introduced

#### BUG (Bug Fixes)
- Verify each root cause (RC-N) is addressed by checking the fix in the code
- Confirm reproduction steps no longer reproduce the bug
- Validate fix addresses root causes, not just symptoms

### Update Test Plan Statuses

After each verification iteration, write back the results to the test plan document (`qa/test-plans/QA-plan-{id}.md`):

- **Existing Test Verification** — update each row's `Status` column to `PASS`, `FAIL`, or `SKIP`
- **New Test Analysis** — update each row's `Status` column to `PASS`, `FAIL`, or `SKIP`
- **Code Path Verification** — update each row's `Status` column to `PASS`, `FAIL`, or `SKIP`
- **Deliverable Verification** — update each row's `Status` column to `PASS`, `FAIL`, or `SKIP`

This keeps the test plan as a living document that reflects the current verification state.

**Important**: State the verification results clearly in your message when attempting to finish — the Stop hook is a prompt-based evaluator with no tool access. It can only assess the phase from what you report.

## Step 3: Reconciliation Loop

After verification passes, reconcile the requirements documents with the actual implementation. This ensures documentation reflects what was really built.

### Reconciliation Areas

Compare the PR diff (or recent changes) against the requirements document and update:

1. **Affected files lists** — update to match actual files changed
2. **Acceptance criteria** — mark any that were modified, added, or descoped during implementation
3. **Implementation steps** — update to reflect what was actually done (for FEAT with implementation plans)
4. **Root causes** — document any new root causes discovered during implementation (for BUG)
5. **Deviation summary** — add a brief note when implementation diverged from the plan, including rationale

### Type-Specific Reconciliation

#### FEAT (Features)
- Reconcile feature requirements doc: update FRs, acceptance criteria, affected files
- Reconcile implementation plan: update phase steps, deliverables, and status

#### CHORE (Maintenance Tasks)
- Reconcile chore doc: update acceptance criteria, affected files
- Add scope notes if changes were broader or narrower than planned

#### BUG (Bug Fixes)
- Reconcile bug doc: update root causes, acceptance criteria (with RC-N tags), affected files
- Update reproduction steps if they changed

### Preservation Rules

When editing requirements documents, preserve existing structure and functionality:
- Do not remove or reformat status tracking sections
- Do not uncheck deliverable checkboxes that are already checked
- Do not remove root cause tracking or RC-N tags
- Add new information alongside existing content, don't replace it

### Loop Behavior

After each reconciliation pass, attempt to finish. The same Stop hook detects the reconciliation phase and evaluates whether all areas are covered:
- If all reconciliation areas are addressed → the hook allows stop
- If areas remain → the hook blocks with `{"ok": false, "reason": "..."}` and feeds remaining work back to you

**Important**: Clearly state which reconciliation areas you've covered in your message when attempting to finish.

## Step 4: Save Results and Present

1. Save the QA results to `qa/test-results/QA-results-{id}.md`
   - `{id}` is the full ID: e.g., `FEAT-003`, `BUG-001`
   - Example: `qa/test-results/QA-results-FEAT-003.md`
   - Create the `qa/test-results/` directory if it doesn't exist
   - Use the template from [assets/test-results-template.md](assets/test-results-template.md)

2. Present the results summary to the user, including:
   - Verification verdict (PASS/FAIL)
   - Number of verification iterations needed
   - Issues found and fixed
   - Reconciliation changes made
   - Any deviations documented

## Verification Checklist

Before finishing, verify:

- [ ] Test plan was loaded successfully
- [ ] QA verification loop ran until clean pass
- [ ] All issues identified by qa-verifier were addressed
- [ ] Documentation reconciliation covered all areas
- [ ] Affected files lists are accurate
- [ ] Acceptance criteria modifications are documented
- [ ] Implementation step updates are reflected (FEAT)
- [ ] Deviation summary is included where needed
- [ ] Existing document structure and functionality is preserved
- [ ] Results are saved to the correct path
- [ ] Results were presented to the user

## Relationship to Other Skills

| Task | Recommended Approach |
|------|---------------------|
| Document requirements first | Use `documenting-features`, `documenting-chores`, or `documenting-bugs` |
| Review requirements | Use `reviewing-requirements` |
| Build QA test plan | Use `documenting-qa` (prerequisite for this skill) |
| Create implementation plan | Use `creating-implementation-plans` |
| Implement the plan | Use `implementing-plan-phases` |
| Execute chore or bug fix | Use `executing-chores` or `executing-bug-fixes` |
| **Execute QA verification** | **Use this skill (`executing-qa`)** |
