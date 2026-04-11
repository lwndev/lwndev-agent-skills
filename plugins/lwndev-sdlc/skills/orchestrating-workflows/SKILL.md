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

## Issue Tracking via `managing-work-items`

The orchestrator integrates with issue trackers (GitHub Issues, Jira) through the `managing-work-items` skill. This is additive -- all existing workflow steps remain unchanged; issue tracking invocations are inserted between steps.

### Issue Reference Extraction

At the start of every workflow, after step 1 (documentation) completes and the requirements artifact exists, the orchestrator extracts the issue reference:

1. Invoke `managing-work-items fetch <requirements-artifact-path>` using FR-7 (issue reference extraction from documents)
2. The skill parses the `## GitHub Issue` section of the requirements document for `[#N](URL)` or `[PROJ-123](URL)` patterns
3. Store the extracted reference (e.g., `#42` or `PROJ-123`) as `issueRef` for all subsequent invocations
4. If no issue reference is found, set `issueRef` to empty

### Skip Behavior

When no issue reference is found in the requirements document (`issueRef` is empty), **all `managing-work-items` invocations are skipped** with an info-level message: "No issue reference found in requirements document -- skipping issue tracking." The workflow continues normally without any issue tracker operations.

### Invocation Pattern

All `managing-work-items` calls follow the same syntax (see `managing-work-items/SKILL.md` for full operation details):

```
managing-work-items <operation> <issueRef> [--type <comment-type>] [--context <json>]
```

- **fetch**: Retrieve issue data to pre-fill requirements
- **comment**: Post a status update to the linked issue
- **FR-6 (PR link)**: Generate `Closes #N` or `PROJ-123` for PR bodies

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

### 3. Read Allocated ID and Extract Issue Reference

After step 1 completes, read the allocated ID from the artifact filename. The `documenting-features` skill assigns the next sequential ID by scanning existing files. Use Glob to find the newest file:

```
requirements/features/FEAT-*-*.md
```

Extract the `FEAT-NNN` portion from the filename. This ID is used for all subsequent state operations.

**Extract issue reference**: If the argument was a `#N` issue reference, invoke `managing-work-items fetch <issueRef>` to retrieve issue data (this was already used by `documenting-features` to pre-fill requirements via delegation). Use FR-7 to extract the issue reference from the requirements artifact and store it as `issueRef` for all subsequent `managing-work-items` invocations. If no issue reference is found, skip all future `managing-work-items` calls (see Skip Behavior above).

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

### 3. Read Allocated ID and Extract Issue Reference

After step 1 completes, read the allocated ID from the artifact filename. Use Glob to find the newest file:

```
requirements/chores/CHORE-*-*.md
```

Extract the `CHORE-NNN` portion from the filename. This ID is used for all subsequent state operations.

**Extract issue reference**: Use FR-7 from `managing-work-items` to extract the issue reference from the requirements artifact. Store it as `issueRef` for all subsequent `managing-work-items` invocations. If no issue reference is found, skip all future `managing-work-items` calls (see Skip Behavior above).

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

### 3. Read Allocated ID and Extract Issue Reference

After step 1 completes, read the allocated ID from the artifact filename. Use Glob to find the newest file:

```
requirements/bugs/BUG-*-*.md
```

Extract the `BUG-NNN` portion from the filename. This ID is used for all subsequent state operations.

**Extract issue reference**: Use FR-7 from `managing-work-items` to extract the issue reference from the requirements artifact. Store it as `issueRef` for all subsequent `managing-work-items` invocations. If no issue reference is found, skip all future `managing-work-items` calls (see Skip Behavior above).

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

**Step 5 — `executing-chores` (fork)**:

