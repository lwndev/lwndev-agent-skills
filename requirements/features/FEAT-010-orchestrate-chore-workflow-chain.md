# Feature Requirements: Orchestrate Chore Workflow Chain

## Overview

Add the chore workflow chain to the `orchestrating-workflows` skill. The chore chain is a 9-step sequence with 1 pause point and no phase loop, building on the shared orchestration infrastructure from FEAT-009.

## Feature ID
`FEAT-010`

## GitHub Issue
[#90](https://github.com/lwndev/lwndev-marketplace/issues/90)

## Priority
High - Extends core orchestration to support chore workflows, the second of three chain types

## User Story

As a developer using the lwndev-sdlc plugin, I want to orchestrate a full chore workflow end-to-end via `/orchestrating-workflows` so that maintenance tasks follow the same automated sequencing as features without requiring manual sub-skill invocations.

## Invocation Syntax

```
/orchestrating-workflows CHORE-007       # Resume existing chore workflow
```

New chore workflows are initiated when the step-1 sub-skill (`documenting-chores`) assigns a `CHORE-` prefixed ID. The orchestrator detects the chain type from the ID prefix.

## Functional Requirements

### FR-1: Chore Chain Step Sequence
Execute the chore chain as a fixed 9-step sequence:

| # | Step | Skill | Context | Expected Artifact |
|---|------|-------|---------|-------------------|
| 1 | Document chore | `documenting-chores` | **main** | `requirements/chores/CHORE-{ID}-*.md` |
| 2 | Review requirements (standard) | `reviewing-requirements` | fork | (edits existing) |
| 3 | Document QA test plan | `documenting-qa` | **main** | `qa/test-plans/QA-plan-CHORE-{ID}.md` |
| 4 | Reconcile test plan | `reviewing-requirements` | fork | (edits existing) |
| 5 | Execute chore | `executing-chores` | fork | Branch + PR created |
| 6 | **PAUSE: PR review** | — | — | Checks `gh pr view` on resume |
| 7 | Reconcile post-review | `reviewing-requirements` | fork | (advisory) |
| 8 | Execute QA | `executing-qa` | **main** | `qa/test-results/QA-results-CHORE-{ID}.md` |
| 9 | Finalize | `finalizing-workflow` | fork | PR merged, on main |

### FR-2: Chore Chain — No Plan-Approval Pause
Unlike the feature chain, the chore chain has no plan-approval pause step. After QA test plan reconciliation (step 4), execution proceeds directly to `executing-chores` (step 5).

### FR-3: Chore Chain — No Phase Loop
The chore chain has no dynamic phase loop. Step 5 (`executing-chores`) is a single invocation that creates the branch, implements the chore, and opens a PR. The `populate-phases` and `phase-count` commands are not used for chore chains.

### FR-4: Chore Chain — PR Extracted from executing-chores
Unlike the feature chain where the orchestrator creates the PR in a dedicated post-phase step, `executing-chores` creates the PR as part of its normal operation. After step 5 completes, the orchestrator must extract the PR number from the `executing-chores` output or detect it from the current branch via `gh pr list --head {branch} --json number`. The PR number is recorded via `scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}`.

### FR-5: Chore Step Sequence in State Script
Add a `generate_chore_steps` function to `scripts/workflow-state.sh` that produces the 9-step sequence. The `init` command must accept `chore` as a valid chain type (currently returns "not yet implemented").

### FR-6: Context Strategy
Three categories of context handling consistent with the feature chain:

- **Main context** (steps 1, 3, 8): Run directly in the orchestrator's conversation. Step 1 may prompt the user interactively. Steps 3 and 8 delegate to `qa-verifier` subagent internally and rely on Stop hooks that don't fire when forked (#92).
- **Forked context** (steps 2, 4, 5, 7, 9): Orchestrator reads the sub-skill's SKILL.md, spawns a subagent via Agent tool, validates artifacts, advances state.
- **Pause point** (step 6): Workflow halts, state persisted, user re-invokes to resume.

### FR-7: PR Review Pause (Step 6)
Same mechanism as the feature chain:

- State records `prNumber`, sets `pauseReason: "pr-review"`
- On resume: calls `scripts/workflow-state.sh resume {ID}` to update `lastResumedAt`, then checks `gh pr view {prNumber} --json state,reviews,mergeStateStatus`
  - Approved/mergeable → advance to step 7
  - Changes requested → report feedback, stay paused
  - Pending → inform user, stay paused

### FR-8: Chore Chain Dispatch in Orchestrator SKILL.md
The orchestrator SKILL.md must include:

1. A chore chain step sequence table
2. Step execution procedures for chore-specific steps (step 1 maps to `documenting-chores`, step 5 maps to `executing-chores`)
3. New workflow procedure for chore chains (when step 1 produces a `CHORE-` ID)
4. Resume procedure that handles chore chain state (no plan-approval pause to handle)

### FR-9: Stop Hook Chore Support
The existing Stop hook must handle chore chain workflows correctly. Since the hook reads state from `.sdlc/workflows/{ID}.json` and checks `status` and `currentStep`, it should work without modification as long as the state file format is consistent.

## Non-Functional Requirements

### NFR-1: Sub-Skill Isolation
Sub-skills are NOT modified — no `context: fork` added to their frontmatter. The orchestrator handles all forking decisions. This is consistent with FEAT-009 (NFR-3).

### NFR-2: State File Consistency
The chore chain state file uses the same JSON format as feature chain state files. The `type` field is set to `"chore"`. All existing state script commands (`status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`) work without modification.

### NFR-3: Idempotency
Consistent with FEAT-009: `init` on an existing workflow returns current state; `advance` on a completed step is a no-op.

## Dependencies

- **FEAT-009** (#89): Shared orchestration infrastructure — state script, Stop hook, Agent-tool forking, resume mechanism
- Existing sub-skills: `documenting-chores`, `reviewing-requirements`, `documenting-qa`, `executing-chores`, `executing-qa`, `finalizing-workflow`
- `gh` CLI for PR status checks
- `jq` for JSON manipulation

## Edge Cases

1. **Chore workflow already exists for ID**: Resume from current state (handled by `init` idempotency)
2. **`executing-chores` fails before creating PR**: State set to failed at step 5; no PR number recorded; retry restarts `executing-chores`
3. **`executing-chores` creates PR but subagent doesn't return PR number**: Orchestrator detects PR via `gh pr list --head {branch} --json number`
4. **User resumes chore at step 6 but PR was closed**: Report PR state, suggest re-opening or restarting from step 5
5. **Branch naming**: `chore/CHORE-XXX-description` — handled by `executing-chores`, not the orchestrator
6. **Commit format**: `chore(category): message` — handled by `executing-chores`, not the orchestrator

## Testing Requirements

### Unit Tests
- `generate_chore_steps` produces correct 9-step sequence
- `init CHORE-001 chore` creates valid state file with `type: "chore"`
- All state commands work with chore chain state files
- Chain type detection from `CHORE-` prefix

### Integration Tests
- New chore workflow initialization through step 1
- Chore chain progresses through all 9 steps in correct order
- PR-review pause and resume cycle
- Error recovery (failed step → resume → retry)
- Stop hook behavior with in-progress chore chain

### Manual Testing
- Full chore chain end-to-end with a real chore task
- Resume from PR-review pause point
- Verify `documenting-qa` and `executing-qa` function in main context
- Verify sub-skills work standalone after orchestrator changes

## Acceptance Criteria

- [ ] `scripts/workflow-state.sh init CHORE-XXX chore` initializes a 9-step chore chain
- [ ] All 9 steps execute in order; steps 2, 4, 5, 7, 9 forked via Agent tool; steps 1, 3, 8 in main
- [ ] Sub-skills are NOT modified — no `context: fork` added to their frontmatter
- [ ] Pauses at PR review (step 6) and resumes correctly; `lastResumedAt` updated on resume
- [ ] State file records `type: "chore"` and chore-specific artifacts
- [ ] `reviewing-requirements` runs in correct mode at each point (standard → test-plan reconciliation → code-review reconciliation)
- [ ] Stop hook handles chore chain correctly (no plan-approval or phase-loop expectations)
- [ ] `documenting-qa` and `executing-qa` function correctly in main context
- [ ] No plan-approval pause exists in the chore chain
- [ ] No phase loop logic is invoked for chore chains
- [ ] PR number extracted from `executing-chores` output or detected via `gh pr list`
- [ ] Orchestrator SKILL.md includes chore chain documentation (step sequence, procedures)
