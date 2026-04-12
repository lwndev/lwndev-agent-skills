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

### Model-Selection Flags (FEAT-014 FR-8)

Three additive, positional-independent flags tune per-workflow model selection. They may appear before or after the ID / `#N` / title argument and do not change the existing argument shapes.

- `--model <tier>` — **hard blanket** override. Replaces every non-locked fork's tier with `<tier>` (`haiku`, `sonnet`, or `opus`). May downgrade below baseline; the orchestrator emits a one-line baseline-bypass warning when it does (Edge Case 11). Baseline-locked forks are still pushed by a hard override.
- `--complexity <tier>` — **soft blanket** override. Treated as a `low|medium|high` (or equivalent tier string) floor for work-item complexity. Upgrade-only; respects baseline locks.
- `--model-for <step>:<tier>` — **hard per-step** override. Replaces the tier for a single named step (e.g. `--model-for reviewing-requirements:opus`). Per-step hard beats blanket hard (FR-5 #1 > #2). May be repeated for multiple steps.

Parsing rules: strip each recognised flag and its argument from the argv list before interpreting the remaining positional token as the ID / `#N` / title. Unknown flags are a usage error. Pass the surviving flag values into every `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resolve-tier` call so the FR-3 chain sees them.

## Issue Tracking via `managing-work-items`

The orchestrator integrates with issue trackers (GitHub Issues, Jira) through the `managing-work-items` skill. This is additive -- all existing workflow steps remain unchanged; issue tracking invocations are inserted between steps.

### Issue Reference Extraction

At the start of every workflow, after step 1 (documentation) completes and the requirements artifact exists, the orchestrator extracts the issue reference:

1. Invoke `managing-work-items fetch <requirements-artifact-path>` using FR-7 (issue reference extraction from documents) — executed inline per "How to Invoke `managing-work-items`" below
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

### How to Invoke `managing-work-items`

`managing-work-items` is a **cross-cutting reference document**, not a forkable step. The orchestrator **executes it inline from its own main context** using its existing `Bash`, `Read`, and `Glob` tool access. Concretely:

1. **Once per workflow, at workflow start**, the orchestrator `Read`s `${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/SKILL.md` plus whichever template reference it will need (`references/github-templates.md` for `#N` issues or `references/jira-templates.md` for `PROJ-123` issues). The file is a reference document — the orchestrator consults it the way a function looks up an argument table, not the way it forks a sub-skill.
2. **At every call site below**, the orchestrator runs the documented `gh` / `acli` / Rovo MCP command directly from main context. No Agent tool fork. No Skill tool call. No sub-conversation.
3. **Graceful degradation** (NFR-1) still applies — every external command is wrapped in the try/skip pattern from `managing-work-items/SKILL.md:287-306`. Failures are logged and the workflow continues.

**Note on cross-cutting skills**: `managing-work-items` is deliberately not in any chain step table (Feature, Chore, or Bug). Cross-cutting skills — skills invoked between steps rather than as a step — do **not** follow the Forked Steps recipe below. They follow this "How to Invoke" subsection instead. This distinction matters because the Forked Steps recipe is scoped to "steps marked **fork** in the step sequence", and cross-cutting invocations have no such marker.

#### Rejected alternatives

Two other invocation mechanisms were considered and explicitly rejected:

- **Agent-tool fork (rejected)**: Forking a subagent for every `gh issue comment` adds conversation-spawn overhead, audit-trail noise, and an unnecessary context boundary for what is usually a single CLI command. `managing-work-items` operations are small, stateless, and don't need isolation — they're idiomatic main-context tool use.
- **Skill-tool invocation (rejected)**: `managing-work-items` is framed as a reference document for the orchestrator; it is not a user-facing skill. Invoking it via the Skill tool would require restructuring its contract (name, trigger phrases, arguments) and would still force the orchestrator to hand off control to a sub-conversation for operations it can execute inline in one tool call.

**Inline execution composes cleanly with the existing Forked Steps recipe.** Step-sequence forks (skills that appear in the chain tables — `reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`, `pr-creation`) continue to use the Forked Steps recipe below. Cross-cutting invocations (`managing-work-items`) are handled inline per this subsection. The two mechanisms do not overlap and do not need to be reconciled.

#### Runnable examples

Each example assumes the orchestrator has already `Read` the `managing-work-items/SKILL.md` reference document once at workflow start and has `issueRef` in scope (either a `#N` GitHub reference or a `PROJ-123` Jira reference).

**Operation 1: `extract-ref` (parse issue reference from requirements document)**

Use `Read` on the requirements document and search for the `## GitHub Issue` section. Pseudocode:

```
content = Read("requirements/features/FEAT-042-my-feature.md")
# Find the "## GitHub Issue" heading and the next non-empty line
# Match patterns: [#N](URL) or [PROJ-123](URL)
# Example content under the heading:
#   ## GitHub Issue
#   [#131](https://github.com/lwndev/lwndev-marketplace/issues/131)
issueRef = "#131"  # extracted; store for the rest of the workflow
```

Concretely, `Grep` the file for `^\[#[0-9]+\]` or `^\[[A-Z][A-Z0-9]*-[0-9]+\]` within the `## GitHub Issue` section, or (equivalently) `Read` the file and string-search in the orchestrator's head. If the section is missing or empty, set `issueRef` to empty and log the info-level skip message; do **not** warn.

**Operation 2: `fetch` (retrieve issue data via `gh issue view`)**

For a GitHub `#N` reference:

```bash
gh issue view 131 --json title,body,labels,state,assignees
```

The orchestrator runs this via its `Bash` tool and parses the returned JSON. For a Jira `PROJ-123` reference, the orchestrator follows the tiered fallback documented in `managing-work-items/SKILL.md` — first try Rovo MCP (`getJiraIssue(cloudId, "PROJ-123")`), then `acli jira workitem view --key PROJ-123`, then skip with a warning if both are unavailable. The orchestrator executes whichever tier succeeds directly; no subagent fork.

**Operation 3: `comment` (post a lifecycle comment via `gh issue comment`)**

For a phase-start comment on a GitHub issue:

1. `Read` the appropriate template from `${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/references/github-templates.md` — select the `phase-start` section.
2. Substitute context variables (`phase`, `totalPhases`, `workItemId`, phase name, steps, deliverables) into the template to produce the rendered markdown body.
3. Run the following command. Use the plain multi-line double-quoted string form (matching the canonical templates in `github-templates.md`); do **not** wrap the body in a `$(cat <<'EOF' ... EOF)"` heredoc — the closing `EOF` delimiter must be at column 0, which conflicts with markdown list-continuation indentation and breaks copy-paste from raw source:

   ```bash
   gh issue comment 131 --body "## Phase 1 Started: GitHub Backend

   **FEAT-014** — Phase 1 of 4

   ### Steps
   - Implement classifier script
   - Wire up state-file fields
   ..."
   ```

   If the rendered body contains literal `$`, backticks, or backslashes that you do not want bash to interpret, use single quotes instead: `gh issue comment 131 --body '...'`. For dynamic substitution, build the body in a shell variable first (`body="..."; gh issue comment 131 --body "$body"`).

4. On failure (non-zero exit), emit a warning-level skip message (see "Mechanism-Failure Logging" below) and continue the workflow.

For a Jira `PROJ-123` reference, the orchestrator instead reads `jira-templates.md`, renders the ADF JSON (for Rovo MCP) or markdown (for `acli`), and invokes the matching backend tier. The template and backend selection are the only differences — the inline-execution pattern is the same.

**Operation 4: `pr-link` (generate PR body issue link)**

For GitHub, hand-write the syntax when constructing the PR body:

```
Closes #131
```

For Jira, write the issue key:

```
PROJ-123
```

This is pure string generation — the orchestrator does not need to shell out for it. It builds the PR body in main context and passes it to `gh pr create --body` alongside all other PR metadata.

#### Mechanism-Failure Logging (WARNING level)

Graceful degradation (NFR-1) tells the orchestrator to skip issue operations on failure rather than block the workflow. That's still correct — but a **mechanism-missing** failure must be distinguishable from a legitimate empty-`issueRef` skip. The orchestrator emits a WARNING-level log line (visibly distinct from the INFO-level skip) in the following cases:

| Failure mode | Warning message format |
|--------------|------------------------|
| `managing-work-items/SKILL.md` cannot be read at workflow start | `[warn] managing-work-items reference document unreadable at ${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/SKILL.md — issue tracking disabled for this workflow.` |
| `gh` CLI missing when `issueRef` is a `#N` reference | `[warn] gh CLI not found on PATH — cannot invoke managing-work-items for GitHub issue ${issueRef}. Skipping issue tracking.` |
| `gh` CLI not authenticated when `issueRef` is `#N` | `[warn] gh CLI not authenticated (run \`gh auth login\`) — cannot invoke managing-work-items for GitHub issue ${issueRef}. Skipping issue tracking.` |
| Jira tiered fallback exhausts all three tiers | `[warn] No Jira backend available (Rovo MCP not registered, acli not found) — cannot invoke managing-work-items for Jira issue ${issueRef}. Skipping issue tracking.` |
| GitHub template file unreadable | `[warn] managing-work-items GitHub template file unreadable at references/github-templates.md — cannot render ${commentType} comment. Skipping.` |
| Jira template file unreadable | `[warn] managing-work-items Jira template file unreadable at references/jira-templates.md — cannot render ${commentType} comment. Skipping.` |

Contrast with the INFO-level skip (legitimate empty-`issueRef`):

```
[info] No issue reference found in requirements document -- skipping issue tracking.
```

The key distinction: INFO means "nothing to do", WARNING means "we have work to do but can't do it — silent-skip regression risk". The `[warn]` prefix is mandatory so a future `grep -n '\[warn\]' conversation.log` catches mechanism regressions.

## Quick Start

1. Parse argument — determine new workflow vs resume, and chain type (feature, chore, or bug)
2. **Check Claude Code version (FEAT-014 NFR-6)**: run `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh check-claude-version 2.1.72` once at the entry point. The subcommand exits `0` silently when current ≥ required (or when the version cannot be determined), and exits `1` with a one-line warning on stderr when the installed Claude Code is older than the minimum. Treat the warning as advisory — continue the workflow; the per-fork NFR-6 fallback wrapper (see "Forked Steps") will catch any Agent-tool `model`-parameter rejection and retry without the parameter.
3. **New feature workflow**: Run step 1 (`documenting-features`) in main context, read allocated ID, initialize state with `init {ID} feature`
4. **New chore workflow**: Run step 1 (`documenting-chores`) in main context, read allocated ID, initialize state with `init {ID} chore`
5. **New bug workflow**: Run step 1 (`documenting-bugs`) in main context, read allocated ID, initialize state with `init {ID} bug`
6. **Resume**: Load state, handle pause/failure logic, continue from current step
7. Execute steps sequentially using the step execution procedures below
8. **Feature chain**: Pause at plan approval (step 4) and PR review (step 6+N+2)
9. **Chore chain**: Pause at PR review only (step 6) — no plan-approval pause
10. **Bug chain**: Pause at PR review only (step 6) — no plan-approval pause, same as chore chain
11. On completion, mark workflow complete

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
| 2 | Review requirements (standard) | `reviewing-requirements` | fork (skip if `complexity == low`) |
| 3 | Document QA test plan | `documenting-qa` | **main** |
| 4 | Reconcile test plan | `reviewing-requirements` | fork (skip if `complexity == low` or no mapping sections) |
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
| 2 | Review requirements (standard) | `reviewing-requirements` | fork (skip if `complexity == low`) |
| 3 | Document QA test plan | `documenting-qa` | **main** |
| 4 | Reconcile test plan | `reviewing-requirements` | fork (skip if `complexity == low` or no mapping sections) |
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

**Extract issue reference**: If the argument was a `#N` issue reference, invoke `managing-work-items fetch <issueRef>` to retrieve issue data (this was already used by `documenting-features` to pre-fill requirements via delegation). Use FR-7 to extract the issue reference from the requirements artifact and store it as `issueRef` for all subsequent `managing-work-items` invocations. Both the `fetch` and `extract-ref` calls are executed inline from the orchestrator's main context — see "How to Invoke `managing-work-items`" in the Issue Tracking section above for the runnable examples. If no issue reference is found, skip all future `managing-work-items` calls (see Skip Behavior above).

### 4. Initialize State

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh init {ID} feature
```

Write the active workflow ID:

```bash
echo "{ID}" > .sdlc/workflows/.active
```

Immediately classify work-item complexity (FEAT-014 FR-2a) by shelling out to the classifier and persisting the result via `set-complexity`. `complexityStage` stays at `init` (the default written by `init`):

```bash
tier=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" classify-init {ID} "requirements/features/{artifact-filename}")
"${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" set-complexity {ID} "${tier}"
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

**Extract issue reference**: Use FR-7 from `managing-work-items` to extract the issue reference from the requirements artifact (executed inline — see "How to Invoke `managing-work-items`" in the Issue Tracking section above). Store it as `issueRef` for all subsequent `managing-work-items` invocations. If no issue reference is found, skip all future `managing-work-items` calls (see Skip Behavior above).

### 4. Initialize State

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh init {ID} chore
```

Write the active workflow ID:

```bash
echo "{ID}" > .sdlc/workflows/.active
```

Classify work-item complexity (FEAT-014 FR-2a) — chore chains only run the init-stage classifier (no post-plan stage):

```bash
tier=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" classify-init {ID} "requirements/chores/{artifact-filename}")
"${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" set-complexity {ID} "${tier}"
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

**Extract issue reference**: Use FR-7 from `managing-work-items` to extract the issue reference from the requirements artifact (executed inline — see "How to Invoke `managing-work-items`" in the Issue Tracking section above). Store it as `issueRef` for all subsequent `managing-work-items` invocations. If no issue reference is found, skip all future `managing-work-items` calls (see Skip Behavior above).

### 4. Initialize State

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh init {ID} bug
```

Write the active workflow ID:

```bash
echo "{ID}" > .sdlc/workflows/.active
```

Classify work-item complexity (FEAT-014 FR-2a) — bug chains, like chores, only run the init-stage classifier:

```bash
tier=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" classify-init {ID} "requirements/bugs/{artifact-filename}")
"${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" set-complexity {ID} "${tier}"
```

### 5. Advance Step 1 and Continue

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "requirements/bugs/{artifact-filename}"
```

Continue to execute remaining steps starting from step 2.

## Resume Procedure

When the argument matches an existing ID (`FEAT-NNN`, `CHORE-NNN`, `BUG-NNN`):

1. Read state: `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh status {ID}` — the read path also migrates pre-FEAT-014 state files in place (FR-13): missing `complexity`, `complexityStage`, `modelOverride`, and `modelSelections` are silently added with their init defaults, so the rest of the resume procedure can treat the four fields as present.
2. **Re-compute work-item complexity (FEAT-014 FR-12)**. Before deciding status, run `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resume-recompute {ID}`. The subcommand is stage-aware and upgrade-only:
   - It re-reads the requirement document and re-runs the init-stage classifier **always**.
   - If `complexityStage` is already `post-plan`, it also re-reads the implementation plan and re-runs the post-plan classifier.
   - It computes `new_tier = max(persisted_complexity, newly_computed_tier)` and persists the new value **only if** it strictly upgrades. If the tier is unchanged or would be a downgrade, the subcommand proceeds silently and keeps the persisted value (complexityStage never regresses).
   - On an upgrade, the subcommand writes a one-line info message to stderr in the documented format (`[model] Work-item complexity upgraded since last invocation: <old> → <new>. Audit trail continues.`) and updates the state file.
   - **Escape hatch for explicit downgrades** (FR-12): if the user genuinely wants to lower the tier between pause and resume, they must run `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-complexity {ID} <lower-tier>` before re-invoking the orchestrator. That is the only recorded user-authored path to a downgrade; doc edits alone never downgrade on resume.
3. Write active marker: `echo "{ID}" > .sdlc/workflows/.active`
4. Determine chain type from the state file's `type` field (`feature`, `chore`, or `bug`)
5. Check status:
   - **paused** with `plan-approval` → (Feature chain only; chore and bug chains have no plan-approval pause.) Ask "Ready to proceed with implementation?" If yes, call `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resume {ID}` and advance past the pause step, then continue.
   - **paused** with `pr-review` → Check PR status via `gh pr view {prNumber} --json state,reviews,mergeStateStatus`. If approved/mergeable, call `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resume {ID}`, advance past the pause step, and continue. If changes requested, report the feedback and stay paused. If pending review, inform user and stay paused. If the PR is closed, report the state and suggest re-opening the PR or restarting from the execution step (feature: phase loop; chore: step 5; bug: step 5). (Applies to all chain types: feature, chore, and bug.)
   - **paused** with `review-findings` → The previous `reviewing-requirements` step found unresolved errors. Call `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resume {ID}` and re-run the current `reviewing-requirements` fork step from scratch. If the re-run returns zero errors, advance and continue. If errors persist, surface findings and pause again with `review-findings`.
   - **failed** → Call `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resume {ID}`. Retry the failed step.
   - **in-progress** → Continue from the current step.
6. Use the appropriate step sequence table (Feature Chain, Chore Chain, or Bug Chain) when determining the next step to execute.

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

**Scope**: This recipe applies **only** to steps marked **fork** in the Feature/Chore/Bug chain step-sequence tables above. Cross-cutting skills — skills that are not listed in any chain step table, such as `managing-work-items` — do **not** follow this recipe. They are executed inline from the orchestrator's main context per the "How to Invoke `managing-work-items`" subsection in the Issue Tracking section. If you find yourself trying to apply the Forked Steps recipe to `managing-work-items`, stop: that skill has a different invocation mechanism and the two do not overlap.

For all steps marked **fork** in the step sequence, use the Agent tool to delegate. Every fork site must execute the FEAT-014 pre-fork sequence **before** spawning the subagent — the audit trail write must precede fork execution (NFR-3) so a crashed fork still leaves a trace:

1. Read the sub-skill's SKILL.md content:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md
   ```

2. **Resolve the tier (FEAT-014 FR-3)**. Call `resolve-tier` with the canonical step-name (see "Fork Step-Name Map" below) and forward any CLI model-selection flags received from the orchestrator invocation:

   ```bash
   tier=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" resolve-tier {ID} {step-name} \
     ${cli_model:+--cli-model $cli_model} \
     ${cli_complexity:+--cli-complexity $cli_complexity} \
     ${cli_model_for:+--cli-model-for $cli_model_for})
   ```

3. **Write the audit trail entry (FEAT-014 FR-7, NFR-3)**. The write happens BEFORE the fork so a crashed subagent still leaves a trace:

   ```bash
   stage=$(jq -r '.complexityStage // "init"' ".sdlc/workflows/{ID}.json")
   "${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" record-model-selection \
     {ID} {stepIndex} {skill-name} {mode-or-null} {phase-or-null} "${tier}" "${stage}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```

4. **Emit the FR-14 console echo line** in the documented format. Non-locked forks use `wi-complexity=`; baseline-locked forks (`finalizing-workflow`, `pr-creation`) use the literal `baseline-locked` tag instead:

   ```
   [model] step {N} ({skill}, {mode-or-phase}) → {tier} (baseline={baseline}, wi-complexity={complexity}, override={override-or-none})
   ```

   Baseline-locked example:
   ```
   [model] step 11 (finalizing-workflow) → haiku (baseline=haiku, baseline-locked)
   ```

   If the resolved tier is a hard-override-below-baseline downgrade (Edge Case 11), also emit the warning line: `[model] Hard override --model {tier} bypassed baseline {baseline} for {skill}. Proceeding at user request.`

5. Spawn a general-purpose subagent via the Agent tool. The prompt must include:
   - The full SKILL.md content
   - The work item ID as argument (e.g., `FEAT-003` or `CHORE-001`)
   - Any step-specific instructions (see below)

   **Pass the resolved `${tier}` as the `model` parameter to the Agent tool on every fork** (FEAT-014 FR-9). No fork inherits the parent conversation's model by default.

6. Wait for the subagent to return a summary.

7. **NFR-6 Agent-tool-rejection fallback (per call site)**. If the Agent tool call in step 6 errors with an "unknown parameter" error on `model` (Claude Code older than 2.1.72), the orchestrator must **retry the same fork exactly once without the `model` parameter** and emit the documented warning line to the console: `[model] Agent tool rejected model parameter — falling back to parent-model inheritance for this fork. Upgrade to Claude Code 2.1.72+ for adaptive selection.` The retry uses the same prompt and the same subagent identity; it does not append a new `modelSelections` entry (the initial audit-trail write from step 3 already captured the intended tier). This wrapper is **per call site** so it composes cleanly with the FR-11 retry classifier below — both can fire for the same fork, but the NFR-6 fallback triggers on tool-parameter errors whereas FR-11 triggers on classifier-flagged output failures.

8. **FR-11 retry-with-tier-upgrade (per call site)**. After the subagent returns, classify its output:
   - **Classifier-flagged failure**: the subagent returned an empty artifact, or its run hit the tool-use loop limit. These are the only two failure modes that count as "possibly under-provisioned".
   - **NOT a failure**: a `reviewing-requirements` fork that returns structured findings (the `Found **N errors**, **N warnings**, **N info**` summary line, or the `No issues found` sentinel). Those are legitimate results and must flow through the Reviewing-Requirements Findings Handling path — do **not** retry with an upgraded tier.
   - **NOT a failure**: any subagent error that originated from user-authored content (bad input, missing doc, malformed plan). Those surface through the normal `fail` path.

   When a classifier-flagged failure occurs, retry the fork **once** at the next tier up using the pure helper `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh next-tier-up <current-tier>`. Tier escalation is `haiku → sonnet → opus → fail`; each fork's retry budget is `1` (independent per-fork — one failing step does not reduce the budget for subsequent steps). The retry **must**:
   1. Compute the escalated tier via `next-tier-up`. If the current tier is already `opus`, call `fail {ID} "retry exhausted at opus for step N"` and halt. Do not emit a second retry.
   2. Write a new `modelSelections` audit-trail entry for the retry via `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-model-selection` before re-invoking the Agent tool — the original entry is preserved so the audit trail shows both attempts.
   3. Emit a fresh FR-14 console echo line for the retry attempt, tagged with the new tier.
   4. Re-invoke the Agent tool with the escalated `model` parameter. If that attempt also classifies as a failure, call `fail {ID} "retry exhausted at <escalated-tier> for step N"` (unless the escalated tier itself was already `opus`, in which case retry is exhausted after this second attempt) and halt.

   The NFR-6 wrapper from step 7 still applies to the retry call — if the escalated-tier fork is rejected by an older Claude Code, the parent-model fallback kicks in on that retry too.

9. Validate the expected artifact exists (use Glob to check). If the artifact is missing after both the NFR-6 fallback and FR-11 retry paths have had their chance, record failure:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh fail {ID} "Step N: expected artifact not found"
   ```

10. On success, advance state:
    ```bash
    ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "{artifact-path}"
    ```

#### Fork Step-Name Map

The `resolve-tier` and `record-model-selection` subcommands key off canonical step-names (not the human-readable table names). Use these exact strings:

| Fork site | Step-name | Baseline | Baseline-locked? |
|-----------|-----------|----------|------------------|
| Review requirements (standard / test-plan / code-review) | `reviewing-requirements` | sonnet | no |
| Create implementation plan | `creating-implementation-plans` | sonnet | no |
| Implement phases (per-phase) | `implementing-plan-phases` | sonnet | no |
| Execute chore | `executing-chores` | sonnet | no |
| Execute bug fix | `executing-bug-fixes` | sonnet | no |
| Finalize workflow | `finalizing-workflow` | haiku | **yes** |
| PR creation (inline fork) | `pr-creation` | haiku | **yes** |

For `reviewing-requirements` call sites, pass the mode (`standard`, `test-plan`, `code-review`) as the `mode` argument of `record-model-selection`. For `implementing-plan-phases`, pass the phase number as the `phase` argument. All other sites pass `null` for both.

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

**Step 2 — `reviewing-requirements` (standard review)**: Append `{ID}` as argument. The skill auto-detects standard review mode. Run the FEAT-014 pre-fork sequence with step-name `reviewing-requirements` and mode `standard`.

**Step 3 — `creating-implementation-plans`**: Append `{ID}` as argument. Expected artifact: `requirements/implementation/{ID}-*.md`. Run the FEAT-014 pre-fork sequence with step-name `creating-implementation-plans`.

**Post-step-3 re-classification (FEAT-014 FR-2b)**: Immediately after step 3's artifact is validated and before `advance` returns control to the next fork, trigger the post-plan re-classification. This runs exactly once per feature chain and must precede any fork that resolves a tier:

```bash
tier=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" classify-post-plan {ID})
# classify-post-plan applies upgrade-only max(persisted, phase_count_tier) and persists
# the result plus complexityStage="post-plan" when an upgrade occurs; silent otherwise.
```

If the plan file is missing or malformed, `classify-post-plan` retains the init-stage tier per NFR-5 and emits a one-line warning. Chore and bug chains have no post-plan stage.

**Step 6 — `reviewing-requirements` (test-plan reconciliation)**: Append `{ID}` as argument. The skill auto-detects test-plan reconciliation mode because `qa/test-plans/QA-plan-{ID}.md` exists. Run the FEAT-014 pre-fork sequence with step-name `reviewing-requirements` and mode `test-plan`. This fork is the first to see the post-plan stage transition (if one occurred).

**Steps 7…6+N — `implementing-plan-phases`**: See Phase Loop below.

**Step 6+N+1 — Create PR**: See PR Creation below.

**Step 6+N+3 — `reviewing-requirements` (code-review reconciliation)**: Append `{ID} --pr {prNumber}` as argument. The skill auto-detects code-review reconciliation mode. Run the FEAT-014 pre-fork sequence with step-name `reviewing-requirements` and mode `code-review`.

**Step 6+N+5 — `finalizing-workflow`**: No special argument needed. The skill merges the current PR and resets to main. Run the FEAT-014 pre-fork sequence with step-name `finalizing-workflow`. This step is **baseline-locked** at `haiku` — the pre-fork echo uses the `baseline-locked` tag, and only a hard override (`--model`, `--model-for`) can push it off its baseline.

### Chore Chain Step-Specific Fork Instructions

Steps 2, 4, 7, and 9 follow the same fork pattern as the feature chain without chore-specific overrides. Every fork runs the FEAT-014 pre-fork sequence (resolve-tier / record-model-selection / FR-14 echo) with the appropriate step-name and mode before spawning the subagent, and passes the resolved tier as the Agent tool's `model` parameter:

**Step 2 — `reviewing-requirements` (standard review)**: **Skip condition (CHORE-031 T2)**: read the persisted complexity from the state file (`jq -r '.complexity' ".sdlc/workflows/{ID}.json"`). If `complexity == low`, skip this fork — advance state without spawning a subagent:
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
```
Otherwise, append `{ID}` as argument. Pre-fork step-name `reviewing-requirements`, mode `standard`.

**Step 4 — `reviewing-requirements` (test-plan reconciliation)**: **Skip condition (CHORE-031 T6)**: if `complexity == low`, or the produced `qa/test-plans/QA-plan-{ID}.md` contains no mapping sections (grep for lines matching `^##+ .*[Mm]apping` returns no results), skip this fork — advance state without spawning a subagent:
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
```
Otherwise, append `{ID}` as argument. Pre-fork step-name `reviewing-requirements`, mode `test-plan`.

**Step 5 — `executing-chores` (fork)**:

Before forking (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type work-start --context '{"workItemId": "{ID}"}'` inline per "How to Invoke `managing-work-items`" above (read the `work-start` template from `references/github-templates.md` — or `references/jira-templates.md` for Jira — substitute context variables, and post via `gh issue comment` / Jira backend).

Run the FEAT-014 pre-fork sequence (resolve-tier / record-model-selection / FR-14 echo) using step-name `executing-chores`, then fork via the Agent tool with `{ID}` as argument and the resolved tier passed as the `model` parameter. If `issueRef` is set, include the FR-6 issue link instruction in the subagent prompt: "Include `Closes #N` (or `PROJ-123` for Jira) in the PR body." After the subagent completes:
1. Extract the PR number from the subagent output (the `executing-chores` skill creates a PR as its final step)
2. If the PR number is not in the output, detect it via: `gh pr list --head {branch} --json number --jq '.[0].number'`
3. Record the PR metadata:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

After step 5 completes (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type work-complete --context '{"workItemId": "{ID}", "prNumber": <pr-number>}'` inline per "How to Invoke `managing-work-items`" above.

**Step 7 — `reviewing-requirements` (code-review reconciliation)**: Append `{ID} --pr {prNumber}` as argument. Pre-fork step-name `reviewing-requirements`, mode `code-review`.

**Step 9 — `finalizing-workflow`**: No special argument needed. Pre-fork step-name `finalizing-workflow` (baseline-locked `haiku`; echo uses the `baseline-locked` tag).

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

Steps 2, 4, 7, and 9 follow the same fork pattern as the chore chain. Every fork runs the FEAT-014 pre-fork sequence before spawning the subagent and passes the resolved tier as the Agent tool's `model` parameter:

**Step 2 — `reviewing-requirements` (standard review)**: **Skip condition (CHORE-031 T2)**: read the persisted complexity from the state file (`jq -r '.complexity' ".sdlc/workflows/{ID}.json"`). If `complexity == low`, skip this fork — advance state without spawning a subagent:
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
```
Otherwise, append `{ID}` as argument. Pre-fork step-name `reviewing-requirements`, mode `standard`.

**Step 4 — `reviewing-requirements` (test-plan reconciliation)**: **Skip condition (CHORE-031 T6)**: if `complexity == low`, or the produced `qa/test-plans/QA-plan-{ID}.md` contains no mapping sections (grep for lines matching `^##+ .*[Mm]apping` returns no results), skip this fork — advance state without spawning a subagent:
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
```
Otherwise, append `{ID}` as argument. Pre-fork step-name `reviewing-requirements`, mode `test-plan`.

**Step 5 — `executing-bug-fixes` (fork)**:

Before forking (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type bug-start --context '{"workItemId": "{ID}"}'` inline per "How to Invoke `managing-work-items`" above (read the `bug-start` template from `references/github-templates.md` — or `references/jira-templates.md` for Jira — substitute context variables, and post via `gh issue comment` / Jira backend).

Run the FEAT-014 pre-fork sequence (resolve-tier / record-model-selection / FR-14 echo) using step-name `executing-bug-fixes`, then fork via the Agent tool with `{ID}` as argument and the resolved tier passed as the `model` parameter. If `issueRef` is set, include the FR-6 issue link instruction in the subagent prompt: "Include `Closes #N` (or `PROJ-123` for Jira) in the PR body." After the subagent completes:
1. Extract the PR number from the subagent output (the `executing-bug-fixes` skill creates a PR as its final step)
2. If the PR number is not in the output, detect it via: `gh pr list --head {branch} --json number --jq '.[0].number'`
3. Record the PR metadata:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

After step 5 completes (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type bug-complete --context '{"workItemId": "{ID}", "prNumber": <pr-number>}'` inline per "How to Invoke `managing-work-items`" above.

**Step 7 — `reviewing-requirements` (code-review reconciliation)**: Append `{ID} --pr {prNumber}` as argument. Pre-fork step-name `reviewing-requirements`, mode `code-review`.

**Step 9 — `finalizing-workflow`**: No special argument needed. Pre-fork step-name `finalizing-workflow` (baseline-locked `haiku`; echo uses the `baseline-locked` tag).

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

   **a. Before the phase** (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type phase-start --context '{"phase": <phase-number>, "totalPhases": <N>, "workItemId": "{ID}"}'` inline per "How to Invoke `managing-work-items`" above (read the `phase-start` template from `references/github-templates.md` — or `references/jira-templates.md` for Jira — substitute context variables, and post via `gh issue comment` / Jira backend).

   **b. Run the FEAT-014 pre-fork sequence**. Resolve the tier per phase (the `complexityStage` — `init` or `post-plan` — is captured per entry so the audit trail shows the upgrade transition when one occurred):

   ```bash
   tier=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" resolve-tier {ID} implementing-plan-phases \
     ${cli_model:+--cli-model $cli_model} \
     ${cli_complexity:+--cli-complexity $cli_complexity} \
     ${cli_model_for:+--cli-model-for $cli_model_for})
   stage=$(jq -r '.complexityStage // "init"' ".sdlc/workflows/{ID}.json")
   "${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" record-model-selection \
     {ID} {stepIndex} implementing-plan-phases null {phase-number} "${tier}" "${stage}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```

   Then emit the FR-14 echo line: `[model] step {stepIndex} (implementing-plan-phases, phase {phase-number}) → {tier} (baseline=sonnet, wi-complexity={complexity}, override={override-or-none})`.

   **c. Fork `implementing-plan-phases`** with the Agent tool. The prompt must include:
   - The SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/SKILL.md`
   - Argument: `{ID} {phase-number}`
   - **Critical**: Append this instruction to the prompt: "Do NOT create a pull request at the end — the orchestrator handles PR creation separately. Skip Step 12 (Create Pull Request) entirely."

   Pass the resolved `${tier}` as the Agent tool's `model` parameter (FEAT-014 FR-9).

   **d. After the phase completes** (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type phase-completion --context '{"phase": <phase-number>, "totalPhases": <N>, "workItemId": "{ID}"}'` inline per "How to Invoke `managing-work-items`" above.

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

1. Run the FEAT-014 pre-fork sequence for the PR-creation inline fork. This site is **baseline-locked** at `haiku` — work-item complexity and soft overrides are ignored; only a hard `--model` / `--model-for pr-creation:<tier>` override can push it off baseline.

   ```bash
   tier=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" resolve-tier {ID} pr-creation \
     ${cli_model:+--cli-model $cli_model} \
     ${cli_complexity:+--cli-complexity $cli_complexity} \
     ${cli_model_for:+--cli-model-for $cli_model_for})
   stage=$(jq -r '.complexityStage // "init"' ".sdlc/workflows/{ID}.json")
   "${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" record-model-selection \
     {ID} {stepIndex} pr-creation null null "${tier}" "${stage}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```

   Emit the FR-14 echo line with the `baseline-locked` tag: `[model] step {stepIndex} (pr-creation) → haiku (baseline=haiku, baseline-locked)`.

2. Fork a subagent to create the PR. Pass the resolved `${tier}` as the Agent tool's `model` parameter. The prompt should instruct:
   - Create a pull request from the current feature branch to main
   - If `issueRef` is set, use `managing-work-items` FR-6 to generate the issue link for the PR body: `Closes #N` for GitHub issues or `PROJ-123` for Jira issues. Include this link in the PR body. This `pr-link` operation is pure string generation, executed inline per "How to Invoke `managing-work-items`" above — the orchestrator builds the PR body in main context and passes it to `gh pr create --body` without forking
   - Return the PR number and branch name

3. Record PR metadata:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

4. Continue to step 6+N+2 (PR review pause).

## Model Selection

This section summarizes the FEAT-014 adaptive model selection policy that every fork in this skill obeys. For the full algorithm pseudocode, tuning guidance, audit-trail field reference, known limitations, and migration guidance, read `references/model-selection.md` — that file is the canonical reference and this section is a concise summary.

Per-fork model selection is a two-axis lookup combined with an override chain. The orchestrator runs the `resolve-tier` subcommand of `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` before every fork; the return value is passed verbatim as the Agent tool's `model` parameter.

```text
final_tier = walk_override_chain(
    base = max(step_baseline, work_item_complexity),
    overrides = [cli_model_for, cli_model, cli_complexity, state_model_override]
)
```

Tiers are ordered `haiku < sonnet < opus`. Complexity labels map to tiers via `low → haiku`, `medium → sonnet`, `high → opus`.

### Axis 1 — Step baseline matrix

| Step | Baseline tier | Rationale |
|------|---------------|-----------|
| `reviewing-requirements` (any mode) | `sonnet` | Structured validation, bidirectional cross-reference, grep-heavy. Haiku risks missing subtle consistency errors. |
| `creating-implementation-plans` | `sonnet` | Most plans benefit from Sonnet; complex features get bumped via work-item signals. |
| `implementing-plan-phases` | `sonnet` | Per-phase fork. Heavy edits but typically scoped. Complex phases bump to Opus. |
| `executing-chores` | `sonnet` | Routine refactors, dependency bumps, cleanups. |
| `executing-bug-fixes` | `sonnet` | Root-cause-driven edit + test + PR. |
| `finalizing-workflow` | `haiku` | Mechanical: merge PR, checkout main, fetch, pull. **Baseline-locked**. |
| PR creation (orchestrator inline fork) | `haiku` | Pure `gh pr create` with a templated body. **Baseline-locked**. |

Steps that run in **main context** — `documenting-*`, `documenting-qa`, `executing-qa` — are unaffected; they run on whatever model the parent conversation uses.

The baseline is a **floor** for computed and soft-overridden tiers. Even when work-item complexity is `low` (would map to `haiku`), a step whose baseline is `sonnet` still runs on `sonnet`. Only hard overrides (`--model`, `--model-for`) can push below the floor, and they do so with a visible warning.

### Axis 2 — Work-item complexity signal matrix

Computed at workflow init from the requirement document and persisted to state. For features, the tier may be upgraded (upgrade-only) after step 3 completes, using the phase count of the implementation plan.

| Chain | Signal | Stage | Value → tier |
|-------|--------|-------|-------------|
| **Chore** | Acceptance criteria count | init | ≤3 → `low`; 4–8 → `medium`; 9+ → `high` |
| **Bug** | Severity field | init | `low` → `low`; `medium` → `medium`; `high`/`critical` → `high` |
| **Bug** | Root-cause count (RC-N) | init | 1 → `low`; 2–3 → `medium`; 4+ → `high` |
| **Bug** | Category | init | `security` / `performance` → bump one tier; others → no change |
| **Feature** | FR count | init | ≤5 → `low`; 6–12 → `medium`; 13+ → `high` |
| **Feature** | NFR mentions security/auth/perf | init | yes → bump one tier |
| **Feature** | Phase count | post-plan | 1 → `low`; 2–3 → `medium`; 4+ → `high` *(upgrade-only)* |

Work-item complexity = `max` of the applicable signals, then mapped `low → haiku`, `medium → sonnet`, `high → opus`.

Unparseable signals (missing section, empty document, malformed template) fall back to `medium` (= `sonnet`) per FR-10. The fallback **never** returns `opus` — silently reintroducing over-provisioning is exactly the behavior FEAT-014 exists to prevent.

### Axis 3 — Override precedence (hard vs soft)

Walked in strict precedence order; the first non-null entry wins. Hard overrides replace the tier entirely; soft overrides are upgrade-only and respect baseline locks.

| Order | Override | Kind | Behavior |
|-------|----------|------|----------|
| 1 | CLI `--model-for <step>:<tier>` | hard | Replaces tier for the matching step. Bypasses baseline lock for that step. |
| 2 | CLI `--model <tier>` | hard | Replaces tier for every fork, including baseline-locked steps. Can downgrade below baseline. |
| 3 | CLI `--complexity <tier>` | soft | `max(current, override)` applied via the work-item complexity axis. Respects baseline lock and baseline floor. |
| 4 | State file `modelOverride: <tier>` | soft | Upgrade-only. Respects baseline lock. Editable between pause and resume via `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-complexity`. |
| 5 | Computed tier | — | Lowest precedence. Derived from step baseline and work-item complexity. |

**Hard vs soft in one line**: hard overrides answer "I know exactly what I want; do it"; soft overrides answer "I think this work is at least this complex".

### Baseline-locked step exceptions

`finalizing-workflow` and the inline PR-creation fork are **baseline-locked**:

- The work-item complexity axis is **skipped** for these steps (FR-3 step 2 is a no-op).
- Soft overrides (`--complexity`, state `modelOverride`) are **ignored** — they cannot push baseline-locked steps off their baseline.
- Hard overrides (`--model`, `--model-for`) **bypass** the lock and apply normally — `--model opus` on a feature chain forces `finalizing-workflow` and PR creation to `opus`.

Rationale: these are mechanical `gh` / `git` operations with no reasoning component, regardless of how complex the overall feature is. Upgrading them to a higher tier costs tokens with zero quality benefit. A hard override is the explicit escape hatch for users who want to force them anyway.

### Worked examples

#### Example A — low-complexity chore (zero Opus)

Chore: "Move `src/utils/example.test.ts` to `test/utils/example.test.ts` and drop `src/**` glob from `vitest.config.ts`." — 5 acceptance criteria → `medium` → `sonnet`.

| Step | Baseline | Final |
|------|----------|-------|
| `reviewing-requirements` (standard) | sonnet | sonnet |
| `reviewing-requirements` (test-plan) | sonnet | sonnet |
| `executing-chores` | sonnet | sonnet |
| `reviewing-requirements` (code-review) | sonnet | sonnet |
| `finalizing-workflow` | haiku | **haiku** *(baseline-locked)* |

Result: **zero Opus invocations**. Entire chain runs on Sonnet + Haiku.

#### Example B — low-severity bug (zero Opus; Sonnet baseline floor)

Bug: `querySelector<HTMLElement>` → `as HTMLElement | null` fix. Severity `low`, 1 root cause, logic-error category → work-item complexity `low` → `haiku`.

| Step | Baseline | Final |
|------|----------|-------|
| `reviewing-requirements` (standard) | sonnet | sonnet *(baseline floor)* |
| `reviewing-requirements` (test-plan) | sonnet | sonnet *(baseline floor)* |
| `executing-bug-fixes` | sonnet | sonnet *(baseline floor)* |
| `reviewing-requirements` (code-review) | sonnet | sonnet *(baseline floor)* |
| `finalizing-workflow` | haiku | haiku |

Result: again **zero Opus invocations** — step baselines floor minor-bug work at Sonnet, which is the right choice for validation/edit work even when the bug is trivial.

#### Example C — two-stage feature (init `sonnet` upgraded to `opus`)

Feature: paginated search endpoint with cursor-based pagination. 5 FRs, NFR section covers rate limiting and response latency (perf match → bump). Plan has 4 phases.

- **Stage 1 init**: 5 FRs → `low`; NFR perf bump → `medium` → `sonnet`.
- **Stage 2 post-plan**: 4 phases → `high`; `max(sonnet, opus) = opus` — upgrade triggered.

| Step | Baseline | Final | Stage |
|------|----------|-------|-------|
| 2. `reviewing-requirements` (standard) | sonnet | **sonnet** | init |
| 3. `creating-implementation-plans` | sonnet | **sonnet** | init |
| 5. `documenting-qa` (main) | — | parent's model | — |
| 6. `reviewing-requirements` (test-plan) | sonnet | **opus** | post-plan |
| 7–10. `implementing-plan-phases` × 4 | sonnet | **opus** | post-plan |
| 11. PR creation | haiku | **haiku** *(baseline-locked)* | — |
| 13. `reviewing-requirements` (code-review) | sonnet | **opus** | post-plan |
| 15. `finalizing-workflow` | haiku | **haiku** *(baseline-locked)* | — |

The audit trail will show the stage transition via per-entry `complexityStage` in `modelSelections`: early entries record `init`, later entries record `post-plan`.

#### Example D — high-complexity feature (both stages resolve to Opus)

Feature: "Add OAuth2 login with PKCE" — 12 FRs, NFR mentions session token storage and replay protection (security → bump). Plan has 4 phases.

- Init stage: 12 FRs → `medium`; security NFR bump → `high` → `opus`.
- Post-plan stage: 4 phases → `high`; `max(opus, opus) = opus`, no transition visible.

Every fork above baseline runs on Opus from step 2 onward. This is the steady-state case for genuinely high-complexity features where the init-stage signals alone are already decisive — the post-plan recomputation is a no-op. `finalizing-workflow` and PR creation still run on `haiku` because work-item complexity does not apply to baseline-locked steps; only `--model opus` would push them up.

### Further reading

The full FR-3 pseudocode, signal-extractor pseudocode, tuning guidance for per-step baselines, `modelSelections` audit-trail field reference with `jq` query recipes, known limitations, and migration guidance for users who want the old "inherit-parent-model" behavior (`--model opus`, wrapper aliases, `--model-for`) all live in `references/model-selection.md` alongside this skill.

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

### Issue Tracking Verification

Issue tracking is supplementary (NFR-1) and must never block workflow progression, but the **reason** for a skipped invocation matters. After the workflow completes, confirm the observed state matches exactly one of the three cases below — and that the log line type (INFO vs WARNING) matches the case. A silent mismatch (e.g., no comments posted but no WARNING either, when `issueRef` was populated) indicates a mechanism-missing regression of BUG-009 and must be escalated.

- [ ] **Case A — invocation succeeded and posted a comment**: `issueRef` was populated from the requirements document, the orchestrator executed `gh issue comment` / Jira backend calls inline, and at least one lifecycle comment is visible on the linked issue. Verification command: `gh issue view <N> --comments` (or `acli jira workitem view --key PROJ-123` for Jira). Expected: `phase-start` + `phase-completion` per phase (feature), or `work-start` + `work-complete` (chore), or `bug-start` + `bug-complete` (bug), plus `Closes #N` / `PROJ-123` in the PR body.
- [ ] **Case B — gracefully skipped because `issueRef` is empty**: The requirements document has no `## GitHub Issue` section (or the section is empty). The orchestrator's conversation log contains exactly one `[info] No issue reference found in requirements document -- skipping issue tracking.` line and no lifecycle comments are expected. No WARNING-level log lines should appear for issue tracking in this case. This is the correct NFR-1 behavior.
- [ ] **Case C — skipped because the invocation mechanism failed**: `issueRef` was populated, but the orchestrator could not execute the invocation because of a mechanism failure (unreadable `managing-work-items/SKILL.md`, missing `gh`, unauthenticated `gh`, exhausted Jira tiered fallback, unreadable template file). The orchestrator's conversation log contains at least one `[warn]` line in the format documented in "Mechanism-Failure Logging" identifying which failure mode fired. The workflow still completes, but the WARNING line makes the silent-skip regression observable. Verify the warning message names the specific failure (e.g., `gh CLI not found on PATH`, `No Jira backend available`) and not the generic "No issue reference found" info message.

If the observed state cannot be classified into one of these three cases, treat it as a BUG-009 regression candidate and investigate the conversation log for silent skips.

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
