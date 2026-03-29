---
name: orchestrating-workflows
description: Orchestrate full SDLC workflow chains (feature, chore, bug) end-to-end — sequences sub-skill invocations, manages state across pause points, and isolates per-step context via Agent tool forking. Use when the user says "orchestrate workflow", "run full workflow", "start workflow", or wants to drive a complete feature/chore/bug chain.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
argument-hint: '"feature title" | #issue-number | FEAT-XXX | CHORE-XXX | BUG-XXX'
hooks:
  Stop:
    - hooks:
        - type: command
          command: "scripts/workflow-stop-hook.sh"
---

# Orchestrating Workflows

Drive full SDLC workflow chains end-to-end: feature, chore, or bug. Sequences sub-skill invocations, manages persistent state across pause points, and isolates per-step context via Agent tool forking.

## When to Use

- User says "orchestrate workflow", "run full workflow", or "start workflow"
- User wants to drive a complete feature, chore, or bug chain from requirements through finalization
- User provides a workflow ID to resume a paused or failed workflow

## Arguments

Parse the argument to determine mode:

- **`FEAT-NNN`, `CHORE-NNN`, or `BUG-NNN`** → Resume an existing workflow (see [Resume from State](#resume-from-state))
- **`#N`** (e.g., `#42`) → Start a new workflow from a GitHub issue
- **Free text** (e.g., `"add skill chaining"`) → Start a new workflow with this as the title
- **No argument** → Prompt the user for workflow type and title

### ID Validation

Workflow IDs must match the pattern `{PREFIX}-{NNN}` where PREFIX is `FEAT`, `CHORE`, or `BUG` and NNN is 3+ digits. If the argument looks like an ID but doesn't match (e.g., `feat-009`, `FEAT003`, `TEST-001`), display an error:

```
Invalid workflow ID "{input}". Supported formats: FEAT-NNN, CHORE-NNN, BUG-NNN (e.g., FEAT-003)
```

## Active Workflow Tracking

At the start of every invocation (new or resume), write the workflow ID to `.sdlc/workflows/.active`:

```bash
mkdir -p .sdlc/workflows
echo "{ID}" > .sdlc/workflows/.active
```

This file is read by the Stop hook to determine which workflow to check.

## New Workflow

### Step 1: Determine Chain Type

New workflows default to the **feature** chain. If the user specifies a different type (e.g., "start a chore workflow"), use the appropriate chain:

| User Intent | Chain Type | Step-1 Skill |
|-------------|-----------|--------------|
| Feature (default) | `feature` | `documenting-features` |
| Chore | `chore` | `documenting-chores` |
| Bug | `bug` | `documenting-bugs` |

### Step 2: Execute Step 1 (Main Context)

Run the step-1 sub-skill **directly in the conversation** (not forked). This step is interactive — the sub-skill may prompt the user for details.

- If argument was `#N`: invoke the sub-skill with `#N` as its argument (e.g., `/documenting-features #42`)
- If argument was free text: invoke the sub-skill with the text as its argument
- If no argument: invoke the sub-skill without arguments — it will prompt the user

**After step 1 completes:**

1. Find the generated artifact using Glob:
   - Feature: `requirements/features/FEAT-*` (newest file)
   - Chore: `requirements/chores/CHORE-*` (newest file)
   - Bug: `requirements/bugs/BUG-*` (newest file)
2. Extract the ID from the filename (e.g., `FEAT-009` from `FEAT-009-orchestrating-workflows-skill.md`)
3. Write active workflow tracking: `echo "{ID}" > .sdlc/workflows/.active`
4. Initialize state: `scripts/workflow-state.sh init {ID} {type}`
5. Mark step 1 complete: `scripts/workflow-state.sh advance {ID} {artifact-path}`
6. Continue to the next step

## Forking Mechanism

For steps that run in **forked context**, use the Agent tool to isolate each sub-skill invocation:

1. Read the sub-skill's SKILL.md:
   ```
   Read ${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md
   ```
2. Spawn a general-purpose subagent via the Agent tool:
   - Set the Agent `prompt` to the full SKILL.md content
   - Append the workflow ID as the argument: `\n\nARGUMENTS: {ID}`
   - Set `description` to a short summary (e.g., "Review requirements for FEAT-009")
3. When the subagent returns:
   - Validate the expected artifact exists (use Glob with the pattern from the step definition)
   - If artifact found: `scripts/workflow-state.sh advance {ID} {artifact-path}`
   - If artifact missing or subagent failed: `scripts/workflow-state.sh fail {ID} "Step N ({skill-name}) failed: {error-or-missing-artifact}"`  — then halt

**Why fork:** A 5-phase feature means ~16 skill invocations. Without forking, each loads 3–5K tokens of SKILL.md plus tool outputs — easily 150K+ tokens. Compaction is lossy and would drop critical context. Forking gives each step a clean context window.

## Feature Chain Execution

The feature chain has 6 + N + 5 steps (N = number of implementation phases).

### Pre-Phase Steps (1–6)

**Step 1** — Document requirements: Runs in **main context** (see [New Workflow](#new-workflow) above).

**Step 2** — Review requirements (standard): **Fork** `reviewing-requirements` with ID. Standard review mode is auto-detected (no test plan or PR exists yet). Expected artifact: edits to the existing requirements file.

**Step 3** — Create implementation plan: **Fork** `creating-implementation-plans` with ID. Expected artifact: `requirements/implementation/{ID}-*.md`.

**Step 4** — Pause: Plan approval:
```bash
scripts/workflow-state.sh pause {ID} plan-approval
```
Display to the user:
```
Implementation plan created. Review it at requirements/implementation/{ID}-*.md
Re-invoke /orchestrating-workflows {ID} to continue.
```
**Stop here.** The workflow will resume when the user re-invokes with the ID.

**Step 5** — Document QA test plan: Runs in **main context** (not forked). Invoke the `documenting-qa` skill directly in the conversation with the ID as argument. This skill delegates to the `qa-verifier` subagent internally — subagents cannot nest, so this step must not be forked. Expected artifact: `qa/test-plans/QA-plan-{ID}.md`.

**Step 6** — Reconcile test plan: **Fork** `reviewing-requirements` with ID. Test-plan reconciliation mode is auto-detected (test plan exists, no PR). Expected artifact: edits to existing documents.

### Phase Loop (Steps 7 through 6+N)

1. Determine phase count:
   ```bash
   scripts/workflow-state.sh phase-count {ID}
   ```
   This reads the implementation plan, counts phases, and populates phase steps + post-phase steps in the state file.

2. For each phase 1 through N:
   - Read `implementing-plan-phases` SKILL.md from `${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/SKILL.md`
   - Spawn Agent with the SKILL.md content as prompt, appending:
     ```
     ARGUMENTS: {ID} {phase-number}

     IMPORTANT: Do not create a pull request after this phase. The orchestrator handles PR creation after all phases complete. Skip step 12 (PR creation) entirely.
     ```
   - After the subagent returns, advance state:
     ```bash
     scripts/workflow-state.sh advance {ID}
     ```
   - **If a phase fails:** call `scripts/workflow-state.sh fail {ID} "Phase {N} failed: {error}"` and **halt immediately** — do not proceed to subsequent phases.

### Post-Phase Steps (6+N+1 through 6+N+5)

**Step 6+N+1** — Create PR: **Fork** a subagent that creates a pull request:
```
Create a pull request from the current branch to main for workflow {ID}.
Use: gh pr create --title "feat({scope}): {description}" --body "..."
Include "Closes #{issue-number}" in the body if a GitHub issue is linked.
Report back the PR number and branch name.
```
After the subagent returns with PR number and branch:
```bash
scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
scripts/workflow-state.sh advance {ID}
```

**Step 6+N+2** — Pause: PR review:
```bash
scripts/workflow-state.sh pause {ID} pr-review
```
Display:
```
PR #{pr-number} created. Waiting for review.
Re-invoke /orchestrating-workflows {ID} after the PR has been reviewed.
```
**Stop here.**

**Step 6+N+3** — Reconcile post-review: **Fork** `reviewing-requirements` with ID. Code-review reconciliation mode is auto-detected (PR exists). This step is advisory.

**Step 6+N+4** — Execute QA: Runs in **main context** (not forked). Invoke `executing-qa` directly with the ID. Same reasoning as step 5 — delegates to `qa-verifier` subagent internally.

**Step 6+N+5** — Finalize: **Fork** `finalizing-workflow` with ID.

After step 6+N+5 completes:
```bash
scripts/workflow-state.sh complete {ID}
```
Display: `Workflow {ID} complete.`

## Chore Chain Execution

The chore chain has 9 fixed steps with 1 pause point and no phase loop.

| Step | Skill | Context |
|------|-------|---------|
| 1 | `documenting-chores` | **main** |
| 2 | `reviewing-requirements` | fork |
| 3 | `documenting-qa` | **main** |
| 4 | `reviewing-requirements` | fork |
| 5 | `executing-chores` | fork |
| 6 | Pause: PR review | — |
| 7 | `reviewing-requirements` | fork |
| 8 | `executing-qa` | **main** |
| 9 | `finalizing-workflow` | fork |

Follow the same patterns as the feature chain:
- Steps 1, 3, 8 run in **main context** (same reasons: interactivity, qa-verifier subagent nesting, Stop hooks)
- All other steps are forked via Agent tool
- Step 6 pauses with `pr-review` reason — `executing-chores` creates its own branch and PR
- After step 5, read the PR number from `gh pr list --head "chore/{ID}-*"` and call `set-pr`

## Bug Chain Execution

The bug chain has 9 fixed steps, identical structure to chore but with bug-specific skills.

| Step | Skill | Context |
|------|-------|---------|
| 1 | `documenting-bugs` | **main** |
| 2 | `reviewing-requirements` | fork |
| 3 | `documenting-qa` | **main** |
| 4 | `reviewing-requirements` | fork |
| 5 | `executing-bug-fixes` | fork |
| 6 | Pause: PR review | — |
| 7 | `reviewing-requirements` | fork |
| 8 | `executing-qa` | **main** |
| 9 | `finalizing-workflow` | fork |

Same patterns as the chore chain. After step 5, read PR from `gh pr list --head "fix/{ID}-*"` and call `set-pr`.

## Resume from State

When invoked with an existing workflow ID:

1. Read state:
   ```bash
   scripts/workflow-state.sh status {ID}
   ```
2. Write active tracking: `echo "{ID}" > .sdlc/workflows/.active`

3. Branch based on status:

### Status: `paused`

**`pauseReason: "plan-approval"`:**
- Call `scripts/workflow-state.sh resume {ID}`
- Ask the user: "Ready to proceed with implementation?"
- If yes, continue to step 5 (Document QA test plan)

**`pauseReason: "pr-review"`:**
- Read PR number from state, then check status:
  ```bash
  gh pr view {prNumber} --json state,reviews,mergeStateStatus
  ```
  - **Approved / mergeable** → call `resume {ID}`, continue to the next step after the pause (reconcile post-review)
  - **Changes requested** → display the review feedback, stay paused
  - **Review pending** → inform the user that review is still pending, stay paused

### Status: `failed`

- Call `scripts/workflow-state.sh resume {ID}`
- Display: "Retrying step {currentStep}: {step-name}"
- Re-execute the failed step (use the step's skill/context from the state file)

### Status: `in-progress`

- Continue from `currentStep` — execute that step and all subsequent steps

### Status: `complete`

- Display: "Workflow {ID} is already complete."

## Error Handling

- **Step failure:** Call `scripts/workflow-state.sh fail {ID} "{error}"`, display the error, and halt. The Stop hook will allow stopping.
- **Phase failure:** Halt the phase loop immediately. Do not proceed to subsequent phases or PR creation.
- **Missing artifact after fork:** Call `fail` with a message specifying which artifact was expected and where.
- **State script errors:** Surface the stderr message to the user.
- **Sub-skill SKILL.md not found:** Display: "Skill '{name}' not found at {path}. Is the plugin installed?"

## Step Execution Helper

Use this pattern for each step to maintain consistency:

```
For step {N} of the workflow:
1. Read the step definition from the state (name, skill, context)
2. If context is "main" → run the skill directly in conversation
3. If context is "fork" → use the Forking Mechanism
4. If context is "pause" → call pause and halt
5. After success → call advance
6. After failure → call fail and halt
```

Loop through steps starting from `currentStep` until a pause is reached, an error occurs, or the workflow completes.
