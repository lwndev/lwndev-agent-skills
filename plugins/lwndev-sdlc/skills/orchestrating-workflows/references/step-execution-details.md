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

**Step 6+N+4 — `finalizing-workflow`**: No special argument needed. The skill merges the current PR and resets to main. Run the FEAT-014 pre-fork sequence with step-name `finalizing-workflow`. This step is **baseline-locked** at `haiku` — the pre-fork echo uses the `baseline-locked` tag, and only a hard override (`--model`, `--model-for`) can push it off its baseline.

### Chore Chain Step-Specific Fork Instructions

Steps 2, 4, and 8 follow the same fork pattern as the feature chain without chore-specific overrides. Every non-skipped fork runs the FEAT-014 pre-fork sequence (resolve-tier / record-model-selection / FR-14 echo) with the appropriate step-name and mode before spawning the subagent, and passes the resolved tier as the Agent tool's `model` parameter. Steps skipped by CHORE-031 conditions call only `advance` — no pre-fork sequence, no audit trail entry, and no `modelSelections` entry for that step index:

**Step 2 — `reviewing-requirements` (standard review)**: **Skip condition (CHORE-031 T2)**: read the persisted complexity from the state file (`jq -r '.complexity' ".sdlc/workflows/{ID}.json"`). If `complexity == low`, skip this fork — advance state without spawning a subagent:
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
```
Otherwise, append `{ID}` as argument. Pre-fork step-name `reviewing-requirements`, mode `standard`.

**Step 4 — `reviewing-requirements` (test-plan reconciliation)**: **Skip condition (CHORE-031 T6)**: if `complexity == low`, skip this fork — advance state without spawning a subagent:
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
```
Otherwise, append `{ID}` as argument. Pre-fork step-name `reviewing-requirements`, mode `test-plan`.

**Step 5 — `executing-chores` (fork)**:

