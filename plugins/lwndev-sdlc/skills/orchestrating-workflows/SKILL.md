---
name: orchestrating-workflows
description: Orchestrate full SDLC workflow chains (feature, chore, bug) end-to-end by sequencing sub-skill invocations, managing state across pause points, and isolating per-step context via Agent tool forking.
argument-hint: "<title-or-issue> or <ID>"
compatibility: Requires jq and a bash-compatible shell
hooks:
  Stop:
    - hooks:
        - type: command
          command: scripts/stop-hook.sh
---

# Orchestrating Workflows

Drive an entire SDLC workflow chain through a single skill invocation. The orchestrator sequences sub-skill calls, manages persistent state across pause points, and isolates per-step context by forking sub-skills into subagents.

## When to Use This Skill

- User wants to run a full feature, chore, or bug workflow end-to-end
- User says "orchestrate workflow", "run full workflow", "start workflow chain"
- User provides a workflow ID to resume a paused or failed workflow

## Arguments

- **When argument is provided**: If the argument matches an existing workflow ID pattern (`FEAT-NNN`, `CHORE-NNN`, `BUG-NNN`), check for an existing state file at `.sdlc/workflows/{ID}.json` and resume if found. If the argument is a `#N` GitHub issue reference, start a new feature workflow from that issue. Otherwise, treat the argument as a free-text feature title and start a new feature workflow.
- **When no argument is provided**: Ask the user for a feature title, GitHub issue reference (`#N`), or existing workflow ID to resume.

## Quick Start

1. Parse argument — determine new workflow vs resume
2. **New workflow**: Run step 1 in main context, read allocated ID, initialize state
3. **Resume**: Load state, handle pause/failure logic, continue from current step
4. Execute steps sequentially using the step execution procedures below
5. Pause at plan approval (step 4) and PR review (step 6+N+2)
6. On completion, mark workflow complete

## Feature Chain Step Sequence

The feature chain has 6 + N + 5 steps where N = number of implementation phases:

| # | Step | Skill | Context |
|---|------|-------|---------|
| 1 | Document requirements | `documenting-features` | **main** |
| 2 | Review requirements (standard) | `reviewing-requirements` | fork |
| 3 | Create implementation plan | `creating-implementation-plans` | fork |
| 4 | **PAUSE: Plan approval** | — | pause |
| 5 | Document QA test plan | `documenting-qa` | **main** |
| 6 | Reconcile test plan | `reviewing-requirements` | fork |
| 7…6+N | Implement phases 1…N | `implementing-plan-phases` | fork |
| 6+N+1 | Create PR | orchestrator | fork |
| 6+N+2 | **PAUSE: PR review** | — | pause |
| 6+N+3 | Reconcile post-review | `reviewing-requirements` | fork |
| 6+N+4 | Execute QA | `executing-qa` | **main** |
| 6+N+5 | Finalize | `finalizing-workflow` | fork |

## New Workflow Procedure

When starting a new workflow (argument is a title or `#N` issue):

### 1. Write Active Marker

```bash
mkdir -p .sdlc/workflows
```

### 2. Execute Step 1 — Document Requirements (Main Context)

Run `documenting-features` directly in this conversation (main context). If the argument is a `#N` issue reference, pass it through. If it's a free-text title, pass it as the feature name.

This step may prompt the user interactively for details. Wait for it to complete and produce an artifact at `requirements/features/FEAT-{ID}-*.md`.

### 3. Read Allocated ID

After step 1 completes, read the allocated ID from the artifact filename. The `documenting-features` skill assigns the next sequential ID by scanning existing files. Use Glob to find the newest file:

```
requirements/features/FEAT-*-*.md
```

Extract the `FEAT-NNN` portion from the filename. This ID is used for all subsequent state operations.

### 4. Initialize State

```bash
scripts/workflow-state.sh init {ID} feature
```

Write the active workflow ID:

```bash
echo "{ID}" > .sdlc/workflows/.active
```

### 5. Advance Step 1 and Continue

```bash
scripts/workflow-state.sh advance {ID} "requirements/features/{artifact-filename}"
```

