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

