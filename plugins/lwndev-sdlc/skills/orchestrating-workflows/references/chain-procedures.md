## New Feature Workflow Procedure

When starting a new feature workflow (argument is a title or `#N` issue):

1. Run `documenting-features` directly in main context. Pass a `#N` issue reference through, or pass free-text as the feature name. This step may prompt the user interactively. Wait for it to produce an artifact at `requirements/features/FEAT-{ID}-*.md`.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/init-workflow.sh" feature "<artifact-path>"`.

   Composite covers: ID extraction from filename, `mkdir -p .sdlc/workflows`, `workflow-state.sh init`, `classify-init` + `set-complexity` (FEAT-014 FR-2a; `complexityStage` stays `init`), `.sdlc/workflows/.active` write, `advance`, and inline `managing-work-items` issue-reference extraction (FR-7).

   Stdout JSON: `{"id":"FEAT-NNN","type":"feature","complexity":"low|medium|high","issueRef":"#N|\"\""}`. Persist `issueRef` for all subsequent `managing-work-items` invocations; empty `issueRef` → skip future `managing-work-items` calls (see Skip Behavior in [issue-tracking.md](issue-tracking.md)). Continue from step 2 of the feature chain.

## New Chore Workflow Procedure

When starting a new chore workflow (argument indicates a chore task):

1. Run `documenting-chores` directly in main context. Pass the argument as the chore description. This step may prompt the user interactively. Wait for it to produce an artifact at `requirements/chores/CHORE-{ID}-*.md`.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/init-workflow.sh" chore "<artifact-path>"`.

   Same composite coverage as the feature case (init-stage classifier only; no post-plan stage). Stdout JSON: `{"id":"CHORE-NNN","type":"chore","complexity":"low|medium|high","issueRef":"#N|\"\""}`. Continue from step 2 of the chore chain.

## New Bug Workflow Procedure

When starting a new bug workflow (argument indicates a bug fix, defect, or regression):

1. Run `documenting-bugs` directly in main context. Pass the argument as the bug description. This step may prompt the user interactively. Wait for it to produce an artifact at `requirements/bugs/BUG-{ID}-*.md`.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/init-workflow.sh" bug "<artifact-path>"`.

   Same composite coverage as the chore case (init-stage classifier only). Stdout JSON: `{"id":"BUG-NNN","type":"bug","complexity":"low|medium|high","issueRef":"#N|\"\""}`. Continue from step 2 of the bug chain.

## Resume Procedure

When the argument matches an existing ID (`FEAT-NNN`, `CHORE-NNN`, `BUG-NNN`):

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/check-resume-preconditions.sh" <ID>`.

   Composite covers: `workflow-state.sh status` (with FR-13 in-place migration of pre-FEAT-014 state files — `complexity`, `complexityStage`, `modelOverride`, `modelSelections` silently added with init defaults), FEAT-014 FR-12 `resume-recompute` (stage-aware upgrade-only re-classification; relays any `[model] Work-item complexity upgraded since last invocation: <old> → <new>. Audit trail continues.` stderr line verbatim), and `type` read.

   Stdout JSON: `{"type":"feature|chore|bug","status":"in-progress|paused|failed|complete","pauseReason":"plan-approval|pr-review|review-findings|null","currentStep":<int>,"chainTable":"feature|chore|bug","complexity":"low|medium|high","complexityStage":"init|post-plan"}`. `modelOverride` is NOT emitted here by design — `workflow-state.sh resolve-tier` reads it directly from state on every fork, so the value is always fresh.

   Explicit-downgrade escape hatch (FR-12): if the user wants to lower the tier between pause and resume, they must run `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-complexity {ID} <lower-tier>` before re-invoking the orchestrator. Doc edits alone never downgrade on resume.

   Dispatch on `status` + `pauseReason`:
   - **paused** + `plan-approval` → (Feature chain only; chore and bug chains have no plan-approval pause.) Ask "Ready to proceed with implementation?" If yes, call `resume {ID}` and advance past the pause step, then continue.
   - **paused** + `pr-review` → Check PR status via `gh pr view {prNumber} --json state,reviews,mergeStateStatus`. If approved/mergeable, call `resume {ID}`, advance past the pause step, and continue. If changes requested, report the feedback and stay paused. If pending review, inform user and stay paused. If the PR is closed, report the state and suggest re-opening the PR or restarting from the execution step (feature: phase loop; chore: step 5; bug: step 5). Applies to all chain types.
   - **paused** + `review-findings` → Call `resume {ID}` and re-run the current `reviewing-requirements` fork step from scratch. Parse the re-run findings through the Decision Flow in SKILL.md (including the chain-type/complexity gate for warnings-only results). If the re-run returns zero errors, advance and continue. If the re-run returns warnings/info only, apply Decision Flow `auto-advance` for bug/chore at `complexity <= medium` or `prompt-user` for high-complexity bug/chore and feature chains. If errors persist, surface findings and pause again with `review-findings`.
   - **failed** → Call `resume {ID}`. Retry the failed step.
   - **in-progress** → Continue from the current step.
2. Use the appropriate step sequence table (Feature Chain, Chore Chain, or Bug Chain) when determining the next step to execute.

