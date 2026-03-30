---
name: orchestrating-workflows
description: Orchestrate full SDLC workflow chains (feature, chore, bug) end-to-end by sequencing sub-skill invocations, managing state across pause points, and isolating per-step context via Agent tool forking.
argument-hint: "<title-or-issue> or <ID>"
compatibility: Requires jq and a bash-compatible shell
hooks:
  Stop:
    - hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/stop-hook.sh"
---

# Orchestrating Workflows

Drive an entire SDLC workflow chain through a single skill invocation. The orchestrator sequences sub-skill calls, manages persistent state across pause points, and isolates per-step context by forking sub-skills into subagents.

## When to Use This Skill

- User wants to run a full feature, chore, or bug workflow end-to-end
- User says "orchestrate workflow", "run full workflow", "start workflow chain"
- User provides a workflow ID to resume a paused or failed workflow

## Arguments

- **When argument is provided**: If the argument matches an existing workflow ID pattern (`FEAT-NNN`, `CHORE-NNN`, `BUG-NNN`), check for an existing state file at `.sdlc/workflows/{ID}.json` and resume if found. A `FEAT-NNN` ID resumes a feature chain; a `CHORE-NNN` ID resumes a chore chain; a `BUG-NNN` ID resumes a bug chain. If the argument is a `#N` GitHub issue reference, start a new feature workflow from that issue. Otherwise, treat the argument as a free-text title and start a new workflow (feature by default; ask the user if ambiguous).
- **When no argument is provided**: Ask the user for a title, GitHub issue reference (`#N`), or existing workflow ID to resume.
- **Chore workflows**: New chore workflows begin when `documenting-chores` (step 1) assigns the `CHORE-NNN` ID. The user may indicate a chore by saying "chore", "maintenance task", or similar.
- **Bug workflows**: New bug workflows begin when `documenting-bugs` (step 1) assigns the `BUG-NNN` ID. The user may indicate a bug by saying "bug", "fix", "defect", "regression", or similar.

## Quick Start

1. Parse argument — determine new workflow vs resume, and chain type (feature, chore, or bug)
2. **New feature workflow**: Run step 1 (`documenting-features`) in main context, read allocated ID, initialize state with `init {ID} feature`
3. **New chore workflow**: Run step 1 (`documenting-chores`) in main context, read allocated ID, initialize state with `init {ID} chore`
4. **New bug workflow**: Run step 1 (`documenting-bugs`) in main context, read allocated ID, initialize state with `init {ID} bug`
5. **Resume**: Load state, handle pause/failure logic, continue from current step
6. Execute steps sequentially using the step execution procedures below
7. **Feature chain**: Pause at plan approval (step 4) and PR review (step 6+N+2)
8. **Chore chain**: Pause at PR review only (step 6) — no plan-approval pause
9. **Bug chain**: Pause at PR review only (step 6) — no plan-approval pause, same as chore chain
10. On completion, mark workflow complete

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

## Chore Chain Step Sequence

The chore chain has a fixed 9 steps with no phase loop and no plan-approval pause:

| # | Step | Skill | Context |
|---|------|-------|---------|
| 1 | Document chore | `documenting-chores` | **main** |
| 2 | Review requirements (standard) | `reviewing-requirements` | fork |
| 3 | Document QA test plan | `documenting-qa` | **main** |
| 4 | Reconcile test plan | `reviewing-requirements` | fork |
| 5 | Execute chore | `executing-chores` | fork |
| 6 | **PAUSE: PR review** | — | pause |
| 7 | Reconcile post-review | `reviewing-requirements` | fork |
| 8 | Execute QA | `executing-qa` | **main** |
| 9 | Finalize | `finalizing-workflow` | fork |

## Bug Chain Step Sequence

The bug chain has a fixed 9 steps with no phase loop and no plan-approval pause, mirroring the chore chain structure with bug-specific skills:

| # | Step | Skill | Context |
|---|------|-------|---------|
| 1 | Document bug | `documenting-bugs` | **main** |
| 2 | Review requirements (standard) | `reviewing-requirements` | fork |
| 3 | Document QA test plan | `documenting-qa` | **main** |
| 4 | Reconcile test plan | `reviewing-requirements` | fork |
| 5 | Execute bug fix | `executing-bug-fixes` | fork |
| 6 | **PAUSE: PR review** | — | pause |
| 7 | Reconcile post-review | `reviewing-requirements` | fork |
| 8 | Execute QA | `executing-qa` | **main** |
| 9 | Finalize | `finalizing-workflow` | fork |

## New Feature Workflow Procedure

