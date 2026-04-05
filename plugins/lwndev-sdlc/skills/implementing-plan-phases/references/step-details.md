# Step-by-Step Implementation Details

Detailed guidance for each step in the phase implementation workflow.

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

Determine which phase to implement:

**User-specified:** User says "implement phase 2" → use Phase 2

**Auto-select:** Find the first phase with **Status: Pending** that has all prerequisites complete

**Verify prerequisites:**
- Check all prior phases show **Status: ✅ Complete**
- Verify deliverables from dependent phases exist

**Extract metadata:**
- GitHub issue number from phase header: `[#N]`
- Feature reference link
- Rationale for phase ordering

## Step 3: Update Implementation Doc Status

Update the phase status in the implementation plan to indicate work has started.

**Change:**
```markdown
**Status:** Pending
```

**To:**
```markdown
**Status:** 🔄 In Progress
```

**Example edit:**
```markdown
### Phase 2: Validation Engine
**Feature:** [FEAT-002](../features/02-validate-skill-command.md) | [#2](https://github.com/...)
**Status:** 🔄 In Progress
```

This provides visibility into current work across the team.

## Step 4: Branch Strategy

Create a feature branch following the naming convention:

```bash
git checkout -b feat/{Feature ID}-{2-3-word-summary}
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
5. **Check off the deliverable in the implementation plan** — edit the plan file to change `- [ ]` to `- [x]` for each deliverable as it is completed
6. **Mark completed:** Update todo when step is done

**Important:** Update the implementation plan deliverable checkbox at the point each deliverable is completed, not in a batch at the end. This provides real-time progress visibility in the plan document.

**Keep exactly ONE todo in_progress at a time.**

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

Before marking phase complete, verify all requirements:

### Run Tests

```bash
npm test
```

All tests must pass. If any fail, fix before proceeding.

### Build Project

```bash
npm run build
```

Build must succeed without errors or warnings.

### Check Coverage

```bash
npm run test:coverage
```

Verify coverage meets the threshold specified in the plan (typically 80%+).

### Verify Files Exist

Check each deliverable from the plan exists and is complete:

```bash
ls -la src/validators/file-exists.ts
ls -la tests/unit/validators/file-exists.test.ts
# ... etc for all deliverables
```

## Step 8: Commit and Push Changes

**Always commit and push after verification — do not ask the user for confirmation.** This is a mandatory step, not an optional one. Commit all changes and push to the remote. This preserves a per-phase audit trail in git and ensures work is not lost between phases.

### Stage Changed Files

Stage all files that were created or modified during this phase:

```bash
# Stage specific deliverable files
git add src/validators/file-exists.ts src/validators/required-fields.ts ...

# Or stage all changes if all modifications are phase-related
git add .
```

Review what will be committed before proceeding:

```bash
git status
```

### Commit with Phase-Traceable Message

Use a commit message that includes the Feature ID, phase number, and phase name:

```bash
git commit -m "feat(FEAT-XXX): complete phase N - <phase name>"
```

**Format:** `feat(<Feature ID>): complete phase <N> - <phase name>`

**Examples:**
- `feat(FEAT-001): complete phase 1 - yaml parsing infrastructure`
- `feat(FEAT-002): complete phase 2 - validation engine`
- `feat(FEAT-007): complete phase 3 - chore execution workflow`

### Push to Remote

Push the feature branch to the remote. Use `-u` on the first push to set upstream tracking:

```bash
# First push for this branch
git push -u origin feat/FEAT-XXX-summary

# Subsequent pushes (upstream already set)
git push
```

If the branch was already pushed in a prior phase, a simple `git push` is sufficient.

### Push Failure Recovery

If the push fails, diagnose and resolve before proceeding:

**Network / authentication errors:**
```bash
# Verify remote is reachable
git remote -v

# Retry the push
git push
```

If authentication has expired, re-authenticate (e.g., `gh auth login`) and retry.

**Rejected push (remote has new commits):**
```bash
# Fetch and rebase onto the latest remote
git fetch origin
git rebase origin/<branch-name>

# Resolve any conflicts, then push
git push
```

**Important:** Do not proceed to Step 10 (Update Plan Status) until the push succeeds. The commit is local-only until pushed, and subsequent phases or collaborators will not see the work.

---

## Step 9: Update Plan Status

**Prerequisite:** Step 8 commit and push must have succeeded before updating status. Do not mark a phase complete if changes are uncommitted or unpushed.

Edit the implementation plan file to mark the phase complete:

**Change:**
```markdown
**Status:** 🔄 In Progress
```

**To:**
```markdown
**Status:** ✅ Complete
```

Confirm that all deliverable checkboxes have already been checked off (`- [x]`) during Step 6. If any were missed, check them off now as a final catch.

## Step 10: Create Pull Request (All Phases Complete)

After all phases in the implementation plan are marked **✅ Complete**, create a pull request to merge the feature branch.

**This step only runs once — after the final phase is complete**, not after each individual phase.

### Check All Phases Are Complete

Before creating the PR, verify every phase in the plan shows **Status: ✅ Complete**:

```bash
# Search for any phases that are not complete
grep "**Status:**" requirements/implementation/<plan-file>.md
```

If any phase is still Pending or 🔄 In Progress, complete it before proceeding.

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
