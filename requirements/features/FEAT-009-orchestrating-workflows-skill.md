# Feature Requirements: Orchestrating Workflows Skill

## Overview

Orchestrate the full SDLC workflow chains (feature, chore, bug) end-to-end through a single `orchestrating-workflows` skill that sequences sub-skill invocations, manages state across pause points, and isolates per-step context via Agent tool forking.

## Feature ID
`FEAT-009`

## GitHub Issue
[#89](https://github.com/lwndev/lwndev-marketplace/issues/89)

## Priority
High - Core orchestration infrastructure that #90 (chores) and #91 (bugs) build on

## User Story

As a developer using the lwndev-sdlc plugin, I want to invoke a single skill that drives my entire workflow chain so that I don't have to manually invoke each sub-skill in sequence and risk skipping steps like reconciliation.

## Invocation Syntax

```
/orchestrating-workflows "add skill chaining"    # New workflow — creates FEAT-XXX
/orchestrating-workflows #42                     # New workflow from GitHub issue
/orchestrating-workflows FEAT-003                # Resume paused/failed workflow
```

### Arguments
- `<title-or-issue>` (required for new workflows) - Free-text feature title or `#N` GitHub issue reference
- `<ID>` (required for resume) - Existing workflow ID (e.g., `FEAT-003`, `CHORE-012`, `BUG-007`)

### Chain Detection
The orchestrator detects chain type from the ID prefix:
- `FEAT-XXX` → Feature chain
- `CHORE-XXX` → Chore chain (future: #90)
- `BUG-XXX` → Bug chain (future: #91)

## Functional Requirements

### FR-1: Feature Chain Step Sequence
Execute the feature chain as 6 + N + 5 steps where N = number of implementation phases:

| # | Step | Skill | Context | Expected Artifact |
|---|------|-------|---------|-------------------|
| 1 | Document requirements | `documenting-features` | **main** | `requirements/features/FEAT-{ID}-*.md` |
| 2 | Review requirements (standard) | `reviewing-requirements` | fork | (edits existing) |
| 3 | Create implementation plan | `creating-implementation-plans` | fork | `requirements/implementation/FEAT-{ID}-*.md` |
| 4 | **PAUSE: Plan approval** | — | — | User reviews plan |
| 5 | Document QA test plan | `documenting-qa` | **main** | `qa/test-plans/QA-plan-FEAT-{ID}.md` |
| 6 | Reconcile test plan | `reviewing-requirements` | fork | (edits existing) |
| 7…6+N | Implement phases 1…N | `implementing-plan-phases` | fork | Commits on `feat/FEAT-{ID}-*` branch |
| 6+N+1 | Create PR | orchestrator | fork | PR created from branch |
| 6+N+2 | **PAUSE: PR review** | — | — | Checks `gh pr view` on resume |
| 6+N+3 | Reconcile post-review | `reviewing-requirements` | fork | (advisory) |
| 6+N+4 | Execute QA | `executing-qa` | **main** | `qa/test-results/QA-results-FEAT-{ID}.md` |
| 6+N+5 | Finalize | `finalizing-workflow` | fork | PR merged, on main |

### FR-2: Context Strategy
Three categories of context handling:

- **Main context** (steps 1, 5, 6+N+4): Run directly in the orchestrator's conversation. Step 1 may prompt the user interactively. Steps 5 and 6+N+4 delegate to `qa-verifier` subagent internally and rely on Stop hooks that don't fire when forked (#92).
- **Forked context** (all other steps): Orchestrator reads the sub-skill's SKILL.md from `${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md`, spawns a general-purpose subagent via the Agent tool with the skill content as the task prompt (appending the work item ID), subagent works autonomously, returns summary, orchestrator validates artifacts and advances state.
- **Pause points** (steps 4, 6+N+2): Workflow halts, state persisted, user re-invokes to resume.

### FR-3: Forking via Agent Tool
The orchestrator controls forking — sub-skills are NOT modified:

1. Read sub-skill's SKILL.md content from plugin directory
2. Spawn general-purpose subagent via Agent tool with SKILL.md as task prompt, appending the work item ID as argument
3. Subagent follows the skill's procedure autonomously, writing artifacts to disk
4. Subagent returns summary to orchestrator
5. Orchestrator validates artifact existence, updates state, continues

### FR-4: Phase Loop (Steps 7 through 6+N)
Dynamic implementation phase execution:

1. Read the implementation plan to determine phase count via `scripts/workflow-state.sh phase-count {ID}`
2. Dynamically populate steps 7…6+N in the state file, one per phase
3. Fork `implementing-plan-phases FEAT-{ID} {phase-number}` for each pending phase via Agent tool
4. Each phase commits to the same branch (`feat/FEAT-{ID}-*`)
5. PR is created only after the final phase completes — not per-phase
6. If a phase fails, halt and record the failure

### FR-5: Pause — Plan Approval (Step 4)
After `creating-implementation-plans` completes:

- Set state to `status: "paused"`, `pauseReason: "plan-approval"`
- Display message: "Implementation plan created at `requirements/implementation/FEAT-{ID}-*.md`. Review it and re-invoke `/orchestrating-workflows FEAT-{ID}` to continue."
- On resume: ask "Ready to proceed with implementation?" before advancing

### FR-6: Pause — PR Review (Step 6+N+2)
After PR creation:

- Record `prNumber` in state, set `pauseReason: "pr-review"`
- Display PR number and link
- On resume: run `gh pr view {prNumber} --json state,reviews,mergeStateStatus`
  - Approved/mergeable → advance
  - Changes requested → report feedback, stay paused
  - Pending review → inform user, stay paused

### FR-7: Resume from State
When invoked with an existing ID (e.g., `FEAT-003`):

1. Read state file from `.sdlc/workflows/{ID}.json`
2. Determine current step from state
3. If `paused` — handle pause-specific resume logic (FR-5, FR-6); on successful resume, call `scripts/workflow-state.sh resume {ID}` to transition to `in-progress` and record the resume timestamp in `lastResumedAt`
4. If `failed` — retry the failed step; call `resume {ID}` to update `lastResumedAt`
5. If `in-progress` — continue from current step

### FR-8: Reconciliation Steps Always Included
All reconciliation steps (`reviewing-requirements` in test-plan and code-review modes) are mandatory. The orchestrator ensures no steps are skipped.

### FR-9: PR Creation Step
After all implementation phases complete, the orchestrator creates a PR:

- Fork a subagent that creates the PR from the feature branch
- Record PR number and branch in state via `scripts/workflow-state.sh set-pr {ID} {pr-number} {branch}`

### FR-10: ID Allocation Delegation
The orchestrator does not assign workflow IDs directly. ID allocation (e.g., `FEAT-009`, `CHORE-028`) is delegated to the step-1 sub-skill (`documenting-features`, `documenting-chores`, or `documenting-bugs`), which determines the next sequential ID by scanning existing requirement files. The orchestrator reads the assigned ID from the step-1 artifact and uses it for state file naming and all subsequent steps.

### FR-11: Implementation Phase PR Suppression
The `implementing-plan-phases` skill currently creates a PR at the end of each invocation. The orchestrator must prevent per-phase PR creation by appending explicit instructions to the Agent tool prompt (e.g., "Do NOT create a pull request at the end — the orchestrator handles PR creation separately"). This approach avoids modifying the sub-skill itself (consistent with NFR-3). The orchestrator creates the PR in a dedicated post-phase step (FR-9) instead.

## State Management

### State Script: `scripts/workflow-state.sh`
Bash script bundled within the skill directory at `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh`. Referenced in SKILL.md as `scripts/workflow-state.sh` (relative to the skill directory root per the Agent Skills specification). The script uses the current working directory (the user's project) for all project-relative paths (`.sdlc/`, `requirements/`). Requires `jq` for JSON manipulation. Called by both the orchestrator skill and the Stop hook.

**Environment requirements:** These scripts require a bash-compatible shell and `jq`. On Windows, use WSL or Git Bash. The skill's SKILL.md frontmatter declares these via the `compatibility` field (e.g., `Requires jq and a bash-compatible shell`).

| Command | Description |
|---------|-------------|
| `init {ID} {type}` | Create state file, populate step sequence for the chain type |
| `status {ID}` | Return current state as JSON |
| `advance {ID} [artifact-path]` | Mark current step complete (with optional artifact), advance to next |
| `pause {ID} {reason}` | Set status to paused (`pr-review`, `plan-approval`) |
| `fail {ID} {message}` | Set status to failed with error details |
| `complete {ID}` | Mark workflow as complete |
| `set-pr {ID} {pr-number} {branch}` | Record PR metadata in state |
| `resume {ID}` | Set status to `in-progress`, clear `pauseReason` and `error`, update `lastResumedAt` to current timestamp |
| `populate-phases {ID} {count}` | Insert N phase steps and 5 post-phase steps after the initial 6 steps; update `phases.total` |
| `phase-count {ID}` | Read implementation plan, return number of phases |
| `phase-status {ID}` | Return per-phase completion status |

The script must be idempotent — running `advance` twice on a completed step is a no-op.

### State File Location
`.sdlc/workflows/{ID}.json` (gitignored)

### State File Format
```json
{
  "id": "FEAT-003",
  "type": "feature",
  "currentStep": 7,
  "status": "in-progress",
  "pauseReason": null,
  "steps": [
    {
      "name": "Document feature requirements",
      "skill": "documenting-features",
      "context": "main",
      "status": "complete",
      "artifact": "requirements/features/FEAT-003-skill-chaining.md",
      "completedAt": "2026-03-28T14:00:00Z"
    },
    {
      "name": "Review requirements (standard)",
      "skill": "reviewing-requirements",
      "context": "fork",
      "status": "complete"
    },
    {
      "name": "Implement phase 1 of 3",
      "skill": "implementing-plan-phases",
      "context": "fork",
      "status": "complete",
      "phaseNumber": 1,
      "completedAt": "2026-03-28T15:30:00Z"
    },
    {
      "name": "Implement phase 2 of 3",
      "skill": "implementing-plan-phases",
      "context": "fork",
      "status": "in-progress",
      "phaseNumber": 2
    }
  ],
  "phases": {
    "total": 3,
    "completed": 1
  },
  "prNumber": null,
  "branch": "feat/FEAT-003-skill-chaining",
  "startedAt": "2026-03-28T13:00:00Z",
  "lastResumedAt": null
}
```

## Stop Hook

### Purpose
A **command hook** (not prompt) on the orchestrator skill prevents premature stopping mid-chain.

### Active Workflow Tracking
The orchestrator writes the current workflow ID to `.sdlc/workflows/.active` at the start of each invocation (new or resume). The Stop hook reads this file to determine which workflow to query. If the file doesn't exist or is empty, the hook allows stop (no active workflow).

### Behavior
1. Read the active workflow ID from `.sdlc/workflows/.active`
2. Run `scripts/workflow-state.sh status {ID}`
3. If workflow is `complete` or `paused` → exit 0 (allow stop)
4. If workflow is `in-progress` with remaining steps → exit 2 with "Continue to step N+1: {description}"

### Hook Constraints
- **No `PostToolUse` hooks** — too fragile to detect "step complete" from individual tool calls
- **No `SessionStart` hooks** — resume is explicit via re-invocation
- **No plugin-level hooks** — orchestration is skill-scoped

## Non-Functional Requirements

### NFR-1: Context Window Efficiency
A 5-phase feature means ~16 skill invocations. Without forking, each loads 3–5K tokens of SKILL.md plus tool outputs — easily 150K+ tokens. Compaction is lossy and would drop critical earlier-step context. Forked steps must get clean context windows while the orchestrator remains lightweight.

### NFR-2: Error Handling
- Step failure → state set to `failed` with error; Stop hook allows stop; resume retries the failed step
- QA failures → `executing-qa` has its own ralph loop for retries within the step; if unfixable, orchestrator records failure
- Phase failure → halt the phase loop; don't proceed to subsequent phases or PR creation

### NFR-3: Sub-Skill Isolation
Sub-skills are NOT modified — no `context: fork` added to their frontmatter. They behave normally when invoked standalone. The orchestrator handles all forking decisions. Issue #94 tracks the separate evaluation of adding `context: fork` to skills directly.

### NFR-4: Idempotency
State script operations must be idempotent. Re-running `advance` on a completed step is a no-op. Re-initializing an existing workflow returns the current state rather than overwriting.

### NFR-5: State File Validation
On load, the state script validates JSON integrity and required fields (`id`, `type`, `status`, `steps`, `currentStep`). If the state file is malformed or missing required fields, the script exits with a clear error message and does not attempt partial recovery. The orchestrator surfaces this error and suggests deleting the state file to restart the workflow.

## Dependencies

- Existing sub-skills: `documenting-features`, `reviewing-requirements`, `creating-implementation-plans`, `documenting-qa`, `implementing-plan-phases`, `executing-qa`, `finalizing-workflow`
- Claude Code Agent tool for forking subagents
- `gh` CLI for PR status checks
- `jq` for JSON manipulation in state scripts
- Bash-compatible shell (macOS/Linux native; Windows via WSL or Git Bash)
- `.sdlc/` directory gitignored in the repository

## Edge Cases

1. **Workflow already exists for ID**: Resume from current state rather than re-initializing
2. **Implementation plan has 0 phases**: Error with clear message — plan may be malformed
3. **Phase branch already exists**: Continue committing to existing branch
4. **PR already exists for branch**: Detect existing PR and record it rather than creating a duplicate
5. **GitHub API unavailable during PR check**: Report error, stay paused, suggest retry
6. **Sub-skill SKILL.md not found**: Error with clear message indicating missing plugin/skill
7. **State file corrupted or malformed**: Error with suggestion to delete and re-start
8. **User invokes sub-skill standalone mid-workflow**: No conflict — sub-skills work independently; state tracks orchestrator-driven progress only
9. **Multiple concurrent workflows**: State files are per-ID; no cross-workflow interference
10. **Unrecognized or malformed ID prefix**: Error with message listing supported prefixes (`FEAT-`, `CHORE-`, `BUG-`) and expected format (e.g., `FEAT-003`, not `feat-003` or `FEAT003`)
11. **Stale `.active` file**: If `.sdlc/workflows/.active` references a workflow that is `complete` or whose state file doesn't exist, the Stop hook cleans up `.active` and allows stop
12. **`jq` not installed**: State script checks for `jq` availability on first invocation and exits with a clear error message and install instructions

## Testing Requirements

### Unit Tests
- State script command coverage: `init`, `status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`, `phase-count`, `phase-status`
- State file JSON structure validation
- Chain type detection from ID prefix
- Step sequence generation for feature chain

### Integration Tests
- New workflow initialization and first step execution
- Pause and resume cycle (plan approval)
- Pause and resume cycle (PR review with mock `gh pr view`)
- Phase loop with dynamic phase count
- Error recovery (failed step → resume → retry)
- Stop hook behavior (in-progress vs. paused vs. complete)

### Manual Testing
- Full feature chain end-to-end with a real feature
- Resume from each pause point
- Verify sub-skills work standalone after orchestrator changes
- Verify context isolation (forked steps don't pollute orchestrator context)

## Related Issues

- **#90**: Chore chain step sequence (builds on this infrastructure)
- **#91**: Bug chain step sequence (builds on this infrastructure)
- **#92**: Frontmatter Stop hooks don't fire in `context: fork` — confirms `documenting-qa` and `executing-qa` must run in main context
- **#93**: `/skill-name` auto-forks when `context: fork` is in frontmatter
- **#94**: Separate evaluation of adding `context: fork` to skills directly

## Acceptance Criteria

- [ ] `orchestrating-workflows` skill exists with frontmatter, description, and Stop hook
- [ ] `scripts/workflow-state.sh` (bundled in skill directory) handles all commands (`init`, `status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`, `populate-phases`, `phase-count`, `phase-status`)
- [ ] State files written to `.sdlc/workflows/{ID}.json`; `.sdlc/` is gitignored
- [ ] Step 1, `documenting-qa`, and `executing-qa` run in main context; all other steps forked via Agent tool
- [ ] Forked steps read SKILL.md content and delegate as subagent task prompts
- [ ] Sub-skills are NOT modified — no `context: fork` added to their frontmatter
- [ ] Phase loop dynamically determines phase count from implementation plan
- [ ] Each phase forks separately; all commit to the same branch
- [ ] PR created only after final phase completes (not per-phase)
- [ ] Pauses at plan approval (step 4) and PR review (step 6+N+2)
- [ ] Resume via re-invocation reads state and continues from correct step
- [ ] PR review resume checks actual PR status via `gh pr view`
- [ ] Stop hook prevents premature stopping mid-chain
- [ ] Step failures halt the chain with clear error reporting
- [ ] Reconciliation steps (`reviewing-requirements` in test-plan and code-review modes) cannot be skipped or omitted from the step sequence
- [ ] When orchestrated, `implementing-plan-phases` does not create a PR — PR is created in the dedicated post-phase step
- [ ] The orchestrator reads the allocated ID from the step-1 artifact rather than assigning it directly
- [ ] State script operations are idempotent — `advance` on a completed step is a no-op; `init` on an existing workflow returns current state
- [ ] Malformed or incomplete state files produce a clear error with a suggestion to delete and restart