When starting a new feature workflow (argument is a title or `#N` issue):

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
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh init {ID} feature
```

Write the active workflow ID:

```bash
echo "{ID}" > .sdlc/workflows/.active
```

### 5. Advance Step 1 and Continue

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "requirements/features/{artifact-filename}"
```

Continue to execute remaining steps starting from step 2.

## New Chore Workflow Procedure

When starting a new chore workflow (argument indicates a chore task):

### 1. Write Active Marker

```bash
mkdir -p .sdlc/workflows
```

### 2. Execute Step 1 — Document Chore (Main Context)

Run `documenting-chores` directly in this conversation (main context). Pass the argument as the chore description. This step may prompt the user interactively for details. Wait for it to complete and produce an artifact at `requirements/chores/CHORE-{ID}-*.md`.

### 3. Read Allocated ID

After step 1 completes, read the allocated ID from the artifact filename. Use Glob to find the newest file:

```
requirements/chores/CHORE-*-*.md
```

Extract the `CHORE-NNN` portion from the filename. This ID is used for all subsequent state operations.

### 4. Initialize State

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh init {ID} chore
```

Write the active workflow ID:

```bash
echo "{ID}" > .sdlc/workflows/.active
```

### 5. Advance Step 1 and Continue

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "requirements/chores/{artifact-filename}"
```

Continue to execute remaining steps starting from step 2.

## New Bug Workflow Procedure

When starting a new bug workflow (argument indicates a bug fix, defect, or regression):

### 1. Write Active Marker

```bash
mkdir -p .sdlc/workflows
```

### 2. Execute Step 1 — Document Bug (Main Context)

Run `documenting-bugs` directly in this conversation (main context). Pass the argument as the bug description. This step may prompt the user interactively for details. Wait for it to complete and produce an artifact at `requirements/bugs/BUG-{ID}-*.md`.

### 3. Read Allocated ID

After step 1 completes, read the allocated ID from the artifact filename. Use Glob to find the newest file:

```
requirements/bugs/BUG-*-*.md
```

Extract the `BUG-NNN` portion from the filename. This ID is used for all subsequent state operations.

### 4. Initialize State

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh init {ID} bug
```

Write the active workflow ID:

```bash
echo "{ID}" > .sdlc/workflows/.active
```

### 5. Advance Step 1 and Continue

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "requirements/bugs/{artifact-filename}"
```

Continue to execute remaining steps starting from step 2.

## Resume Procedure

When the argument matches an existing ID (`FEAT-NNN`, `CHORE-NNN`, `BUG-NNN`):

1. Read state: `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh status {ID}`
2. Write active marker: `echo "{ID}" > .sdlc/workflows/.active`
3. Determine chain type from the state file's `type` field (`feature`, `chore`, or `bug`)
4. Check status:
   - **paused** with `plan-approval` → (Feature chain only; chore and bug chains have no plan-approval pause.) Ask "Ready to proceed with implementation?" If yes, call `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resume {ID}` and advance past the pause step, then continue.
   - **paused** with `pr-review` → Check PR status via `gh pr view {prNumber} --json state,reviews,mergeStateStatus`. If approved/mergeable, call `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resume {ID}`, advance past the pause step, and continue. If changes requested, report the feedback and stay paused. If pending review, inform user and stay paused. If the PR is closed, report the state and suggest re-opening the PR or restarting from the execution step (feature: phase loop; chore: step 5; bug: step 5). (Applies to all chain types: feature, chore, and bug.)
   - **paused** with `review-findings` → The previous `reviewing-requirements` step found unresolved errors. Call `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resume {ID}` and re-run the current `reviewing-requirements` fork step from scratch. If the re-run returns zero errors, advance and continue. If errors persist, surface findings and pause again with `review-findings`.
   - **failed** → Call `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resume {ID}`. Retry the failed step.
   - **in-progress** → Continue from the current step.
5. Use the appropriate step sequence table (Feature Chain, Chore Chain, or Bug Chain) when determining the next step to execute.

## Step Execution

For each step, determine the context from the appropriate step sequence table (Feature Chain, Chore Chain, or Bug Chain) and execute accordingly. The forked step and main-context step patterns are shared across all chains.

### Main-Context Steps

These steps run directly in the orchestrator's conversation because they rely on Stop hooks or interactive prompts that don't work when forked.

#### Feature Chain Main-Context Steps (Steps 1, 5, 6+N+4)

**Step 1 — `documenting-features`**: See New Feature Workflow Procedure above.

**Step 5 — `documenting-qa`**: Read the SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/SKILL.md`. Follow its instructions directly in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-plans/QA-plan-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-plans/QA-plan-{ID}.md"
```

