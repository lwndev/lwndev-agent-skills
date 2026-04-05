# Workflow Details

Detailed guidance for each phase of the chore execution workflow.

## Table of Contents

- [Phase 1: Initialization](#phase-1-initialization)
- [Phase 2: Execution](#phase-2-execution)
- [Phase 3: Completion](#phase-3-completion)
- [Error Recovery](#error-recovery)
- [Common Git Commands](#common-git-commands)

> **Note:** Issue tracking (start/completion comments) is handled by the orchestrator via `managing-work-items`. This reference document focuses on chore execution steps only.

---

## Phase 1: Initialization

### Step 1: Locate Chore Document

Find the chore document in `requirements/chores/`:

```bash
# List all chore documents
ls requirements/chores/

# View specific chore document
cat requirements/chores/CHORE-XXX-description.md
```

Extract from the document:
- **Chore ID**: Used for branch naming (e.g., `CHORE-001`)
- **Category**: For commit message format
- **Acceptance Criteria**: Load into todos

### Step 2: Create Git Branch

Ensure clean working directory:

```bash
# Check for uncommitted changes
git status

# If changes exist, stash them
git stash
```

Create and switch to chore branch:

```bash
# Create branch from main/master
git checkout -b chore/CHORE-XXX-description

# Example
git checkout -b chore/CHORE-001-update-dependencies
```

---

## Phase 2: Execution

### Step 3: Load Acceptance Criteria

Convert acceptance criteria from the chore document into todos:

Example chore document criteria:
```markdown
## Acceptance Criteria
- [ ] All npm packages updated to latest compatible versions
- [ ] No security vulnerabilities remain
- [ ] Build passes after updates
```

Load these directly into the todo list and mark as in_progress as you work through each.

### Step 4: Execute Changes

Work through each acceptance criterion:

1. Mark current task as `in_progress`
2. Make the necessary changes
3. Test locally if applicable
4. **Check off the criterion in the chore document** — edit the source file to change `- [ ]` to `- [x]` for the criterion you just verified
5. Mark task as `completed`
6. Move to next criterion

**Important:** Update the chore document checkbox at the point each criterion is verified, not in a batch at the end. This provides real-time progress visibility in the source document.

### Step 5: Commit Changes

Commit with proper format:

```bash
git add <files>
git commit -m "chore(category): brief description"
```

**Commit message guidelines:**
- Use the category from the chore document
- Keep the message under 72 characters
- Be specific about what changed

**Examples by category:**

| Category | Example Commit Message |
|----------|----------------------|
| dependencies | `chore(dependencies): update typescript to 5.5.4` |
| documentation | `chore(documentation): fix broken links in README` |
| refactoring | `chore(refactoring): extract validation into utility` |
| configuration | `chore(configuration): add eslint rule for imports` |
| cleanup | `chore(cleanup): remove deprecated API handlers` |

**Multiple commits:** For larger chores, use multiple commits with related changes grouped together.

---

## Phase 3: Completion

### Step 6: Verify Acceptance Criteria

Confirm that all acceptance criteria in the chore document have been checked off (`- [x]`) during Step 4. Each checkbox should already be marked — this step is a final review to catch any that were missed.

If any criteria cannot be met:
- Document the blocker
- Decide whether to proceed with partial completion or resolve first

### Step 7: Run Tests/Build

```bash
# Run tests (if applicable)
npm test

# Run build
npm run build

# Run linting (if applicable)
npm run lint
```

All checks must pass before creating PR.

### Step 8: Create Pull Request

Push branch and create PR:

```bash
# Push branch to remote
git push -u origin chore/CHORE-XXX-description

# Create PR
gh pr create --title "chore(category): description" --body "..."
```

Use the PR template from [assets/pr-template.md](../assets/pr-template.md).

**Important:** The PR body MUST include `Closes #N` if the chore document links to a GitHub issue. This auto-closes the issue when the PR is merged.

---

## Error Recovery

### Dirty Working Directory

If you have uncommitted changes before starting:

```bash
# Option 1: Stash changes
git stash
git checkout -b chore/CHORE-XXX-description
# Later: git stash pop

# Option 2: Commit current work first
git add .
git commit -m "wip: current work"
git checkout -b chore/CHORE-XXX-description
```

### Branch Already Exists

```bash
# Check if branch exists
git branch --list "chore/CHORE-XXX*"

# Option 1: Switch to existing branch
git checkout chore/CHORE-XXX-description

# Option 2: Delete and recreate
git branch -D chore/CHORE-XXX-description
git checkout -b chore/CHORE-XXX-description
```

### Tests Failing

1. Review test output for failures
2. Fix issues related to your changes
3. Re-run tests until passing
4. If failures are unrelated to your changes, document and decide whether to fix or proceed

### PR Already Exists

```bash
# Check for existing PRs
gh pr list --head "chore/CHORE-XXX-description"

# Update existing PR with new commits
git push origin chore/CHORE-XXX-description

# Or update PR body
gh pr edit <PR_NUM> --body "..."
```

### GitHub CLI Not Available

If `gh` is not installed or authenticated:

1. Create PR through GitHub web interface
2. Manually post issue comments through web interface
3. Consider installing `gh` for future chores: `brew install gh`

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
git commit -m "chore(category): description"

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
