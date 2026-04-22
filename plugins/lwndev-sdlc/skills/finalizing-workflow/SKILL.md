---
name: finalizing-workflow
description: Merges the current PR, checks out main, fetches, and pulls — reducing the repetitive end-of-workflow sequence to a single slash command. Use when the user says "finalize", "merge and reset", "finalize workflow", or after QA passes.
allowed-tools:
  - Bash
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

## Usage

Capture the current branch name, confirm intent with the user up-front, and then delegate the full sequence (pre-flight, bookkeeping, merge, reset) to `finalize.sh`:

1. Capture the branch: `branch=$(git branch --show-current)`.
2. Fetch the PR number and title for display: `gh pr view --json number,title`. This is for the confirmation prompt only — the real pre-flight (clean tree, PR state, mergeability) runs inside `finalize.sh`.
3. Ask the user exactly once:

   > Ready to merge PR #\<N\> ("\<title\>") and finalize the requirement document. Proceed?

4. If the user replies no / n / empty, abort before invoking the script and report `Aborted — no changes made.` Do not run `finalize.sh`.
5. On confirmation, run the script and report its stdout verbatim to the user:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/finalize.sh" "$branch"
   ```

`finalize.sh` itself does **not** prompt — the confirmation is owned entirely by this skill. The script runs unattended after confirmation.

### Expected output

On success (exit `0`), the script prints a short multi-line report: merged PR number and title, a `Bookkeeping:` summary line (ran / skipped with reason), an optional `Pushed bookkeeping commit as <sha>` line when the requirement doc was updated, and a final `On main, up to date` line. Surface this stdout verbatim.

On non-zero exit, `finalize.sh` emits a single `[error]` (or `[warn]`) line on stderr describing the failure (pre-flight abort, push failure, merge failure, etc.). Surface that stderr verbatim to the user — it is the sole error surface.

## Relationship to Other Skills

This skill is the terminal step in all workflow chains. Reconciliation steps are optional but recommended.

```
Features: ... → implementing-plan-phases → PR review → reviewing-requirements → executing-qa → finalizing-workflow
Chores:   ... → executing-chores   → PR review → reviewing-requirements → executing-qa → finalizing-workflow
Bugs:     ... → executing-bug-fixes → PR review → reviewing-requirements → executing-qa → finalizing-workflow
```

| Task | Recommended Approach |
|------|---------------------|
| Document requirements | Use `documenting-features`, `documenting-chores`, or `documenting-bugs` |
| Review requirements | Use `reviewing-requirements` |
| Build QA test plan | Use `documenting-qa` |
| Reconcile after QA plan creation | Use `reviewing-requirements` — test-plan reconciliation mode (optional but recommended) |
| Create implementation plan | Use `creating-implementation-plans` |
| Implement the plan | Use `implementing-plan-phases` |
| Execute chore or bug fix | Use `executing-chores` or `executing-bug-fixes` |
| Reconcile after PR review | Use `reviewing-requirements` — code-review reconciliation mode (optional but recommended) |
| Execute QA verification | Use `executing-qa` |
| **Merge PR and reset to main (and finalize requirement doc)** | **Use this skill (`finalizing-workflow`)** |
