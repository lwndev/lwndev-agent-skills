# Step-by-Step Implementation Details

Detailed guidance for each step in the phase implementation workflow. Script paths are relative to `${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/` and abbreviated `$SCRIPTS/` below.

## Table of Contents

- [Step 1: Locate the Implementation Plan](#step-1-locate-the-implementation-plan)
- [Step 2: Identify Target Phase](#step-2-identify-target-phase)
- [Step 3: Update Implementation Doc Status](#step-3-update-implementation-doc-status)
- [Step 4: Branch Strategy](#step-4-branch-strategy)
- [Step 5: Load Steps into Todos](#step-5-load-steps-into-todos)
- [Step 6: Execute Implementation](#step-6-execute-implementation)
- [Step 7: Verify Deliverables](#step-7-verify-deliverables)
- [Step 8: Commit and Push Changes](#step-8-commit-and-push-changes)
- [Step 9: Update Plan Status](#step-9-update-plan-status)
- [Step 10: Create Pull Request (All Phases Complete)](#step-10-create-pull-request-all-phases-complete)
- [Common Patterns](#common-patterns)

> **Note:** Issue tracking (start/completion comments) is handled by the orchestrator via `managing-work-items`. This reference document focuses on the implementation steps only.

---

## Step 1: Locate the Implementation Plan

Find the relevant implementation plan:

```bash
ls requirements/implementation/
```

Read the plan file to understand:
- Phase structure and dependencies
- Implementation steps for each phase
- Deliverables checklist
- Shared infrastructure references

## Step 2: Identify Target Phase

When the user specified a phase, use it directly. Otherwise run `next-pending-phase.sh` — it parses the plan's `### Phase N: <name>` headings and `**Status:**` lines (fence-aware) and applies a two-tier selection rule (sequential ordering + explicit `**Depends on:** Phase <N>` lines).

```bash
bash "$SCRIPTS/next-pending-phase.sh" "<plan-path>"
```

Dispatch on the JSON stdout:
- `{"phase":<N>,"name":"..."}` — implement that phase.
- `{"phase":<N>,"name":"...","reason":"resume-in-progress"}` — a phase is already `🔄 In Progress`; resume it rather than starting a new one.
- `{"phase":null,"reason":"all-complete"}` — every phase is `✅ Complete`; proceed to Step 10.
- `{"phase":null,"reason":"blocked","blockedOn":[<N>,...]}` — a pending phase exists but its prerequisites are not complete; halt and surface the blocker.

Exit `0` on every shape above. Exit `1` on missing plan, no `### Phase` blocks, or a phase block with no `**Status:**` line. Exit `2` on missing arg.

Extract any issue metadata (`[#N]`) and feature-link from the phase heading yourself once the target phase is selected.

## Step 3: Update Implementation Doc Status

Transition the selected phase to `🔄 In Progress` via `plan-status-marker.sh`:

```bash
bash "$SCRIPTS/plan-status-marker.sh" "<plan-path>" <phase-N> in-progress
```

Canonical state tokens: `Pending`, `in-progress` (writes `🔄 In Progress`), `complete` (writes `✅ Complete`). Script is fence-aware, CRLF-safe, and idempotent: stdout `transitioned` on a real write, `already set` when the line already matches. Exit `1` on missing plan, no matching phase block, or no `**Status:**` line. Exit `2` on malformed args.

Scope is bounded to the target `### Phase <N>:` block — sibling phases are never touched.

## Step 4: Branch Strategy

Create a feature branch following the naming convention:

```bash
git checkout -b feat/{Feature ID}-{2-3-word-summary}
```

Assemble the name via `build-branch-name.sh` and create/switch with `ensure-branch.sh`:

```bash
branch=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-branch-name.sh" feat "<FEAT-NNN>" "<summary>")
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-branch.sh" "$branch"
```

**Naming guidelines:**
- Use `feat/` prefix for feature work
- Add 2-3 word description (kebab-case)

**Examples:**
- `feat/FEAT-001-scaffold-skill-command`
- `feat/FEAT-002-validate-skill-command`
- `feat/FEAT-007-chore-task-skill`

**If already on a feature branch:** Stay on current branch if it's the correct one for this phase sequence.

## Step 5: Load Steps into Todos

Use TodoWrite to create trackable tasks for each implementation step.

**Include:**
- Each numbered step from "Implementation Steps"
- Deliverable verification as final step

**Example:**
```json
[
  {"content": "Create file-exists validator", "status": "pending"},
  {"content": "Create required-fields validator", "status": "pending"},
  {"content": "Create validation orchestrator", "status": "pending"},
  {"content": "Write file-exists tests", "status": "pending"},
  {"content": "Write required-fields tests", "status": "pending"},
  {"content": "Write orchestrator tests", "status": "pending"},
  {"content": "Verify all deliverables", "status": "pending"}
]
```

## Step 6: Execute Implementation

For each implementation step:

1. **Mark in_progress:** Update todo status before starting
2. **Implement:** Write the code/tests
3. **Follow patterns:** Reference existing code style and architecture
4. **Use shared infrastructure:** Check plan's "Shared Infrastructure" section
5. **Check off the deliverable in the implementation plan** via `check-deliverable.sh` (see below) — run it as each deliverable completes, not in a batch at the end
6. **Mark completed:** Update todo when step is done

**Keep exactly ONE todo in_progress at a time.**

### Checking Off Deliverables

```bash
bash "$SCRIPTS/check-deliverable.sh" "<plan-path>" <phase-N> "<idx-or-text>"
```

Dispatches on the third arg: digits → 1-based index into the phase's deliverable lines (in document order, counting both `- [ ]` and `- [x]`); any non-digit → literal substring matcher (identical semantics to the plugin-shared `check-acceptance.sh`). Phase-scoped — matches only within the target `### Phase <N>:` block. Fence-aware — `- [ ]` lines inside fenced code blocks are never flipped.

Exit-code shape (matches `check-acceptance.sh`):
- `0` — line flipped to `- [x]`, stdout `checked`; or the line was already `- [x]`, stdout `already checked` (idempotent).
- `1` — deliverable not found, out-of-range index, missing plan, or missing phase block.
- `2` — ambiguous substring (multiple `- [ ]` lines match; `- [x]` matches are ignored for ambiguity).
- `3` — missing or malformed arg.

### Following Code Organization

Implementation plans include a "Code Organization" section showing where files should be created:

```
src/
├── generators/
│   └── validate.ts           # Phase 2
├── validators/
│   ├── file-exists.ts        # Phase 2
│   └── required-fields.ts    # Phase 2
```

Follow this structure exactly for consistency.

### Reusing Existing Code

Check the phase "Rationale" section for references to existing utilities:

```markdown
**Leverages existing code**: Reuses `validateName`, `validateDescription`,
and `validateFrontmatterKeys` from scaffold implementation
```

Import and integrate rather than rewriting:

```typescript
import { validateName } from './name';
import { validateDescription } from './description';
```

### Test-Driven Development

Write tests alongside implementation:
- Unit tests for individual functions
- Integration tests for workflows
- Create test fixtures as needed

Reference the plan's test organization structure for file placement.

## Step 7: Verify Deliverables

Run `verify-phase-deliverables.sh` — one call replaces the old `npm test` + `npm run build` + `npm run test:coverage` + per-file `ls` sequence:

```bash
bash "$SCRIPTS/verify-phase-deliverables.sh" "<plan-path>" <phase-N>
```

The script parses the phase's `#### Deliverables` subsection, extracts backticked paths from both `- [ ]` and `- [x]` lines, and checks each file exists. It then runs `npm test` and `npm run build` sequentially (fail-fast: the first failing check short-circuits), and runs `npm run test:coverage` only when the plan mentions `coverage` or a `[0-9]+%` threshold. Non-file deliverable lines (no leading backtick) are skipped from the file-existence check.

JSON stdout shape:

```json
{
  "files": { "ok": ["..."], "missing": [] },
  "test": "pass|fail|skipped",
  "build": "pass|fail|skipped",
  "coverage": "pass|fail|skipped",
  "output": { "test": "<last 50 lines>", "build": "..." }
}
```

`output` keys appear only for failing checks.

Aggregate exit code: `0` only when `files.missing` is empty AND each of `test`/`build`/`coverage` is `pass` or `skipped`. Otherwise `1`. Missing args → `2`.

**Graceful degradation.** If `npm` is not on `PATH`, the script emits `[warn] verify-phase-deliverables: npm not found; skipping test/build/coverage checks.` to stderr and reports all three as `skipped`. Exit `0` when all deliverable files exist.

## Step 8: Commit and Push Changes

**Always commit and push after verification — do not ask the user for confirmation.** This is a mandatory step, not an optional one. One script handles stage, commit, and push:

```bash
bash "$SCRIPTS/commit-and-push-phase.sh" "<FEAT-NNN>" <phase-N> "<phase-name>"
```

The script:
1. Runs `git status --porcelain=v1` — empty output → stderr `error: no changes to commit`, exit `1`.
2. Stages with `git add -A`. On failure → stderr `[error] git add failed`, exit `1`.
3. Commits with the canonical message `<type>(<ID>): complete phase <N> - <phase-name>`. Type prefix is derived from the ID: `FEAT-` → `feat`, `CHORE-` → `chore`, `BUG-` → `fix`.
4. Determines current branch via `git rev-parse --abbrev-ref HEAD`.
5. Checks upstream via `git rev-parse --abbrev-ref --symbolic-full-name @{u}`; pushes with `git push -u origin <branch>` on first push, bare `git push` thereafter.
6. On success: stdout `pushed <branch>`, exit `0`.
7. On push failure: `git push` stderr is surfaced verbatim, followed by `[error] push failed; see Push Failure Recovery in SKILL.md`, exit `1`.

**Canonical message examples:**
- `feat(FEAT-001): complete phase 1 - yaml parsing infrastructure`
- `chore(CHORE-003): complete phase 2 - update deps`
- `fix(BUG-012): complete phase 3 - fix null check`

**Arg validation.** Exit `2` on: malformed ID (not matching `^(FEAT|CHORE|BUG)-[0-9]+$`), non-positive `<phase-N>`, or empty/whitespace-only `<phase-name>`.

### Push Failure Recovery

If the push fails, diagnose and resolve before proceeding.

**Network / authentication errors:**

```bash
git remote -v
git push
```

If authentication has expired, re-authenticate (e.g. `gh auth login`) and retry `git push` directly.

**Rejected push (remote has new commits):**

```bash
git fetch origin
git rebase origin/<branch-name>
# resolve conflicts if any
git push
```

**Important:** Do not proceed to Step 9 (Update Plan Status) until the push succeeds. The commit is local-only until pushed, and subsequent phases or collaborators will not see the work.

**Do not re-run `commit-and-push-phase.sh` after resolving a rejected push.** The script's first step is `git status --porcelain=v1`; once the rebase is in place the working tree is clean, so the sanity gate reports `error: no changes to commit` and exits `1`, masking the successful recovery. The commit already exists locally (it is what you just rebased) — a raw `git push` is the correct retry.

---

## Step 9: Update Plan Status

**Prerequisite:** Step 8 commit and push must have succeeded before updating status. Do not mark a phase complete if changes are uncommitted or unpushed.

Transition to `✅ Complete` via the same `plan-status-marker.sh` used in Step 3, with the `complete` token:

```bash
bash "$SCRIPTS/plan-status-marker.sh" "<plan-path>" <phase-N> complete
```

Stdout `transitioned` on a real write, `already set` if the phase is already `✅ Complete` (idempotent). Exit `1` on missing plan, no matching phase block, or no `**Status:**` line.

Confirm that all deliverable checkboxes were flipped during Step 6. If any were missed, run `check-deliverable.sh` for each now as a final catch.

## Step 10: Create Pull Request (All Phases Complete)

After all phases in the implementation plan are marked **✅ Complete**, create a pull request to merge the feature branch.

**This step only runs once — after the final phase is complete**, not after each individual phase.

### Check All Phases Are Complete

Before creating the PR, gate on `verify-all-phases-complete.sh`:

```bash
bash "$SCRIPTS/verify-all-phases-complete.sh" "<plan-path>"
```

Exit `0` with stdout `all phases complete` when every phase is `✅ Complete`. Otherwise exit `1` with JSON `{"incomplete":[{"phase":<N>,"name":"...","status":"Pending|in-progress"},...]}` on stdout — finish the listed phases before proceeding. Exit `1` with stderr `[error] no phase blocks found in plan` (no JSON) when the plan has no `### Phase` blocks. The script is fence-aware; `**Status:**` lines inside fenced blocks are ignored.

### Create the Pull Request

Use the PR template from [assets/pr-template.md](../assets/pr-template.md):

```bash
gh pr create --title "feat(FEAT-XXX): <feature summary>" --body "..."
```

**Important:** If the implementation plan links to a GitHub issue, you MUST include `Closes #N` in the Related section. This auto-closes the issue when the PR is merged.

### PR Title Format

```
feat(FEAT-XXX): <feature summary>
```

**Examples:**
- `feat(FEAT-001): add scaffold skill command`
- `feat(FEAT-002): add validation engine`
- `feat(FEAT-007): add chore task skill`

---

## Common Patterns

### Handling Test Fixtures

Create test fixtures in the structure specified by the plan:

```
tests/
└── fixtures/
    └── skills/
        ├── valid-skill/
        │   └── SKILL.md
        ├── missing-name/
        │   └── SKILL.md
        └── invalid-yaml/
            └── SKILL.md
```

Each fixture should represent a specific test case.

### Dependencies and Prerequisites

Implementation plans include a "Dependencies and Prerequisites" section:

```markdown
## Dependencies and Prerequisites

- Node.js 18+ with npm
- TypeScript 5.5+
- Jest testing framework
- Phase 1 must be complete before Phase 2
```

Verify these before starting implementation.

### Shared Infrastructure

Plans may include a "Shared Infrastructure" section listing reusable components:

```markdown
## Shared Infrastructure

### Validators (from Phase 2)
- `validateName(name: string)` - Name format validation
- `validateDescription(desc: string)` - Description validation

### Types (from Phase 1)
- `ValidationResult` - Standard validation result format
- `FrontmatterData` - Parsed frontmatter structure
```

Reference these rather than duplicating logic.
