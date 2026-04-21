---
name: finalizing-workflow
description: Merges the current PR, checks out main, fetches, and pulls — reducing the repetitive end-of-workflow sequence to a single slash command. Use when the user says "finalize", "merge and reset", "finalize workflow", or after QA passes.
allowed-tools:
  - Bash
  - Read
  - Edit
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

## Pre-Merge Bookkeeping

After all pre-flight checks pass, confirm intent with the user before proceeding:

> Ready to merge PR #N ("PR title") and finalize the requirement document. Proceed?

Wait for user confirmation. If the user declines, abort before running any bookkeeping. Bookkeeping runs once after confirmation; `## Execution` proceeds without a second prompt.

### BK-1 — Derive Work Item ID From Branch Name (FR-2)

Classify the branch name captured in Pre-Flight Check 2 with:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/branch-id-parse.sh" "<branch>"
```

The script applies the three regexes (`^feat/(FEAT-[0-9]+)-`, `^chore/(CHORE-[0-9]+)-`, `^fix/(BUG-[0-9]+)-`) and emits JSON `{"id": "...", "type": "...", "dir": "..."}` on stdout (`jq` when available; hand-assembled JSON otherwise). Exit codes: `0` on match — parse the JSON and use `id` / `dir` for BK-2; `1` on no match — skip all bookkeeping with info-level message (see Error Handling row 1) and continue to `## Execution`; `2` on missing arg.

### BK-2 — Locate the Requirement Document (FR-3)

Using the derived ID from BK-1, resolve the doc path with:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<ID>"
```

Map the script's exit codes to the existing behaviors:

- Exit `0` → exactly-one match; store the path on stdout for BK-3 and BK-4.
- Exit `1` → zero matches; skip all bookkeeping with warning (Error Handling row 2); continue to `## Execution`.
- Exit `2` → multiple matches; skip all bookkeeping with error-level warning ("workspace inconsistency — investigate"); continue to `## Execution`.
- Exit `3` → malformed/missing ID; emit a warning (BK-1 parsed a malformed ID — should not happen) and skip bookkeeping.

### BK-3 — Idempotency Check (FR-4)

Before any edits, check all three conditions. All detection uses the same line-ending- and fence-aware rules as BK-4 (see the robustness rules at the top of BK-4):

1. The `## Acceptance Criteria` section is absent, or present with zero `- [ ]` lines outside fenced code blocks.
2. A `## Completion` section exists containing `**Status:** \`Complete\`` or `**Status:** \`Completed\``.
3. A `**Pull Request:**` line within `## Completion` contains `[#N]` or `/pull/N` where N equals the current PR number (from Pre-Flight Check 3; no new `gh` call).

If all three hold → skip bookkeeping silently; proceed to `## Execution` (Error Handling row 3).
If any fails → proceed to BK-4.

### BK-4 — Four Mechanical Updates (FR-5)

**Robustness rules that apply to every sub-step below:**

- **Line-ending agnostic**: match section headings with `\r?\n` (not literal `\n`). A doc with CRLF endings (Windows editors, `core.autocrlf=true`) MUST be detected and edited correctly. If in doubt, normalize on read and restore the original ending on write.
- **Fenced-code-block aware**: a fenced code block opens with a line starting with ` ``` ` and closes at the next such line. Section-heading detection MUST skip over fenced blocks — a `## Something` line inside a fence is documentation content, not a real heading. Checkbox and path scans inside section bodies MUST also skip over fenced content so that illustrative examples (`- [ ]` sample items, example Affected Files lists) are never modified.

Execute the following sub-steps in order:

**BK-4.1 (FR-5.1): Acceptance Criteria Checkoff** — Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/checkbox-flip-all.sh" "<resolved-doc-path>" "Acceptance Criteria"
```

The script locates the `## Acceptance Criteria` heading, walks the section body to the next `## ` heading (fence-aware — `## Something` inside a fenced block is skipped), flips every `- [ ]` outside fenced blocks to `- [x]`, and prints `checked N lines` to stdout. Exit codes: `0` always on success; the `checked 0 lines` output is idempotent (a re-run after all boxes are already ticked emits `checked 0 lines` and exits `0`). Exit `1` means the section is absent — skip silently per the prior behavior. Exit `2` on missing arg. If a single criterion needs flipping (rather than the whole section), use `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-acceptance.sh" "<doc>" "<matcher>"` (literal substring match, fence-aware; exit `0` on `checked`/`already checked`, `1` on not-found, `2` on ambiguous, `3` on missing arg).

**BK-4.2 (FR-5.2): Completion Section Upsert** — Construct the block below. If `## Completion` exists, replace its body in place (heading preserved, all sub-sections replaced). If absent, append (preceded by a blank line) at end of doc.

```
## Completion

**Status:** `Complete`

**Completed:** YYYY-MM-DD

**Pull Request:** [#N](https://github.com/{owner}/{repo}/pull/N)
```

Date: `date -u +%Y-%m-%d`. PR number and URL: `gh pr view --json number,url --jq '{number: .number, url: .url}'`. On `gh` failure: omit the `**Pull Request:**` line; write Status + date only; log a warning.

**BK-4.3 (FR-5.3): Affected Files Reconciliation** — Fetch PR files: `gh pr view {N} --json files --jq '.files[].path' | sort`. If `## Affected Files` section is absent → skip silently. If present: files in PR but not in doc → append as `` - `path` `` bullets; files in doc not in PR → annotate `(planned but not modified)` (idempotent — skip if already present); files in both → leave unchanged. On `gh` failure → skip sub-step; log warning.

**BK-4.4 (FR-5.4):** Satisfied by BK-4.2 (the `**Pull Request:**` line). No additional edit required.

### BK-5 — Bookkeeping Commit and Push (FR-6)

Run `git status --porcelain`. If no changes → skip commit and push; proceed to `## Execution`.

If changes exist → stage only the requirement doc (`git add {resolved-path}`), commit with:

```
chore({ID}): finalize requirement document

- Tick completed acceptance criteria
- Set completion status with PR link
- Reconcile affected files against PR diff
```

Then `git push`. This is a new commit only (no amend, no force-push). Git author identity uses whatever `git config user.name`/`user.email` are set; if identity not configured, stop and report — do not auto-configure.

If `git add` fails, stop and report — treat as a non-recoverable error.
If push fails → stop and report; do not proceed to `## Execution` (Error Handling row 4).

## Execution

Once bookkeeping is complete (or skipped), execute the following sequence without a second confirmation prompt:

### Step 1: Merge the PR

```bash
gh pr merge --merge --delete-branch
```

The `--merge` flag is required because `gh` does not auto-detect the repository's default merge strategy when running non-interactively. The `--delete-branch` flag cleans up the remote and local branch after merge. Do not force-merge or bypass required checks.

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
| Branch name does not match workflow ID pattern (`feat/`, `chore/`, `fix/`) | Skip bookkeeping. Emit info-level message: `[info] Branch {name} does not match workflow ID pattern; skipping bookkeeping.` Continue to merge. |
| Requirement doc not found for derived ID | Skip bookkeeping. Emit warning-level message: `[warn] No requirement doc found for {ID} under {directory}; skipping bookkeeping.` Continue to merge. |
| Requirement doc already finalized (FR-4 idempotency check passes) | Skip bookkeeping silently. Continue to merge. No message required. |
| Bookkeeping commit or push fails | Stop. Report the error. Do not merge. |

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