**Step 6+N+4 — `executing-qa`**: Read the SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/SKILL.md`. Follow its instructions directly in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-results/QA-results-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-results/QA-results-{ID}.md"
```

#### Chore Chain Main-Context Steps (Steps 1, 3, 8)

**Step 1 — `documenting-chores`**: See New Chore Workflow Procedure above.

**Step 3 — `documenting-qa`**: Same pattern as feature chain step 5. Read `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/SKILL.md`, follow its instructions in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-plans/QA-plan-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-plans/QA-plan-{ID}.md"
```

**Step 8 — `executing-qa`**: Same pattern as feature chain step 6+N+4. Read `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/SKILL.md`, follow its instructions in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-results/QA-results-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-results/QA-results-{ID}.md"
```

### Forked Steps

For all steps marked **fork** in the step sequence, use the Agent tool to delegate:

1. Read the sub-skill's SKILL.md content:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md
   ```

2. Spawn a general-purpose subagent via the Agent tool. The prompt must include:
   - The full SKILL.md content
   - The work item ID as argument (e.g., `FEAT-003` or `CHORE-001`)
   - Any step-specific instructions (see below)

3. Wait for the subagent to return a summary.

4. Validate the expected artifact exists (use Glob to check). If the artifact is missing, record failure:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh fail {ID} "Step N: expected artifact not found"
   ```

5. On success, advance state:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "{artifact-path}"
   ```

### Reviewing-Requirements Findings Handling

All `reviewing-requirements` fork steps (feature steps 2, 6, 6+N+3; chore steps 2, 4, 7; bug steps 2, 4, 7) require findings handling after the subagent returns. The orchestrator parses the subagent's return text and acts on the findings before advancing.

#### Parsing Findings

After the `reviewing-requirements` subagent returns its summary, parse the summary line for severity counts:

```
Found **N errors**, **N warnings**, **N info**
```

Extract the error, warning, and info counts from this line. If the summary line is not found (e.g., the subagent returned "No issues found"), treat as zero errors, zero warnings, zero info.

#### Decision Flow

Based on the parsed counts, follow this flow:

1. **Zero findings** (zero errors, zero warnings, zero info) → Advance state automatically. No user interaction needed.

2. **Warnings/info only (zero errors)** → Display the full findings to the user. Prompt: "{N} warnings and {N} info found by reviewing-requirements. Review findings above and continue? (yes / no)". If the user confirms, advance state. If the user declines, pause the workflow:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
   ```
   Halt execution. The user re-invokes with `/orchestrating-workflows {ID}` after addressing findings manually.

3. **Errors present** → Display the full findings to the user. List the auto-fixable items from the "Fix Summary" / "Update Summary" section of the findings. Errors always block progression — present two options:
   - **Apply fixes** → The orchestrator applies the auto-fixable corrections in main context using the Edit tool. Then spawn a **new** `reviewing-requirements` subagent fork to re-verify (this is the re-run, max 1). Parse the re-run findings:
     - If zero errors → advance state.
     - If errors persist → display remaining findings and pause:
       ```bash
       ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
       ```
       Halt execution.
   - **Pause for manual resolution** → Pause immediately:
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
     ```
     Halt execution.

#### Applying Auto-Fixes

When the user opts to apply fixes, the orchestrator (not a subagent) applies them:

1. Read the auto-fixable items from the findings (listed under "Auto-fixable" or "Applicable updates" in the subagent's return text)
2. For each fix, use the Edit tool to apply the correction to the target file
3. After all fixes are applied, spawn a new `reviewing-requirements` subagent fork with the same arguments as the original step to re-verify
4. This re-run counts as the single allowed retry — do not apply fixes or re-run again after this

### Feature Chain Step-Specific Fork Instructions

**Step 2 — `reviewing-requirements` (standard review)**: Append `{ID}` as argument. The skill auto-detects standard review mode.

**Step 3 — `creating-implementation-plans`**: Append `{ID}` as argument. Expected artifact: `requirements/implementation/{ID}-*.md`.

**Step 6 — `reviewing-requirements` (test-plan reconciliation)**: Append `{ID}` as argument. The skill auto-detects test-plan reconciliation mode because `qa/test-plans/QA-plan-{ID}.md` exists.

**Steps 7…6+N — `implementing-plan-phases`**: See Phase Loop below.

**Step 6+N+1 — Create PR**: See PR Creation below.

**Step 6+N+3 — `reviewing-requirements` (code-review reconciliation)**: Append `{ID} --pr {prNumber}` as argument. The skill auto-detects code-review reconciliation mode.

**Step 6+N+5 — `finalizing-workflow`**: No special argument needed. The skill merges the current PR and resets to main.

### Chore Chain Step-Specific Fork Instructions

Steps 2, 4, 7, and 9 follow the same fork pattern as the feature chain without chore-specific overrides:

**Step 2 — `reviewing-requirements` (standard review)**: Append `{ID}` as argument. Same as feature chain step 2.

**Step 4 — `reviewing-requirements` (test-plan reconciliation)**: Append `{ID}` as argument. Same as feature chain step 6.

**Step 5 — `executing-chores` (fork)**: Fork via Agent tool with `{ID}` as argument. After the subagent completes:
1. Extract the PR number from the subagent output (the `executing-chores` skill creates a PR as its final step)
2. If the PR number is not in the output, detect it via: `gh pr list --head {branch} --json number --jq '.[0].number'`
3. Record the PR metadata:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

**Step 7 — `reviewing-requirements` (code-review reconciliation)**: Append `{ID} --pr {prNumber}` as argument. Same as feature chain step 6+N+3.

**Step 9 — `finalizing-workflow`**: No special argument needed. Same as feature chain step 6+N+5.

### Bug Chain Main-Context Steps (Steps 1, 3, 8)

**Step 1 — `documenting-bugs`**: See New Bug Workflow Procedure above.

**Step 3 — `documenting-qa`**: Same pattern as chore chain step 3. Read `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/SKILL.md`, follow its instructions in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-plans/QA-plan-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-plans/QA-plan-{ID}.md"
```