Continue to execute remaining steps starting from step 2.

## Resume Procedure

When the argument matches an existing ID (`FEAT-NNN`, `CHORE-NNN`, `BUG-NNN`):

1. Read state: `scripts/workflow-state.sh status {ID}`
2. Write active marker: `echo "{ID}" > .sdlc/workflows/.active`
3. Check status:
   - **paused** with `plan-approval` → Ask "Ready to proceed with implementation?" If yes, call `scripts/workflow-state.sh resume {ID}` and advance past the pause step, then continue.
   - **paused** with `pr-review` → Check PR status via `gh pr view {prNumber} --json state,reviews,mergeStateStatus`. If approved/mergeable, call `scripts/workflow-state.sh resume {ID}`, advance past the pause step, and continue. If changes requested, report the feedback and stay paused. If pending review, inform user and stay paused.
   - **failed** → Call `scripts/workflow-state.sh resume {ID}`. Retry the failed step.
   - **in-progress** → Continue from the current step.

## Step Execution

For each step, determine the context from the step sequence table and execute accordingly.

### Main-Context Steps (Steps 1, 5, 6+N+4)

These steps run directly in the orchestrator's conversation because they rely on Stop hooks or interactive prompts that don't work when forked.

**Step 1 — `documenting-features`**: See New Workflow Procedure above.

**Step 5 — `documenting-qa`**: Read the SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/SKILL.md`. Follow its instructions directly in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-plans/QA-plan-{ID}.md`. On completion:

```bash
scripts/workflow-state.sh advance {ID} "qa/test-plans/QA-plan-{ID}.md"
```

**Step 6+N+4 — `executing-qa`**: Read the SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/SKILL.md`. Follow its instructions directly in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-results/QA-results-{ID}.md`. On completion:

```bash
scripts/workflow-state.sh advance {ID} "qa/test-results/QA-results-{ID}.md"
```

### Forked Steps

For all steps marked **fork** in the step sequence, use the Agent tool to delegate:

1. Read the sub-skill's SKILL.md content:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md
   ```

2. Spawn a general-purpose subagent via the Agent tool. The prompt must include:
   - The full SKILL.md content
   - The work item ID as argument (e.g., `FEAT-003`)
   - Any step-specific instructions (see below)

3. Wait for the subagent to return a summary.

4. Validate the expected artifact exists (use Glob to check). If the artifact is missing, record failure:
   ```bash
   scripts/workflow-state.sh fail {ID} "Step N: expected artifact not found"
   ```

5. On success, advance state:
   ```bash
   scripts/workflow-state.sh advance {ID} "{artifact-path}"
   ```

### Step-Specific Fork Instructions

**Step 2 — `reviewing-requirements` (standard review)**: Append `{ID}` as argument. The skill auto-detects standard review mode.

**Step 3 — `creating-implementation-plans`**: Append `{ID}` as argument. Expected artifact: `requirements/implementation/{ID}-*.md`.

**Step 6 — `reviewing-requirements` (test-plan reconciliation)**: Append `{ID}` as argument. The skill auto-detects test-plan reconciliation mode because `qa/test-plans/QA-plan-{ID}.md` exists.

**Steps 7…6+N — `implementing-plan-phases`**: See Phase Loop below.

**Step 6+N+1 — Create PR**: See PR Creation below.

**Step 6+N+3 — `reviewing-requirements` (code-review reconciliation)**: Append `{ID} --pr {prNumber}` as argument. The skill auto-detects code-review reconciliation mode.

**Step 6+N+5 — `finalizing-workflow`**: No special argument needed. The skill merges the current PR and resets to main.

### Pause Steps

**Step 4 — Plan Approval**:
```bash
scripts/workflow-state.sh advance {ID}
scripts/workflow-state.sh pause {ID} plan-approval
```
Display: "Implementation plan created at `requirements/implementation/{ID}-*.md`. Review it and re-invoke `/orchestrating-workflows {ID}` to continue."

Halt execution. The user re-invokes the skill to resume.

**Step 6+N+2 — PR Review**:
```bash
scripts/workflow-state.sh advance {ID}
scripts/workflow-state.sh pause {ID} pr-review
```
Display the PR number, link, and branch. Halt execution.

## Phase Loop

After step 6 (test-plan reconciliation) completes:

1. Determine phase count and populate steps:
   ```bash
   scripts/workflow-state.sh phase-count {ID}
   scripts/workflow-state.sh populate-phases {ID} {count}
   ```
   This inserts N phase steps and 5 post-phase steps (Create PR, PR review, Reconcile post-review, Execute QA, Finalize) into the state file after the initial 6 steps.

2. For each phase 1 through N, fork `implementing-plan-phases` with the Agent tool. The prompt must include:
   - The SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/SKILL.md`
   - Argument: `{ID} {phase-number}`
   - **Critical**: Append this instruction to the prompt: "Do NOT create a pull request at the end — the orchestrator handles PR creation separately. Skip Step 12 (Create Pull Request) entirely."

