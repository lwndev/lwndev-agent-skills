---
name: finalizing-workflow
description: Merges the current PR, checks out main, fetches, and pulls — reducing the repetitive end-of-workflow sequence to a single slash command. Use when the user says "finalize", "merge and reset", "finalize workflow", or after QA passes.
allowed-tools:
  - Bash
  - Read
  - Glob
---

# Finalizing Workflow

Merge the current PR and reset to main in a single invocation. This is the terminal step in all three SDLC workflow chains.

## When to Use This Skill

- User says "finalize", "finalize workflow", "merge and reset", or "wrap up"
- After QA verification passes and the PR is ready to merge
- User wants to merge the current branch's PR and return to main

## Workflow Position

```
Features: ... → implementing-plan-phases → executing-qa → finalizing-workflow
Chores:   ... → executing-chores        → executing-qa → finalizing-workflow
Bugs:     ... → executing-bug-fixes     → executing-qa → finalizing-workflow
```

## Pre-Flight Checks

Before executing, verify all of the following. If any check fails, stop and report the issue to the user.

### 1. Clean Working Directory

```bash
git status --porcelain
```

If there are uncommitted changes, stop and ask the user to commit or stash them first. Do not proceed with a dirty working directory.

### 2. Identify Current Branch

```bash
git branch --show-current
```

If on `main` or `master`, stop — there is nothing to finalize.

### 3. Find Associated PR

```bash
gh pr view --json number,title,state,mergeable
```

If no PR exists for the current branch, stop and inform the user. If the PR is not in an `OPEN` state, stop and report the current state. If the PR is not mergeable (e.g., merge conflicts, failing checks), stop and report the reason.

## Execution

After all pre-flight checks pass, confirm intent with the user before proceeding:

> Ready to merge PR #N ("PR title") and switch to main. Proceed?

Wait for user confirmation. Once confirmed, execute the following sequence:

### Step 1: Merge the PR

```bash
gh pr merge --delete-branch
```

Use the repository's default merge strategy (no `--merge`, `--squash`, or `--rebase` flag). The `--delete-branch` flag cleans up the remote and local branch after merge. Do not force-merge or bypass required checks.

If the merge fails, stop and report the error. Do not retry automatically.

### Step 2: Switch to Main

```bash
git checkout main
```

### Step 3: Fetch and Pull

```bash
git fetch origin
git pull
```

## Completion

After all steps succeed, report:

- The PR number and title that was merged
- Confirmation that the working directory is now on `main` and up to date

## Error Handling

| Scenario | Action |
|----------|--------|
| Dirty working directory | Stop. Ask user to commit or stash changes. |
| Already on main/master | Stop. Nothing to finalize. |
| No PR for current branch | Stop. Inform user no PR was found. |
| PR not open | Stop. Report PR state (closed, merged, draft). |
| PR not mergeable | Stop. Report reason (conflicts, failing checks). |
| Merge fails | Stop. Report error. Do not retry. |
| Checkout fails | Stop. Report error. |
| Fetch/pull fails | Report error but note the merge already succeeded. |

## Relationship to Other Skills

| Task | Recommended Approach |
|------|---------------------|
| Document requirements | Use `documenting-features`, `documenting-chores`, or `documenting-bugs` |
| Review requirements | Use `reviewing-requirements` |
| Build QA test plan | Use `documenting-qa` |
| Create implementation plan | Use `creating-implementation-plans` |
| Implement the plan | Use `implementing-plan-phases` |
| Execute chore or bug fix | Use `executing-chores` or `executing-bug-fixes` |
| Execute QA verification | Use `executing-qa` |
| **Merge PR and reset to main** | **Use this skill (`finalizing-workflow`)** |