**Step 8 — `executing-qa`**: Same pattern as chore chain step 8. Read `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/SKILL.md`, follow its instructions in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-results/QA-results-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-results/QA-results-{ID}.md"
```

### Bug Chain Step-Specific Fork Instructions

Steps 2, 4, 7, and 9 follow the same fork pattern as the chore chain:

**Step 2 — `reviewing-requirements` (standard review)**: Append `{ID}` as argument. Same as chore chain step 2.

**Step 4 — `reviewing-requirements` (test-plan reconciliation)**: Append `{ID}` as argument. Same as chore chain step 4.

**Step 5 — `executing-bug-fixes` (fork)**: Fork via Agent tool with `{ID}` as argument. After the subagent completes:
1. Extract the PR number from the subagent output (the `executing-bug-fixes` skill creates a PR as its final step)
2. If the PR number is not in the output, detect it via: `gh pr list --head {branch} --json number --jq '.[0].number'`
3. Record the PR metadata:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

**Step 7 — `reviewing-requirements` (code-review reconciliation)**: Append `{ID} --pr {prNumber}` as argument. Same as chore chain step 7.

**Step 9 — `finalizing-workflow`**: No special argument needed. Same as chore chain step 9.

### Pause Steps

#### Feature Chain Pause Steps

**Step 4 — Plan Approval** (feature chain only):
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} plan-approval
```
Display: "Implementation plan created at `requirements/implementation/{ID}-*.md`. Review it and re-invoke `/orchestrating-workflows {ID}` to continue."

Halt execution. The user re-invokes the skill to resume.

**Step 6+N+2 — PR Review**:
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} pr-review
```
Display the PR number, link, and branch. Halt execution.

#### Chore Chain Pause Steps

**Step 6 — PR Review** (the only pause in the chore chain):
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} pr-review
```
Display the PR number, link, and branch. Halt execution. The user re-invokes with `/orchestrating-workflows {ID}` to resume after review.

#### Bug Chain Pause Steps

**Step 6 — PR Review** (the only pause in the bug chain):
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} pr-review
```
Display the PR number, link, and branch. Halt execution. The user re-invokes with `/orchestrating-workflows {ID}` to resume after review.

## Phase Loop

After step 6 (test-plan reconciliation) completes:

1. Determine phase count and populate steps:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh phase-count {ID}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh populate-phases {ID} {count}
   ```
   This inserts N phase steps and 5 post-phase steps (Create PR, PR review, Reconcile post-review, Execute QA, Finalize) into the state file after the initial 6 steps.