Before forking (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type work-start --context '{"workItemId": "{ID}"}'` inline per "How to Invoke `managing-work-items`" in [issue-tracking.md](issue-tracking.md) (read the `work-start` template from `references/github-templates.md` — or `references/jira-templates.md` for Jira — substitute context variables, and post via `gh issue comment` / Jira backend).

Run the FEAT-014 pre-fork sequence (resolve-tier / record-model-selection / FR-14 echo) using step-name `executing-chores`, then fork via the Agent tool with `{ID}` as argument and the resolved tier passed as the `model` parameter. If `issueRef` is set, include the FR-6 issue link instruction in the subagent prompt: "Include `Closes #N` (or `PROJ-123` for Jira) in the PR body." After the subagent completes:
1. Extract the PR number from the subagent output (the `executing-chores` skill creates a PR as its final step)
2. If the PR number is not in the output, detect it via: `gh pr list --head {branch} --json number --jq '.[0].number'`
3. Record the PR metadata:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

After step 5 completes (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type work-complete --context '{"workItemId": "{ID}", "prNumber": <pr-number>}'` inline per "How to Invoke `managing-work-items`" in [issue-tracking.md](issue-tracking.md).

**Step 8 — `finalizing-workflow`**: No special argument needed. Pre-fork step-name `finalizing-workflow` (baseline-locked `haiku`; echo uses the `baseline-locked` tag).

### Bug Chain Main-Context Steps (Steps 1, 3, 7)

**Step 1 — `documenting-bugs`**: See New Bug Workflow Procedure in [chain-procedures.md](chain-procedures.md).

**Step 3 — `documenting-qa`**: Same pattern as chore chain step 3. Read `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/SKILL.md`, follow its instructions in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-plans/QA-plan-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-plans/QA-plan-{ID}.md"
```

**Step 7 — `executing-qa`**: Same pattern as chore chain step 7. Read `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/SKILL.md`, follow its instructions in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-results/QA-results-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-results/QA-results-{ID}.md"
```

### Bug Chain Step-Specific Fork Instructions

Steps 2, 4, and 8 follow the same fork pattern as the chore chain. Every non-skipped fork runs the FEAT-014 pre-fork sequence before spawning the subagent and passes the resolved tier as the Agent tool's `model` parameter. Steps skipped by CHORE-031 conditions call only `advance` — no pre-fork sequence, no audit trail entry, and no `modelSelections` entry for that step index:

**Step 2 — `reviewing-requirements` (standard review)**: **Skip condition (CHORE-031 T2)**: read the persisted complexity from the state file (`jq -r '.complexity' ".sdlc/workflows/{ID}.json"`). If `complexity == low`, skip this fork — advance state without spawning a subagent:
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
```
Otherwise, append `{ID}` as argument. Pre-fork step-name `reviewing-requirements`, mode `standard`.

**Step 4 — `reviewing-requirements` (test-plan reconciliation)**: **Skip condition (CHORE-031 T6)**: if `complexity == low`, skip this fork — advance state without spawning a subagent:
```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
```
Otherwise, append `{ID}` as argument. Pre-fork step-name `reviewing-requirements`, mode `test-plan`.

**Step 5 — `executing-bug-fixes` (fork)**:

Before forking (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type bug-start --context '{"workItemId": "{ID}"}'` inline per "How to Invoke `managing-work-items`" in [issue-tracking.md](issue-tracking.md) (read the `bug-start` template from `references/github-templates.md` — or `references/jira-templates.md` for Jira — substitute context variables, and post via `gh issue comment` / Jira backend).

Run the FEAT-014 pre-fork sequence (resolve-tier / record-model-selection / FR-14 echo) using step-name `executing-bug-fixes`, then fork via the Agent tool with `{ID}` as argument and the resolved tier passed as the `model` parameter. If `issueRef` is set, include the FR-6 issue link instruction in the subagent prompt: "Include `Closes #N` (or `PROJ-123` for Jira) in the PR body." After the subagent completes:
1. Extract the PR number from the subagent output (the `executing-bug-fixes` skill creates a PR as its final step)
2. If the PR number is not in the output, detect it via: `gh pr list --head {branch} --json number --jq '.[0].number'`
3. Record the PR metadata:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

After step 5 completes (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type bug-complete --context '{"workItemId": "{ID}", "prNumber": <pr-number>}'` inline per "How to Invoke `managing-work-items`" in [issue-tracking.md](issue-tracking.md).

**Step 8 — `finalizing-workflow`**: No special argument needed. Pre-fork step-name `finalizing-workflow` (baseline-locked `haiku`; echo uses the `baseline-locked` tag).

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
   This inserts N phase steps and 4 post-phase steps (Create PR, PR review, Execute QA, Finalize) into the state file after the initial 6 steps.

2. For each phase 1 through N:

   **a. Before the phase** (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type phase-start --context '{"phase": <phase-number>, "totalPhases": <N>, "workItemId": "{ID}"}'` inline per "How to Invoke `managing-work-items`" in [issue-tracking.md](issue-tracking.md) (read the `phase-start` template from `references/github-templates.md` — or `references/jira-templates.md` for Jira — substitute context variables, and post via `gh issue comment` / Jira backend).

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

   **d. After the phase completes** (if `issueRef` is set): invoke `managing-work-items comment <issueRef> --type phase-completion --context '{"phase": <phase-number>, "totalPhases": <N>, "workItemId": "{ID}"}'` inline per "How to Invoke `managing-work-items`" in [issue-tracking.md](issue-tracking.md).

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
   - If `issueRef` is set, use `managing-work-items` FR-6 to generate the issue link for the PR body: `Closes #N` for GitHub issues or `PROJ-123` for Jira issues. Include this link in the PR body. This `pr-link` operation is pure string generation, executed inline per "How to Invoke `managing-work-items`" in [issue-tracking.md](issue-tracking.md) — the orchestrator builds the PR body in main context and passes it to `gh pr create --body` without forking
   - Return the PR number and branch name

3. Record PR metadata:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}
   ```

4. Continue to step 6+N+2 (PR review pause).
