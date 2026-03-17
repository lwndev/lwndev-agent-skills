# Workflow Details

Detailed guidance for each phase of the bug fix execution workflow.

## Table of Contents

- [Phase 1: Initialization](#phase-1-initialization)
- [Phase 2: Execution](#phase-2-execution)
- [Phase 3: Completion](#phase-3-completion)
- [Error Recovery](#error-recovery)
- [Common Git Commands](#common-git-commands)

---

## Phase 1: Initialization

### Step 1: Locate Bug Document

Find the bug document in `requirements/bugs/`:

```bash
# List all bug documents
ls requirements/bugs/

# View specific bug document
cat requirements/bugs/BUG-XXX-description.md
```

Extract from the document:
- **Bug ID**: Used for branch naming (e.g., `BUG-001`)
- **Severity**: Critical/High/Medium/Low — determines urgency
- **Category**: For commit message format (e.g., `runtime-error`, `logic-error`)
- **Reproduction Steps**: Must verify these no longer trigger the bug after fix
- **Root Causes**: Numbered list (RC-1, RC-2, ...) — the core of the execution workflow
- **Acceptance Criteria**: Tagged with `(RC-N)` to link back to root causes
- **GitHub Issue**: Link to update with progress (optional)

### Step 2: Redeclare Root Causes

Load the root causes from the bug document into the todo list as trackable work items:

```
Example bug document root causes:
1. RC-1: Null check missing in user profile lookup
2. RC-2: Error handler swallows exception without logging

Redeclare as work items:
- [ ] RC-1: Fix null check in user profile lookup
- [ ] RC-2: Fix error handler to log exceptions
```

This ensures every root cause is explicitly tracked and none are missed during execution.

### Step 3: Check GitHub Issue

If the bug document links to a GitHub issue:

```bash
# View issue details
gh issue view <ISSUE_NUM>

# Post starting comment (see github-templates.md)
gh issue comment <ISSUE_NUM> --body "..."
```

If no issue exists, you may:
- Proceed without GitHub issue tracking
- Create a new issue (with user confirmation)

### Step 4: Create Git Branch

Ensure clean working directory:

```bash
# Check for uncommitted changes
git status

# If changes exist, stash them
git stash
```

Create and switch to bug fix branch:

```bash
# Create branch from main/master
git checkout -b fix/BUG-XXX-description

# Example
git checkout -b fix/BUG-001-null-pointer-crash
```

---

## Phase 2: Execution

### Step 5: Load Acceptance Criteria

Convert acceptance criteria from the bug document into todos, grouped by root cause:

Example bug document criteria:
```markdown
## Acceptance Criteria
- [ ] Null check added before profile lookup (RC-1)
- [ ] Profile lookup returns default for missing users (RC-1)
- [ ] Error handler logs exception with stack trace (RC-2)
- [ ] Error handler re-throws after logging (RC-2)
```

Load these into the todo list grouped by root cause, and work through each RC sequentially.

### Step 6: Address Each Root Cause

For each root cause (RC-1, RC-2, ...):

1. Mark the RC as `in_progress`
2. **Investigate**: Understand the specific code paths involved
3. **Implement**: Make the fix for that root cause
4. **Verify**: Confirm the `(RC-N)` tagged acceptance criteria pass
5. Mark the RC as `completed`
6. Move to the next root cause

**Important:** Address root causes one at a time. Complete and verify each before moving to the next to maintain traceability.

### Step 7: Verify Reproduction Steps

After all root causes are addressed, verify the reproduction steps from the bug document no longer trigger the bug:

1. Follow the exact reproduction steps documented in the bug report
2. Confirm the bug behavior no longer occurs
3. If the bug can still be reproduced, investigate whether a root cause was missed

### Step 8: Commit Changes

Commit with proper format:

```bash
git add <files>
git commit -m "fix(category): brief description"
```

**Commit message guidelines:**
- Use the category from the bug document
- Keep the message under 72 characters
- Be specific about what was fixed

**Examples by category:**

| Category | Example Commit Message |
|----------|----------------------|
| runtime-error | `fix(runtime-error): handle null user in profile lookup` |
| logic-error | `fix(logic-error): correct discount calculation for bulk orders` |
| ui-defect | `fix(ui-defect): fix modal overlay z-index stacking` |
| performance | `fix(performance): add index for slow user query` |
| security | `fix(security): sanitize user input in search endpoint` |
| regression | `fix(regression): restore pagination after list refactor` |

**Multiple commits:** For multi-root-cause fixes, consider one commit per root cause for clearer history.

---

## Phase 3: Completion

### Step 9: Verify All Root Causes Addressed

Review each root cause from the bug document:

```markdown
## Root Causes
- [x] RC-1: Null check missing — FIXED
- [x] RC-2: Error handler swallows exception — FIXED
```

If any root cause cannot be fully addressed:
- Document the blocker
- Decide whether to proceed with partial fix or resolve first
- If proceeding partially, note this in the PR description

### Step 10: Run Tests/Build

```bash
# Run tests (if applicable)
npm test

# Run build
npm run build

# Run linting (if applicable)
npm run lint
```

All checks must pass before creating PR.

### Step 11: Create Pull Request

Push branch and create PR:

```bash
# Push branch to remote
git push -u origin fix/BUG-XXX-description

# Create PR (see github-templates.md for body format)
gh pr create --title "fix(category): description" --body "..."
```

Use the PR template from [assets/pr-template.md](../assets/pr-template.md).

**Important:** The PR body MUST include `Closes #N` if the bug document links to a GitHub issue. This auto-closes the issue when the PR is merged.

### Step 12: Update Bug Document

Update the bug document's completion section:

```markdown
## Resolution
- **Status:** Completed
- **Date:** YYYY-MM-DD
- **PR:** #<PR_NUM>
```

### Step 13: Update GitHub Issue

If a GitHub issue is linked:

```bash
gh issue comment <ISSUE_NUM> --body "✅ Work complete for BUG-XXX

PR created: #<PR_NUM>

All root causes addressed and verified."
```

---

## Error Recovery

### Dirty Working Directory

If you have uncommitted changes before starting:

```bash
# Option 1: Stash changes
git stash
git checkout -b fix/BUG-XXX-description
# Later: git stash pop

# Option 2: Commit current work first
git add .
git commit -m "wip: current work"
git checkout -b fix/BUG-XXX-description
```

### Branch Already Exists

```bash
# Check if branch exists
git branch --list "fix/BUG-XXX*"

# Option 1: Switch to existing branch
git checkout fix/BUG-XXX-description

# Option 2: Delete and recreate
git branch -D fix/BUG-XXX-description
git checkout -b fix/BUG-XXX-description
```

### Tests Failing

1. Review test output for failures
2. Fix issues related to your changes
3. Re-run tests until passing
4. If failures are unrelated to your changes, document and decide whether to fix or proceed

### PR Already Exists

```bash
# Check for existing PRs
gh pr list --head "fix/BUG-XXX-description"

# Update existing PR with new commits
git push origin fix/BUG-XXX-description

# Or update PR body
gh pr edit <PR_NUM> --body "..."
```

### GitHub CLI Not Available

If `gh` is not installed or authenticated:

1. Create PR through GitHub web interface
2. Manually post issue comments through web interface
3. Consider installing `gh` for future work: `brew install gh`

### New Root Cause Discovered

If a new root cause is discovered during execution:

1. Add the new root cause to the bug document as a new `RC-N` entry
2. Add corresponding acceptance criteria with the `(RC-N)` tag
3. Add the new RC to the todo list
4. Address it as part of the current fix
5. Include it in the PR's root cause traceability table

### Root Cause Cannot Be Fully Addressed

If a root cause cannot be fully resolved in this fix:

1. Document the limitation in the PR description
2. Note which acceptance criteria for that RC are partially met
3. Create a follow-up issue for the remaining work
4. Reference the follow-up issue in the PR's Related section

---

## Common Git Commands

### Status and History

```bash
# Check current status
git status

# View recent commits
git log --oneline -10

# View changes in current branch
git diff main...HEAD
```

### Branch Management

```bash
# List branches
git branch

# Switch branches
git checkout <branch-name>

# Delete local branch
git branch -d <branch-name>
```

### Committing

```bash
# Stage specific files
git add file1.ts file2.ts

# Stage all changes
git add .

# Commit with message
git commit -m "fix(category): description"

# Amend last commit (before push)
git commit --amend
```

### Remote Operations

```bash
# Push new branch
git push -u origin <branch-name>

# Push updates
git push

# Fetch latest from remote
git fetch origin
```