2. For each phase 1 through N, fork `implementing-plan-phases` with the Agent tool. The prompt must include:
   - The SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/SKILL.md`
   - Argument: `{ID} {phase-number}`
   - **Critical**: Append this instruction to the prompt: "Do NOT create a pull request at the end — the orchestrator handles PR creation separately. Skip Step 12 (Create Pull Request) entirely."

3. After each phase completes, advance state:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

4. If a phase fails, halt the loop immediately:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh fail {ID} "Phase {N} failed: {error-summary}"
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
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

3. Continue to step 6+N+2 (PR review pause).

## Error Handling

- **Step failure**: Call `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh fail {ID} "{error message}"`. Display the error clearly. Halt execution. The user can re-invoke to retry.
- **Phase failure**: Halt the phase loop. Do not proceed to subsequent phases or PR creation. Call `fail` with the phase error.
- **QA failure**: `executing-qa` handles retries internally via its own loop. If ultimately unfixable, the orchestrator records the failure.
- **Sub-skill SKILL.md not found**: Display "Error: Skill '{skill-name}' not found at `${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md`. Check that the lwndev-sdlc plugin is installed." Call `fail`.
- **State file not found on resume**: Display "Error: No workflow state found for {ID}. Start a new workflow with `/orchestrating-workflows \"feature title\"`."

## Verification Checklist

Before marking the workflow complete:

### Common Checks (all chain types)
- [ ] All steps executed in the correct order per the chain's step sequence
- [ ] State file at `.sdlc/workflows/{ID}.json` reflects completion
- [ ] Artifacts exist for all completed steps
- [ ] Sub-skills were NOT modified — no `context: fork` added to their frontmatter
- [ ] Reconciliation steps (reviewing-requirements in test-plan and code-review modes) were not skipped
- [ ] Stop hook prevents premature stopping during in-progress steps

### Feature Chain Checks
- [ ] PR was created only after all phases completed (not per-phase)
- [ ] Plan-approval pause occurred at step 4
- [ ] Phase loop correctly iterated through all N phases

### Chore Chain Checks
- [ ] No plan-approval pause occurred (chore chains skip this)
- [ ] No phase loop was executed (chore chains have a fixed 9-step sequence)
- [ ] PR number was extracted from `executing-chores` output or detected via `gh pr list` fallback
- [ ] `set-pr` was called with the correct PR number and branch after step 5

### Bug Chain Checks
- [ ] No plan-approval pause occurred (bug chains skip this)
- [ ] No phase loop was executed (bug chains have a fixed 9-step sequence)
- [ ] PR number was extracted from `executing-bug-fixes` output or detected via `gh pr list` fallback
- [ ] `set-pr` was called with the correct PR number and branch after step 5
- [ ] RC-N traceability maintained through the chain (delegated to sub-skills)

## Relationship to Other Skills

This skill orchestrates all other skills in the lwndev-sdlc plugin:

```
Feature chain:
documenting-features → reviewing-requirements (standard) → creating-implementation-plans
  → PAUSE → documenting-qa → reviewing-requirements (test-plan)
  → implementing-plan-phases (×N) → Create PR
  → PAUSE → reviewing-requirements (code-review) → executing-qa → finalizing-workflow

Chore chain:
documenting-chores → reviewing-requirements (standard) → documenting-qa
  → reviewing-requirements (test-plan) → executing-chores
  → PAUSE → reviewing-requirements (code-review) → executing-qa → finalizing-workflow

Bug chain:
documenting-bugs → reviewing-requirements (standard) → documenting-qa
  → reviewing-requirements (test-plan) → executing-bug-fixes
  → PAUSE → reviewing-requirements (code-review) → executing-qa → finalizing-workflow
```

### Feature Chain Skills

| Task | Skill |
|------|-------|
| Document feature requirements | `documenting-features` (step 1, main) |
| Review requirements | `reviewing-requirements` (steps 2/6/6+N+3, fork) |
| Create implementation plan | `creating-implementation-plans` (step 3, fork) |
| Document QA test plan | `documenting-qa` (step 5, main) |
| Implement phases | `implementing-plan-phases` (steps 7…6+N, fork) |
| Execute QA verification | `executing-qa` (step 6+N+4, main) |
| Merge and finalize | `finalizing-workflow` (step 6+N+5, fork) |

### Chore Chain Skills

| Task | Skill |
|------|-------|
| Document chore requirements | `documenting-chores` (step 1, main) |
| Review requirements | `reviewing-requirements` (steps 2/4/7, fork) |
| Document QA test plan | `documenting-qa` (step 3, main) |
| Execute chore implementation | `executing-chores` (step 5, fork) |
| Execute QA verification | `executing-qa` (step 8, main) |
| Merge and finalize | `finalizing-workflow` (step 9, fork) |

### Bug Chain Skills

| Task | Skill |
|------|-------|
| Document bug report | `documenting-bugs` (step 1, main) |
| Review requirements | `reviewing-requirements` (steps 2/4/7, fork) |
| Document QA test plan | `documenting-qa` (step 3, main) |
| Execute bug fix | `executing-bug-fixes` (step 5, fork) |
| Execute QA verification | `executing-qa` (step 8, main) |
| Merge and finalize | `finalizing-workflow` (step 9, fork) |