3. After each phase completes, advance state:
   ```bash
   scripts/workflow-state.sh advance {ID}
   ```

4. If a phase fails, halt the loop immediately:
   ```bash
   scripts/workflow-state.sh fail {ID} "Phase {N} failed: {error-summary}"
   ```
   Do not proceed to subsequent phases or PR creation.

5. After the final phase completes, continue to step 6+N+1 (PR creation).

## PR Creation

After all phases complete (step 6+N+1):

1. Fork a subagent to create the PR. The prompt should instruct:
   - Create a pull request from the current feature branch to main
   - Include `Closes #N` in the body if a GitHub issue is linked (read it from the requirements document)
   - Return the PR number and branch name

2. Record PR metadata:
   ```bash
   scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   scripts/workflow-state.sh advance {ID}
   ```

3. Continue to step 6+N+2 (PR review pause).

## Error Handling

- **Step failure**: Call `scripts/workflow-state.sh fail {ID} "{error message}"`. Display the error clearly. Halt execution. The user can re-invoke to retry.
- **Phase failure**: Halt the phase loop. Do not proceed to subsequent phases or PR creation. Call `fail` with the phase error.
- **QA failure**: `executing-qa` handles retries internally via its own loop. If ultimately unfixable, the orchestrator records the failure.
- **Sub-skill SKILL.md not found**: Display "Error: Skill '{skill-name}' not found at `${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md`. Check that the lwndev-sdlc plugin is installed." Call `fail`.
- **State file not found on resume**: Display "Error: No workflow state found for {ID}. Start a new workflow with `/orchestrating-workflows \"feature title\"`."

## Verification Checklist

Before marking the workflow complete:

- [ ] All steps executed in the correct order per the feature chain sequence
- [ ] State file at `.sdlc/workflows/{ID}.json` reflects completion
- [ ] Artifacts exist for all completed steps
- [ ] Sub-skills were NOT modified — no `context: fork` added to their frontmatter
- [ ] Reconciliation steps (reviewing-requirements in test-plan and code-review modes) were not skipped
- [ ] PR was created only after all phases completed (not per-phase)
- [ ] Stop hook prevents premature stopping during in-progress steps

## Relationship to Other Skills

This skill orchestrates all other skills in the lwndev-sdlc plugin:

```
Feature chain:
documenting-features → reviewing-requirements (standard) → creating-implementation-plans
  → PAUSE → documenting-qa → reviewing-requirements (test-plan)
  → implementing-plan-phases (×N) → Create PR
  → PAUSE → reviewing-requirements (code-review) → executing-qa → finalizing-workflow
```

| Task | Skill |
|------|-------|
| Document feature requirements | `documenting-features` (step 1, main) |
| Review requirements | `reviewing-requirements` (steps 2/6/6+N+3, fork) |
| Create implementation plan | `creating-implementation-plans` (step 3, fork) |
| Document QA test plan | `documenting-qa` (step 5, main) |
| Implement phases | `implementing-plan-phases` (steps 7…6+N, fork) |
| Execute QA verification | `executing-qa` (step 6+N+4, main) |
| Merge and finalize | `finalizing-workflow` (step 6+N+5, fork) |