Before forking (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type work-start --context '{"workItemId": "{ID}"}'`

Fork via Agent tool with `{ID}` as argument. If `issueRef` is set, include the FR-6 issue link instruction in the subagent prompt: "Include `Closes #N` (or `PROJ-123` for Jira) in the PR body." After the subagent completes:
1. Extract the PR number from the subagent output (the `executing-chores` skill creates a PR as its final step)
2. If the PR number is not in the output, detect it via: `gh pr list --head {branch} --json number --jq '.[0].number'`
3. Record the PR metadata:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

After step 5 completes (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type work-complete --context '{"workItemId": "{ID}", "prNumber": <pr-number>}'`

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

**Step 5 — `executing-bug-fixes` (fork)**:

Before forking (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type bug-start --context '{"workItemId": "{ID}"}'`

Fork via Agent tool with `{ID}` as argument. If `issueRef` is set, include the FR-6 issue link instruction in the subagent prompt: "Include `Closes #N` (or `PROJ-123` for Jira) in the PR body." After the subagent completes:
1. Extract the PR number from the subagent output (the `executing-bug-fixes` skill creates a PR as its final step)
2. If the PR number is not in the output, detect it via: `gh pr list --head {branch} --json number --jq '.[0].number'`
3. Record the PR metadata:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

After step 5 completes (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type bug-complete --context '{"workItemId": "{ID}", "prNumber": <pr-number>}'`

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

2. For each phase 1 through N:

   **a. Before the phase** (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type phase-start --context '{"phase": <phase-number>, "totalPhases": <N>, "workItemId": "{ID}"}'`

   **b. Fork `implementing-plan-phases`** with the Agent tool. The prompt must include:
   - The SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/SKILL.md`
   - Argument: `{ID} {phase-number}`
   - **Critical**: Append this instruction to the prompt: "Do NOT create a pull request at the end — the orchestrator handles PR creation separately. Skip Step 12 (Create Pull Request) entirely."

   **c. After the phase completes** (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type phase-completion --context '{"phase": <phase-number>, "totalPhases": <N>, "workItemId": "{ID}"}'`

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
   - If `issueRef` is set, use `managing-work-items` FR-6 to generate the issue link for the PR body: `Closes #N` for GitHub issues or `PROJ-123` for Jira issues. Include this link in the PR body
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

## Model Selection — Algorithm Reference (Phase 2 prose)

> **Phase-5 move note**: This section is documented here temporarily. Phase 5 will relocate it to its final position between "Step Execution" and "Error Handling" alongside the full "Model Selection" section (step baseline matrix, complexity signal matrix, worked examples). The algorithm prose itself is the Phase 2 deliverable and is not yet wired into the fork call sites — Phase 3 handles the wiring.

This section documents the classification algorithm the orchestrator runs at workflow init, after step 3 (feature chains only), and before every fork invocation. The shell implementation lives in `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` as the `classify-init`, `classify-post-plan`, and `resolve-tier` subcommands; the prose below is the canonical reference and the shell implementation mirrors it verbatim.

### Tier Ordering

Tiers are ordered `haiku < sonnet < opus`. The `max` tier helper compares two tier strings and returns whichever is higher in this ordering. Unknown tier values are treated as less-than-known so a recognised value always wins against an unrecognised one.

```
max("haiku", "sonnet") → "sonnet"
max("sonnet", "opus")  → "opus"
max("haiku", "opus")   → "opus"
max("sonnet", "haiku") → "sonnet"
```

The same ordering applies to the complexity labels `low < medium < high`, which map to tiers via `low → haiku`, `medium → sonnet`, `high → opus`.

### Work-Item Signal Extractors

At workflow init (FR-2a) and, for feature chains, after step 3 completes (FR-2b), the orchestrator parses the requirement document (and optionally the implementation plan) to compute a work-item complexity label. Parsing is strictly local: no network calls, no LLM invocations, just markdown regex and section walking.

#### Chore signal extractor

```
read the requirement document at requirements/chores/{ID}-*.md
locate the `## Acceptance Criteria` heading
count list items matching `- [ ]` or `- [x]` until the next `## ` heading or EOF
→ ≤3 items     → low
→ 4–8 items    → medium
→ 9+ items     → high
→ heading absent → unparseable → FR-10 fallback → medium
```

Only the acceptance criteria count is used. Chore docs do not enforce a parseable file-list schema, so "affected files count" is intentionally not a signal (E2 fix in the requirement doc).

#### Bug signal extractor

```
read the requirement document at requirements/bugs/{ID}-*.md

severity_tier:
  read the first non-empty line under `## Severity`, strip backticks, lowercase
  → "low"               → low
  → "medium"            → medium
  → "high" or "critical" → high
  → anything else        → unset

rc_count_tier:
  count numbered list items (`1.`, `2.`, …) under `## Root Cause(s)`
  if the heading is absent, fall back to counting distinct `RC-N` mentions in the whole doc
  → 1 item   → low
  → 2–3 items → medium
  → 4+ items → high
  → 0 items   → unset

if severity_tier is unset and rc_count_tier is unset:
  → unparseable → FR-10 fallback → medium
else:
  base = max(severity_tier, rc_count_tier)   # unknown sides are ignored

category:
  read the first non-empty line under `## Category`, strip backticks, lowercase
  if category in {"security", "performance"}:
    base = bump_one_tier(base)                # low→medium, medium→high, high→high

return base
```

#### Feature init-stage signal extractor (FR-2a)

```
read the requirement document at requirements/features/{ID}-*.md

fr_count:
  locate the `## Functional Requirements` heading
  count `### FR-N:` sub-headings until the next `## ` heading or EOF
  SKIP any heading line whose text contains the literal "removed" (case-insensitive)
  → ≤5 items   → low
  → 6–12 items → medium
  → 13+ items  → high

nfr_bump:
  locate the `## Non-Functional Requirements` heading
  scan the section body (case-insensitive) for the substrings
    "security", "auth", "perf"
  → any match  → true
  → no match   → false
  → section absent → unset

if fr_count is unset and nfr_bump is unset:
  → unparseable → FR-10 fallback → medium

base = fr_count (or medium if fr_count is unset)
if nfr_bump == true:
  base = bump_one_tier(base)
return base
```

#### Feature post-plan signal extractor (FR-2b)

This stage runs exactly once in a feature chain, after step 3 (`creating-implementation-plans`) completes and before any subsequent fork resolves its tier. It is **upgrade-only**: it can never downgrade the tier computed at init.

```
read the implementation plan at requirements/implementation/{ID}-*.md
count `### Phase N:` headings
→ 1 phase   → low
→ 2–3 phases → medium
→ 4+ phases → high
→ plan absent or 0 phases → NFR-5: retain persisted init-stage tier, log warning, do not upgrade

new_tier = max(persisted_complexity, phase_count_tier)   # upgrade-only
if new_tier != persisted_complexity:
  persist new_tier, set complexityStage = "post-plan", emit one-line upgrade log
else:
  proceed silently with persisted tier
```

Chore and bug chains have no post-plan stage — all their signals are init-stage.

### FR-10 Unparseable-Signal Fallback

When a signal extractor cannot produce a value (missing section, zero matches, empty document, missing file), the classifier falls back to the complexity label `medium`, which maps to the `sonnet` tier. It **never** falls back to `opus` — silently reintroducing over-provisioning is exactly the behavior FEAT-014 exists to prevent.

Edge Case 5 (empty requirement document): the classifier returns `medium` unconditionally. Edge Case 9 (chore with only a title and no Acceptance Criteria section): same.

### FR-3 Override Precedence Chain (`resolve-tier`)

The orchestrator runs this algorithm fresh before every `Agent` tool fork call. The FR-5 precedence order is mirrored below verbatim. Hard overrides replace the tier entirely (and may downgrade below baseline); soft overrides are upgrade-only and respect baseline locks.

```
# Inputs:
#   step_name           — name of the step being forked (e.g. "reviewing-requirements")
#   cli_model           — --model flag from CLI (hard, blanket)
#   cli_complexity      — --complexity flag from CLI (soft, blanket)
#   cli_model_for       — --model-for flag from CLI (hard, per-step)
#   state_complexity    — persisted .complexity (low/medium/high) from state file
#   state_model_override — persisted .modelOverride from state file (soft)

baseline        = step_baseline(step_name)                 # Axis 1, sonnet or haiku
locked          = step_baseline_locked(step_name)          # true for finalizing-workflow, pr-creation

# Step 1: start at baseline
tier = baseline

# Step 2: apply work-item complexity axis (skipped for baseline-locked steps)
if not locked:
    wi_tier = complexity_to_tier(state_complexity)         # low→haiku, medium→sonnet, high→opus
    if wi_tier is not None:
        tier = max(tier, wi_tier)

# Step 3: walk the override chain in FR-5 precedence order.
# The FIRST non-null entry wins — break out of the loop on match.
chain = [
    (cli_model_for.get(step_name),           "hard"),   # FR-5 #1 (per-step replace)
    (cli_model,                              "hard"),   # FR-5 #2 (blanket replace)
    (cli_complexity,                         "soft"),   # FR-5 #3 (upgrade-only max)
    (state_model_override,                   "soft"),   # FR-5 #4 (upgrade-only max)
]

for (value, kind) in chain:
    if value is None:
        continue
    if kind == "hard":
        # Hard override: replace tier entirely. May downgrade below baseline.
        # May bypass baseline lock (finalizing-workflow on --model opus is legal).
        tier = value
    else:
        # Soft override: upgrade-only. Respects baseline lock.
        if locked:
            pass   # baseline-locked steps reject soft overrides
        else:
            soft_tier = value
            if soft_tier is a complexity label (low/medium/high):
                soft_tier = complexity_to_tier(soft_tier)
            tier = max(tier, soft_tier)
    break   # first non-null wins

return tier
```

### Hard vs Soft Override Rules

| Rule | Hard overrides (`--model`, `--model-for`) | Soft overrides (`--complexity`, `modelOverride`) |
|------|-------------------------------------------|-------------------------------------------------|
| Replace vs upgrade | Replace the tier entirely | `max(current, override)` — upgrade-only |
| Baseline lock | Bypass the lock (can push baseline-locked steps off their baseline) | Respect the lock (baseline-locked steps ignore soft overrides) |
| Can downgrade below baseline? | Yes, with a one-line warning (Edge Case 11) | No — never downgrades below baseline |
| Per-step vs blanket | Both forms supported (`--model-for` per-step beats `--model` blanket) | Blanket only |

Concrete examples:

- `--model haiku` on a default feature chain forces `reviewing-requirements` to `haiku`, even though the baseline is `sonnet`. Emit the Edge Case 11 baseline-bypass warning.
- `--model opus` on any chain forces `finalizing-workflow` to `opus`, even though it is baseline-locked at `haiku`. Hard overrides bypass locks.
- `--complexity low` on a work item already classified `high` has no effect because `max(opus, haiku) = opus`. Soft overrides are strictly upgrade-only.
- `modelOverride: "opus"` in state on `finalizing-workflow` is ignored because `finalizing-workflow` is baseline-locked and soft overrides respect the lock.
- `--model-for reviewing-requirements:opus --model haiku` resolves to `opus` for `reviewing-requirements` (per-step hard beats blanket hard, FR-5 #1 > #2) and `haiku` for every other fork (blanket hard wins there).

### Baseline Floor (FR-10)

Step baselines are a floor for computed and soft-overridden tiers. Even when work-item complexity is `low` (would map to `haiku`), a step whose baseline is `sonnet` still runs on `sonnet`. This protects validation and edit work from quality regression on trivial inputs. Hard overrides are the only path that can push below the floor, and they do so with a visible warning.

### Signal Extractor Implementation Cross-Reference

| Algorithm step | Shell helper | File / line |
|----------------|--------------|-------------|
| Chore AC count | `_count_acceptance_criteria` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| Bug severity | `_extract_severity` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| Bug category | `_extract_category` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| Bug RC count | `_count_root_causes` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| Feature FR count | `_count_functional_requirements` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| Feature NFR bump check | `_check_security_auth_perf` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| Feature phase count | `_count_phases` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| Chore classifier | `_classify_chore` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| Bug classifier | `_classify_bug` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| Feature init classifier | `_classify_feature_init` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| Feature post-plan classifier | `_classify_feature_post_plan` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| `classify-init` subcommand | `cmd_classify_init` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| `classify-post-plan` subcommand | `cmd_classify_post_plan` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |
| `resolve-tier` subcommand (FR-3 walker) | `cmd_resolve_tier` | `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` |

Test fixtures for every bucket boundary and every override precedence level live under `scripts/__tests__/fixtures/feat-014/`. Unit tests in `scripts/__tests__/workflow-state.test.ts` (the `classifier (FEAT-014 Phase 2)` describe block) cover chore/bug/feature signal extraction, the two-stage feature upgrade path, baseline-lock interactions for hard and soft overrides, the FR-10 unparseable-signal fallback, and every precedence level in the FR-3 chain.

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

### Managing Work Items Checks
- [ ] Issue reference extracted from requirements document at workflow start (FR-7)
- [ ] `phase-start` comment posted before each implementation phase (feature chain)
- [ ] `phase-completion` comment posted after each implementation phase (feature chain)
- [ ] `work-start` comment posted before executing-chores (chore chain)
- [ ] `work-complete` comment posted after executing-chores (chore chain)
- [ ] `bug-start` comment posted before executing-bug-fixes (bug chain)
- [ ] `bug-complete` comment posted after executing-bug-fixes (bug chain)
- [ ] PR body includes issue link via FR-6 (`Closes #N` or `PROJ-123`)
- [ ] All `managing-work-items` invocations gracefully skipped when no issue reference found

## Relationship to Other Skills

This skill orchestrates all other skills in the lwndev-sdlc plugin:

```
Feature chain:
documenting-features → [managing-work-items: extract issueRef]
  → reviewing-requirements (standard) → creating-implementation-plans
  → PAUSE → documenting-qa → reviewing-requirements (test-plan)
  → [managing-work-items: phase-start] → implementing-plan-phases (×N) → [managing-work-items: phase-completion]
  → Create PR [managing-work-items: FR-6 issue link]
  → PAUSE → reviewing-requirements (code-review) → executing-qa → finalizing-workflow

Chore chain:
documenting-chores → [managing-work-items: extract issueRef]
  → reviewing-requirements (standard) → documenting-qa
  → reviewing-requirements (test-plan)
  → [managing-work-items: work-start] → executing-chores [managing-work-items: FR-6 issue link] → [managing-work-items: work-complete]
  → PAUSE → reviewing-requirements (code-review) → executing-qa → finalizing-workflow

Bug chain:
documenting-bugs → [managing-work-items: extract issueRef]
  → reviewing-requirements (standard) → documenting-qa
  → reviewing-requirements (test-plan)
  → [managing-work-items: bug-start] → executing-bug-fixes [managing-work-items: FR-6 issue link] → [managing-work-items: bug-complete]
  → PAUSE → reviewing-requirements (code-review) → executing-qa → finalizing-workflow
```

### Feature Chain Skills

| Task | Skill |
|------|-------|
| Document feature requirements | `documenting-features` (step 1, main) |
| Issue tracking (fetch, comments, PR link) | `managing-work-items` (after step 1, before/after phases, at PR creation) |
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
| Issue tracking (comments, PR link) | `managing-work-items` (after step 1, before/after step 5) |
| Review requirements | `reviewing-requirements` (steps 2/4/7, fork) |
| Document QA test plan | `documenting-qa` (step 3, main) |
| Execute chore implementation | `executing-chores` (step 5, fork) |
| Execute QA verification | `executing-qa` (step 8, main) |
| Merge and finalize | `finalizing-workflow` (step 9, fork) |

### Bug Chain Skills

| Task | Skill |
|------|-------|
| Document bug report | `documenting-bugs` (step 1, main) |
| Issue tracking (comments, PR link) | `managing-work-items` (after step 1, before/after step 5) |
| Review requirements | `reviewing-requirements` (steps 2/4/7, fork) |
| Document QA test plan | `documenting-qa` (step 3, main) |
| Execute bug fix | `executing-bug-fixes` (step 5, fork) |
| Execute QA verification | `executing-qa` (step 8, main) |
| Merge and finalize | `finalizing-workflow` (step 9, fork) |
