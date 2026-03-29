# Implementation Plan: Orchestrating Workflows Skill

## Overview

Build the `orchestrating-workflows` skill and its supporting infrastructure to drive full SDLC workflow chains (feature, chore, bug) end-to-end. The feature chain is implemented first as the most complex variant (6 + N + 5 steps with a dynamic phase loop and 2 pause points). The chore (#90) and bug (#91) chain sequences build on this infrastructure separately.

The implementation has three components: a shell-based state management script, the orchestrator skill itself (a SKILL.md with orchestration procedure), and a command-based Stop hook that prevents premature stopping mid-chain.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-009 | [#89](https://github.com/lwndev/lwndev-marketplace/issues/89) | [FEAT-009-orchestrating-workflows-skill.md](../features/FEAT-009-orchestrating-workflows-skill.md) | High | High | Pending |

## Recommended Build Sequence

### Phase 1: State Management Script and Infrastructure
**Feature:** [FEAT-009](../features/FEAT-009-orchestrating-workflows-skill.md) | [#89](https://github.com/lwndev/lwndev-marketplace/issues/89)
**Status:** ✅ Complete

#### Rationale
- **Foundation first**: Every other component (skill, Stop hook) depends on the state script to read and write workflow state
- **Independently testable**: The shell script can be verified in isolation before the skill exists
- **Unblocks parallel work**: Once state management works, the skill and hook can be developed with confidence in the underlying data layer

#### Implementation Steps
1. Add `.sdlc/` to `.gitignore` (append after existing entries)
2. Create `scripts/workflow-state.sh` as an executable shell script with a subcommand dispatcher
3. Implement the `init {ID} {type}` command:
   - Validate ID format matches `FEAT-NNN`, `CHORE-NNN`, or `BUG-NNN` (case-sensitive, dash-separated, 3+ digit number)
   - Create `.sdlc/workflows/` directory if it doesn't exist
   - If state file already exists, return current state (idempotent — don't overwrite)
   - For `type=feature`: populate the 6 pre-phase steps (document requirements, review requirements, create implementation plan, pause: plan approval, document QA, reconcile test plan) with `status: "pending"`. Phase steps are populated later by `phase-count`
   - For `type=chore`: populate all 9 steps per #90
   - For `type=bug`: populate all 9 steps per #91
   - Set `status: "in-progress"`, `currentStep: 1`, `startedAt` to current ISO 8601 timestamp, `lastResumedAt: null`
   - Write JSON to `.sdlc/workflows/{ID}.json`
4. Implement the `status {ID}` command:
   - Read and validate `.sdlc/workflows/{ID}.json`
   - Validate required fields (`id`, `type`, `status`, `steps`, `currentStep`) — exit with error if malformed (NFR-5)
   - Output the full JSON to stdout
5. Implement the `advance {ID} [artifact-path]` command:
   - Read current state; if current step is already complete, no-op (idempotent)
   - Mark current step as `status: "complete"`, set `completedAt` to current timestamp
   - If `artifact-path` provided, record it in the step's `artifact` field
   - Increment `currentStep`; if all steps complete, set workflow `status: "complete"`
   - Write updated state
6. Implement the `pause {ID} {reason}` command:
   - Set `status: "paused"`, `pauseReason` to the given reason (`plan-approval` or `pr-review`)
   - Write updated state
7. Implement the `resume {ID}` command:
   - Set `status: "in-progress"`, clear `pauseReason` to `null`, update `lastResumedAt` to current ISO 8601 timestamp
   - Write updated state
8. Implement the `fail {ID} {message}` command:
   - Set `status: "failed"`, record error message in a top-level `error` field
   - Write updated state
9. Implement the `complete {ID}` command:
   - Set `status: "complete"`, record `completedAt` timestamp at the workflow level
   - Write updated state
10. Implement the `set-pr {ID} {pr-number} {branch}` command:
    - Set `prNumber` and `branch` fields in state
    - Write updated state
11. Implement the `phase-count {ID}` command:
    - Read the implementation plan from `requirements/implementation/FEAT-{ID}-*.md` (glob for matching file)
    - Count the number of `### Phase N:` headings in the file
    - Output the count as a plain integer to stdout
    - If feature chain: dynamically populate phase steps (7 through 6+N) in the state file with `status: "pending"`, each with a `phaseNumber` field, and append the 5 post-phase steps (create PR, pause: PR review, reconcile post-review, execute QA, finalize)
    - Update `phases.total` in state
12. Implement the `phase-status {ID}` command:
    - Filter steps with `phaseNumber` field, output JSON array with each phase's number and status
13. Add error handling throughout: exit code 1 for errors (with stderr message), exit code 0 for success. Use `jq` for JSON manipulation (verify `jq` is available; if not, fall back to pure bash JSON handling or error with install suggestion).

#### Deliverables
- [x] Updated `.gitignore` with `.sdlc/` entry
- [x] `scripts/workflow-state.sh` — executable shell script with all 10 commands

---

### Phase 2: Orchestrator Skill
**Feature:** [FEAT-009](../features/FEAT-009-orchestrating-workflows-skill.md) | [#89](https://github.com/lwndev/lwndev-marketplace/issues/89)
**Status:** ✅ Complete
**Depends on:** Phase 1

#### Rationale
- **Core deliverable**: The SKILL.md is the orchestrator itself — it contains the full procedure Claude follows to drive the workflow chain
- **Depends on Phase 1**: The skill invokes `scripts/workflow-state.sh` for all state transitions
- **Single file**: The skill is one SKILL.md file, but it encodes the most complex logic — argument parsing, chain detection, forking, pause/resume, phase loop, and error handling

#### Implementation Steps
1. Create the skill directory: `plugins/lwndev-sdlc/skills/orchestrating-workflows/`
2. Create `SKILL.md` with YAML frontmatter:
   - `name: orchestrating-workflows`
   - `description: Orchestrate full SDLC workflow chains (feature, chore, bug) end-to-end — sequences sub-skill invocations, manages state across pause points, and isolates per-step context via Agent tool forking`
   - `allowed-tools`: Bash, Read, Glob, Grep, Write, Edit, Agent (needs Agent for forking sub-skills)
   - `argument-hint: "feature title" | #issue-number | FEAT-XXX | CHORE-XXX | BUG-XXX`
   - No `context: fork` — the orchestrator itself runs in main context
3. Write the **Argument Parsing** section:
   - If argument matches `FEAT-NNN`, `CHORE-NNN`, or `BUG-NNN` pattern → resume mode (FR-7)
   - If argument matches `#N` → new workflow from GitHub issue (fetch title/body via `gh issue view`)
   - Otherwise → new workflow with argument as free-text title
   - If no argument → prompt the user for workflow type and title
   - Validate ID format; error with supported prefixes for malformed IDs (edge case 10)
4. Write the **New Workflow** section:
   - Detect chain type: new workflows default to feature chain unless user specifies otherwise
   - Run step 1 in **main context**: invoke the step-1 sub-skill (`documenting-features`) directly in the conversation, passing the title or issue reference as argument. This step is interactive — the sub-skill may prompt the user.
   - After step 1 completes, read the generated artifact to extract the assigned ID (e.g., `FEAT-009` from the filename)
   - Call `scripts/workflow-state.sh init {ID} feature` to create the state file
   - Call `scripts/workflow-state.sh advance {ID} {artifact-path}` to mark step 1 complete
   - Continue to step 2
5. Write the **Forking Mechanism** section (FR-3):
   - For each forked step: read the sub-skill's SKILL.md from `${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md` using the Read tool
   - Spawn a general-purpose subagent via the Agent tool with the SKILL.md content as the task prompt, appending the workflow ID as argument
   - After the subagent returns, validate the expected artifact exists (Glob for the artifact path pattern from the step definition)
   - Call `advance` to mark the step complete with the artifact path
   - If the subagent fails or the artifact is missing, call `fail` and halt
6. Write the **Steps 2–6** section (pre-phase linear steps):
   - Step 2: Fork `reviewing-requirements {ID}` — standard review mode
   - Step 3: Fork `creating-implementation-plans {ID}` — creates implementation plan
   - Step 4: **Pause — plan approval** (FR-5): call `pause {ID} plan-approval`, display message with plan path, instruct user to re-invoke with ID to continue
   - Step 5: Run `documenting-qa {ID}` in **main context** (not forked — delegates to qa-verifier subagent internally)
   - Step 6: Fork `reviewing-requirements {ID}` — test-plan reconciliation mode (auto-detected)
7. Write the **Phase Loop** section (FR-4, steps 7 through 6+N):
   - Call `scripts/workflow-state.sh phase-count {ID}` to determine N and populate phase steps
   - For each phase 1 through N:
     - Fork `implementing-plan-phases {ID} {phase-number}` via Agent tool
     - Include instruction to the subagent to skip PR creation (FR-10 suppression): append "Do not create a pull request after this phase. The orchestrator handles PR creation after all phases complete." to the Agent task prompt
     - Call `advance` after each phase completes
     - If a phase fails, call `fail` and halt — do not proceed to subsequent phases
8. Write the **Post-Phase Steps** section (steps 6+N+1 through 6+N+5):
   - Step 6+N+1: **Create PR** — fork a subagent that runs `gh pr create` from the feature branch with title and body referencing the requirement ID. Call `set-pr {ID} {pr-number} {branch}`.
   - Step 6+N+2: **Pause — PR review** (FR-6): call `pause {ID} pr-review`, display PR number and link
   - Step 6+N+3: Fork `reviewing-requirements {ID}` — code-review reconciliation mode (auto-detected from PR existence)
   - Step 6+N+4: Run `executing-qa {ID}` in **main context** (not forked — same reasons as step 5)
   - Step 6+N+5: Fork `finalizing-workflow {ID}`
   - After step 6+N+5, call `complete {ID}`
9. Write the **Resume** section (FR-7):
   - Read state via `scripts/workflow-state.sh status {ID}`
   - If `paused` with `pauseReason: "plan-approval"`: call `resume {ID}`, ask "Ready to proceed with implementation?", continue to step 5
   - If `paused` with `pauseReason: "pr-review"`: run `gh pr view {prNumber} --json state,reviews,mergeStateStatus`, check status:
     - Approved/mergeable → call `resume {ID}`, continue to step 6+N+3
     - Changes requested → display review feedback, stay paused
     - Pending → inform user review is pending, stay paused
   - If `failed` → call `resume {ID}`, retry the failed step
   - If `in-progress` → continue from `currentStep`
10. Write the **Error Handling** section:
    - Step failure: call `fail {ID} {error-message}`, display error, allow stopping
    - Phase failure: halt phase loop, call `fail`, do not proceed
    - Missing artifact after fork: call `fail`, report which artifact was expected
    - State script errors: surface the error message to the user

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — full orchestrator skill with frontmatter and procedure

---

### Phase 3: Stop Hook and End-to-End Verification
**Feature:** [FEAT-009](../features/FEAT-009-orchestrating-workflows-skill.md) | [#89](https://github.com/lwndev/lwndev-marketplace/issues/89)
**Status:** ✅ Complete
**Depends on:** Phase 1, Phase 2

#### Rationale
- **Depends on both prior phases**: The Stop hook reads state (Phase 1) and is wired into the skill (Phase 2)
- **Critical safety mechanism**: Without the Stop hook, Claude may stop mid-chain losing orchestration context
- **Needs active workflow tracking**: The hook must know which workflow ID is active to query its state, requiring a tracking mechanism (`.sdlc/workflows/.active`)
- **Final integration step**: Verifies all components work together before the feature is considered complete

#### Implementation Steps
1. Implement active workflow tracking:
   - The orchestrator skill writes the current workflow ID to `.sdlc/workflows/.active` at the start of each invocation (new or resume)
   - This file contains just the ID string (e.g., `FEAT-009`)
   - The Stop hook reads this file to determine which workflow to check
2. Create `scripts/workflow-stop-hook.sh` as an executable shell script:
   - Read the active workflow ID from `.sdlc/workflows/.active`
   - If the file doesn't exist or is empty, exit 0 (allow stop — no active workflow)
   - Call `scripts/workflow-state.sh status {ID}` and parse the JSON output
   - If `status` is `"complete"` or `"paused"` → exit 0 (allow stop)
   - If `status` is `"in-progress"` with remaining steps → exit 2 with message: "Continue to step {N+1}: {step-name}" (where N is the current step number and step-name is from the state's steps array)
   - If `status` is `"failed"` → exit 0 (allow stop — user may want to investigate)
3. Add the Stop hook to the SKILL.md frontmatter:
   ```yaml
   hooks:
     Stop:
       - hooks:
           - type: command
             command: "scripts/workflow-stop-hook.sh"
   ```
4. Update the orchestrator skill (SKILL.md) to write `.sdlc/workflows/.active` at the start of:
   - New workflow initialization (after ID is assigned from step 1 artifact)
   - Resume (after reading the ID from the argument)
5. Verify Stop hook behavior:
   - Mid-chain (in-progress with remaining steps): hook blocks stop with continuation message
   - At pause point: hook allows stop
   - After completion: hook allows stop
   - After failure: hook allows stop
   - No active workflow: hook allows stop
6. Run end-to-end verification of the full feature chain:
   - Start a new workflow with a test title
   - Verify step 1 runs in main context (documenting-features)
   - Verify steps 2-3 fork correctly (reviewing-requirements, creating-implementation-plans)
   - Verify plan approval pause halts correctly and resume continues
   - Verify step 5 runs in main context (documenting-qa)
   - Verify phase loop processes all phases sequentially
   - Verify PR creation step works
   - Verify PR review pause and resume with status check
   - Verify executing-qa runs in main context
   - Verify finalize completes and marks workflow as complete

#### Deliverables
- [x] `scripts/workflow-stop-hook.sh` — executable Stop hook script
- [x] Updated `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — Stop hook in frontmatter + `.active` file tracking

---

## Shared Infrastructure

### State File Convention
All workflow state is stored in `.sdlc/workflows/{ID}.json`. The `.sdlc/` directory is gitignored — state is local to each developer's machine and not committed. The `.active` file in the same directory tracks the currently running workflow for the Stop hook.

### Forking Convention
Forked steps use a consistent pattern: read SKILL.md → spawn Agent with content as prompt + ID as argument → validate artifact → advance state. This pattern is encoded in the orchestrator's SKILL.md and does not require code changes to sub-skills.

### PR Suppression Convention
The orchestrator appends a "skip PR creation" instruction to the Agent tool prompt when forking `implementing-plan-phases`. This is a prompt-level override — the sub-skill's SKILL.md is not modified.

## Testing Strategy

### Phase 1 Testing
- Manually invoke each `workflow-state.sh` command and verify JSON output
- Test idempotency: `advance` on a completed step is a no-op; `init` on an existing ID returns current state
- Test validation: malformed IDs, missing files, corrupted JSON
- Test `phase-count` against an existing implementation plan file

### Phase 2 Testing
- Invoke `/orchestrating-workflows "test feature"` and verify step 1 runs correctly
- Verify forked steps create artifacts in expected locations
- Test pause/resume cycle manually
- Verify phase loop with a 2-phase implementation plan

### Phase 3 Testing
- Test Stop hook in each state: in-progress, paused, complete, failed, no active workflow
- Full end-to-end chain with a real (or test) feature

## Dependencies and Prerequisites

| Dependency | Status | Notes |
|-----------|--------|-------|
| Existing sub-skills (7 total) | Available | All exist under `plugins/lwndev-sdlc/skills/` |
| `gh` CLI | Required | Used for PR creation, PR status checks, issue fetching |
| `jq` | Required | Used by state script for JSON manipulation |
| Claude Code Agent tool | Available | Built-in tool for forking subagents |
| `.sdlc/` gitignore | Phase 1 | Must be added before state files are created |

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Context window exhaustion during long chains | High | Medium | Forking isolates each step; orchestrator stays lightweight |
| Sub-skill behavior changes breaking orchestrator | Medium | Low | Orchestrator reads SKILL.md dynamically; sub-skills are not modified |
| Stop hook fails to detect active workflow | Medium | Medium | `.active` file provides explicit tracking; hook falls back to allowing stop |
| `jq` not available on developer machine | Low | Low | State script can fall back to basic bash JSON or error with install guidance |
| Phase loop fails mid-way leaving partial state | Medium | Medium | Failed phases halt the loop; resume retries from the failed phase |
| PR suppression prompt override ignored by subagent | Medium | Low | Verify with testing; if unreliable, evaluate `--no-pr` flag (#94) |

## Success Criteria

- All 16 acceptance criteria from FEAT-009 requirements pass
- State script handles all 10 commands correctly and idempotently
- Feature chain runs end-to-end with correct step sequencing
- Pause points halt and resume correctly
- Stop hook prevents premature stopping during active chains
- Existing skills work normally when invoked standalone (no modifications made)
- State files are properly gitignored

## Code Organization

```
plugins/lwndev-sdlc/
└── skills/
    └── orchestrating-workflows/
        └── SKILL.md              # Phase 2: orchestrator skill

scripts/
├── workflow-state.sh             # Phase 1: state management
└── workflow-stop-hook.sh         # Phase 3: Stop hook

.sdlc/                            # gitignored
└── workflows/
    ├── .active                   # Phase 3: active workflow tracking
    ├── FEAT-009.json             # per-workflow state files
    └── CHORE-028.json
```
