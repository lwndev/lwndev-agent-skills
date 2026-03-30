# Feature Requirements: Orchestrate Bug Fix Workflow Chain

## Overview

Add the bug fix workflow chain to the `orchestrating-workflows` skill. The bug chain is a 9-step sequence with 1 pause point and no phase loop, mirroring the chore chain structurally but using bug-specific skills with root-cause-driven execution.

## Feature ID
`FEAT-011`

## GitHub Issue
[#91](https://github.com/lwndev/lwndev-marketplace/issues/91)

## Priority
High - Completes the three chain types (feature, chore, bug) in the orchestrator, enabling full SDLC coverage

## User Story

As a developer using the lwndev-sdlc plugin, I want to orchestrate a full bug fix workflow end-to-end via `/orchestrating-workflows` so that bug fixes follow the same automated sequencing as features and chores, with root cause traceability maintained throughout the chain.

## Invocation Syntax

```
/orchestrating-workflows BUG-012       # Resume existing bug workflow
```

New bug workflows are initiated when the step-1 sub-skill (`documenting-bugs`) assigns a `BUG-` prefixed ID. The orchestrator detects the chain type from the ID prefix.

## Functional Requirements

### FR-1: Bug Chain Step Sequence
Execute the bug chain as a fixed 9-step sequence:

| # | Step | Skill | Context | Expected Artifact |
|---|------|-------|---------|-------------------|
| 1 | Document bug | `documenting-bugs` | **main** | `requirements/bugs/BUG-{ID}-*.md` (includes RC-N root causes) |
| 2 | Review requirements (standard) | `reviewing-requirements` | fork | (edits existing; validates RC-N ↔ AC traceability) |
| 3 | Document QA test plan | `documenting-qa` | **main** | `qa/test-plans/QA-plan-BUG-{ID}.md` (maps RC-N to entries) |
| 4 | Reconcile test plan | `reviewing-requirements` | fork | (edits existing) |
| 5 | Execute bug fix | `executing-bug-fixes` | fork | Branch + PR created (RC-driven execution) |
| 6 | **PAUSE: PR review** | — | — | Checks `gh pr view` on resume |
| 7 | Reconcile post-review | `reviewing-requirements` | fork | (advisory) |
| 8 | Execute QA | `executing-qa` | **main** | `qa/test-results/QA-results-BUG-{ID}.md` |
| 9 | Finalize | `finalizing-workflow` | fork | PR merged, on main |

### FR-2: Bug Chain — No Plan-Approval Pause
Like the chore chain, the bug chain has no plan-approval pause step. After QA test plan reconciliation (step 4), execution proceeds directly to `executing-bug-fixes` (step 5).

### FR-3: Bug Chain — No Phase Loop
The bug chain has no dynamic phase loop. Step 5 (`executing-bug-fixes`) is a single invocation that creates the branch, addresses each root cause systematically, and opens a PR. The `populate-phases` and `phase-count` commands are not used for bug chains.

### FR-4: Bug Chain — PR Extracted from executing-bug-fixes
Like the chore chain, `executing-bug-fixes` creates the PR as part of its normal operation. After step 5 completes, the orchestrator must extract the PR number from the `executing-bug-fixes` output or detect it from the current branch via `gh pr list --head {branch} --json number`. The PR number is recorded via `scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}`.

### FR-5: Bug Step Sequence in State Script
Add a `generate_bug_steps` function to `scripts/workflow-state.sh` that produces the 9-step sequence. Update the `init` command's `bug` case to call `generate_bug_steps` instead of returning "not yet implemented".

### FR-6: Context Strategy
Three categories of context handling consistent with feature and chore chains:

- **Main context** (steps 1, 3, 8): Run directly in the orchestrator's conversation. Step 1 may prompt the user interactively. Steps 3 and 8 delegate to `qa-verifier` subagent internally and rely on Stop hooks that don't fire when forked (#92).
- **Forked context** (steps 2, 4, 5, 7, 9): Orchestrator reads the sub-skill's SKILL.md, spawns a subagent via Agent tool, validates artifacts, advances state.
- **Pause point** (step 6): Workflow halts, state persisted, user re-invokes to resume.

### FR-7: PR Review Pause (Step 6)
Same mechanism as the feature and chore chains:

- State records `prNumber`, sets `pauseReason: "pr-review"`
- On resume: calls `scripts/workflow-state.sh resume {ID}` to update `lastResumedAt`, then checks `gh pr view {prNumber} --json state,reviews,mergeStateStatus`
  - Approved/mergeable → advance to step 7
  - Changes requested → report feedback, stay paused
  - Pending → inform user, stay paused

### FR-8: Bug Chain Dispatch in Orchestrator SKILL.md
The orchestrator SKILL.md must include:

1. A bug chain step sequence table
2. Step execution procedures for bug-specific steps (step 1 maps to `documenting-bugs`, step 5 maps to `executing-bug-fixes`)
3. New workflow procedure for bug chains (when step 1 produces a `BUG-` ID)
4. Resume procedure that handles bug chain state (no plan-approval pause to handle)
5. Bug chain verification checklist items
6. Bug chain skills relationship table

### FR-9: Stop Hook Bug Support
The existing Stop hook handles bug chain workflows without modification since it reads state from `.sdlc/workflows/{ID}.json` and checks `status` and `currentStep`, which is format-consistent across all chain types.

### FR-10: Root Cause Traceability
Root cause traceability (RC-N) is the key differentiator for the bug chain. The individual sub-skills handle RC-N mapping internally — the orchestrator does not need special RC-N logic. Specifically:

- `documenting-bugs` defines RC-N root causes in the requirements document
- `reviewing-requirements` validates RC-N ↔ AC traceability
- `documenting-qa` maps RC-N to test plan entries
- `executing-bug-fixes` addresses each RC-N systematically and verifies reproduction steps
- `executing-qa` confirms reproduction steps fail AND each RC-N is addressed in code

## Non-Functional Requirements

### NFR-1: Sub-Skill Isolation
Sub-skills are NOT modified — no `context: fork` added to their frontmatter. The orchestrator handles all forking decisions. Consistent with FEAT-009 (NFR-3) and FEAT-010 (NFR-1).

### NFR-2: State File Consistency
The bug chain state file uses the same JSON format as feature and chore chain state files. The `type` field is set to `"bug"`. All existing state script commands (`status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`) work without modification.

### NFR-3: Idempotency
Consistent with FEAT-009 and FEAT-010: `init` on an existing workflow returns current state; `advance` on a completed step is a no-op.

## Dependencies

- **FEAT-009** (#89): Shared orchestration infrastructure — state script, Stop hook, Agent-tool forking, resume mechanism
- **FEAT-010** (#90): Chore chain implementation — established the pattern for fixed 9-step chains without phase loops
- Existing sub-skills: `documenting-bugs`, `reviewing-requirements`, `documenting-qa`, `executing-bug-fixes`, `executing-qa`, `finalizing-workflow`
- `gh` CLI for PR status checks
- `jq` for JSON manipulation

## Edge Cases

1. **Bug workflow already exists for ID**: Resume from current state (handled by `init` idempotency)
2. **`executing-bug-fixes` fails before creating PR**: State set to failed at step 5; no PR number recorded; retry restarts `executing-bug-fixes`
3. **`executing-bug-fixes` creates PR but subagent doesn't return PR number**: Orchestrator detects PR via `gh pr list --head {branch} --json number`
4. **User resumes bug at step 6 but PR was closed**: Report PR state, suggest re-opening or restarting from step 5
5. **Branch naming**: `fix/BUG-XXX-description` — handled by `executing-bug-fixes`, not the orchestrator
6. **Commit format**: `fix(category): message` — handled by `executing-bug-fixes`, not the orchestrator
7. **New root causes discovered during execution**: Handled internally by `executing-bug-fixes`, which may update the requirements document; the orchestrator does not need to intervene

## Testing Requirements

### Unit Tests
- `generate_bug_steps` produces correct 9-step sequence
- `init BUG-001 bug` creates valid state file with `type: "bug"`
- All state commands work with bug chain state files
- Chain type detection from `BUG-` prefix

### Integration Tests
- New bug workflow initialization through step 1
- Bug chain progresses through all 9 steps in correct order
- PR-review pause and resume cycle
- Error recovery (failed step → resume → retry)
- Stop hook behavior with in-progress bug chain

### Manual Testing
- Full bug chain end-to-end with a real bug fix
- Resume from PR-review pause point
- Verify `documenting-qa` and `executing-qa` function in main context
- Verify sub-skills work standalone after orchestrator changes
- Verify RC-N traceability maintained through the full chain

## Acceptance Criteria

- [ ] `scripts/workflow-state.sh init BUG-XXX bug` initializes a 9-step bug chain
- [ ] All 9 steps execute in order; steps 2, 4, 5, 7, 9 forked via Agent tool; steps 1, 3, 8 in main
- [ ] Sub-skills are NOT modified — no `context: fork` added to their frontmatter
- [ ] Pauses at PR review (step 6) and resumes correctly; `lastResumedAt` updated on resume
- [ ] State file records `type: "bug"` and bug-specific artifacts
- [ ] RC-N traceability maintained through the full chain (documenting → QA planning → execution → verification)
- [ ] `reviewing-requirements` runs in correct mode at each point (standard → test-plan reconciliation → code-review reconciliation)
- [ ] Stop hook handles bug chain correctly (no plan-approval or phase-loop expectations)
- [ ] `documenting-qa` and `executing-qa` function correctly in main context
- [ ] No plan-approval pause exists in the bug chain
- [ ] No phase loop logic is invoked for bug chains
- [ ] PR number extracted from `executing-bug-fixes` output or detected via `gh pr list`
- [ ] Orchestrator SKILL.md includes bug chain documentation (step sequence, procedures, verification checklist)
