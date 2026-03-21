---
name: documenting-qa
description: Builds a QA test plan from requirements documents. Use when the user says "document qa", "create test plan", "qa plan", or provides a requirement ID (FEAT-XXX, CHORE-XXX, BUG-XXX) for QA planning.
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
hooks:
  Stop:
    - hooks:
        - type: prompt
          prompt: "You are evaluating whether Claude should stop. Context: $ARGUMENTS\n\nA prompt hook is a single-turn LLM call with no tool access — you can only evaluate based on the input fields provided, not by reading files.\n\nIf stop_hook_active is true in the input, respond {\"ok\": true} immediately to prevent infinite loops.\n\nOtherwise, examine last_assistant_message. Claude should have delegated to a qa-verifier subagent and received a completeness verdict. Based on Claude's last message, determine if the test plan covers every acceptance criterion, FR-N, RC-N, and phase deliverable from the source requirements.\n\nRespond with {\"ok\": true} if Claude's message indicates the plan is complete, or {\"ok\": false, \"reason\": \"what appears to be missing based on Claude's message\"} if gaps remain."
          model: haiku
---

# Documenting QA

Build a comprehensive QA test plan from requirements documents. The test plan maps every acceptance criterion, functional requirement, and root cause to verification entries, ensuring complete coverage before QA execution begins.

## When to Use This Skill

- User says "document qa", "create test plan", or "qa plan"
- User provides a requirement ID (FEAT-XXX, CHORE-XXX, BUG-XXX) for QA planning
- After implementation is complete and before merging — to prepare for QA verification

## Quick Start

1. Accept a requirement ID as input
2. Parse the ID to determine type and locate source documents
3. Load and analyze requirements
4. Build a structured test plan
5. Verify plan completeness via qa-verifier subagent
6. Save test plan and present to user

## Input

The user provides a requirement ID in one of these formats:

- `FEAT-XXX` — Feature requirement
- `CHORE-XXX` — Chore/maintenance task
- `BUG-XXX` — Bug report

If no ID is provided, ask the user for one.

## Step 1: Parse ID and Locate Documents

Parse the requirement ID to determine the type and locate source documents:

| ID Prefix | Type | Requirements Directory | Additional Documents |
|-----------|------|----------------------|---------------------|
| `FEAT-` | Feature | `requirements/features/` | `requirements/implementation/` (if exists) |
| `CHORE-` | Chore | `requirements/chores/` | — |
| `BUG-` | Bug | `requirements/bugs/` | — |

Search for files matching the pattern `{PREFIX}-{NNN}*.md` in the appropriate directory. Error clearly if no matching document is found — include the expected path in the error message.

For `FEAT-` IDs, also search `requirements/implementation/` for a matching implementation plan. If found, load it as an additional source document. If not found, note the absence but proceed with the feature requirements document alone.

## Step 2: Analyze Requirements

Read the source document(s) and extract all verifiable items:

### For FEAT (Features)
- All functional requirements (FR-N entries)
- All acceptance criteria
- Phase deliverables from the implementation plan (if available)
- Non-functional requirements that are testable

### For CHORE (Maintenance Tasks)
- All acceptance criteria
- Scope boundaries (what should and should NOT change)

### For BUG (Bug Fixes)
- All root causes (RC-N entries)
- All acceptance criteria (with their RC-N traceability tags)
- Reproduction steps (for regression test verification)

## Step 3: Build Test Plan

Use the template from [assets/test-plan-template.md](assets/test-plan-template.md) to build the test plan.

For each extracted item from Step 2, create a test plan entry in the appropriate section:

### FEAT Test Plan Entries
- Map each FR-N to a "Code Path Verification" entry with expected behavior
- Map each acceptance criterion to a verification checklist item
- Map each phase deliverable to a "Deliverable Verification" entry
- Identify existing tests that cover the feature area

### CHORE Test Plan Entries
- Map each acceptance criterion to a verification checklist item
- Add scope verification entries (confirm no unrelated changes)
- Identify existing tests that should still pass (regression check)

### BUG Test Plan Entries
- Map each RC-N to a "Code Path Verification" entry targeting the root cause
- Map each acceptance criterion to a verification checklist item with its RC-N tag
- Add reproduction step verification entries (confirm bug no longer reproduces)
- Identify existing tests related to the bug area

## Step 4: Verify Plan Completeness (Ralph Loop)

Delegate plan completeness verification to the `qa-verifier` subagent:

1. Use the Agent tool to spawn a `qa-verifier` subagent
2. Provide the subagent with:
   - The test plan content built in Step 3
   - The source requirements document(s) content
   - Instructions to verify every AC, FR-N, RC-N, and phase deliverable is covered
3. The subagent returns a completeness verdict

If the subagent identifies gaps:
- Add the missing items to the test plan
- Re-delegate to the subagent for another verification pass

**After each verification round, attempt to finish.** The Stop hook will evaluate your last message to determine if the plan is truly complete. If gaps remain, it will block with `{"ok": false, "reason": "..."}` and feed the missing items back to you. Continue adding missing items and re-verifying until the hook allows completion.

**Important**: State the verification results clearly in your message when attempting to finish — the Stop hook is a prompt-based evaluator with no tool access. It can only assess completeness from what you report in your message.

## Step 5: Save and Present

1. Save the completed test plan to `qa/test-plans/QA-plan-{id}.md`
   - `{id}` is the full ID: e.g., `FEAT-003`, `BUG-001`
   - Example: `qa/test-plans/QA-plan-FEAT-003.md`
   - Create the `qa/test-plans/` directory if it doesn't exist
2. Present the test plan to the user for review before they proceed to `executing-qa`

## Verification Checklist

Before finishing, verify:

- [ ] Requirement ID was parsed correctly and source documents were found
- [ ] All acceptance criteria from the source document are covered in the test plan
- [ ] All FR-N (features), RC-N (bugs), or scope items (chores) are mapped to test plan entries
- [ ] Implementation plan deliverables are covered (for FEAT IDs with implementation plans)
- [ ] The qa-verifier subagent confirmed plan completeness
- [ ] Test plan is saved to the correct path
- [ ] Test plan was presented to the user

## Relationship to Other Skills

| Task | Recommended Approach |
|------|---------------------|
| Document requirements first | Use `documenting-features`, `documenting-chores`, or `documenting-bugs` |
| Create implementation plan | Use `creating-implementation-plans` |
| Implement the plan | Use `implementing-plan-phases` |
| **Build QA test plan** | **Use this skill (`documenting-qa`)** |
| Execute QA verification | Use `executing-qa` (requires test plan from this skill) |
