---
name: executing-bug-fixes
description: Executes bug fix workflows from branch creation through pull request with root cause driven execution. Use when the user says "execute bug fix", "fix this bug", "run the bug fix workflow", or references bug documents in requirements/bugs/.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
argument-hint: <bug-id>
---

# Executing Bug Fixes

Execute bug fix workflows with root cause driven execution from branch creation through pull request.

## When to Use This Skill

- User says "execute bug fix", "fix this bug", or "run the bug fix workflow"
- User references a bug document in `requirements/bugs/`
- User wants to implement a documented bug fix
- Continuing bug fix work that was previously started

## Arguments

- **When argument is provided**: Match the argument against files in `requirements/bugs/` by ID prefix (e.g., `BUG-003` matches `BUG-003-login-timeout-error.md`). If no match is found, inform the user and fall back to interactive selection. If multiple matches are found, present the options and ask the user to choose.
- **When no argument is provided**: Scan `requirements/bugs/` for bug documents and prompt the user to select one if multiple exist.

## Quick Start

1. Locate the bug document — resolve a `BUG-NNN` ID to a file path with:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<BUG-NNN>"
   ```

   Exit codes: `0` on exactly-one match (path on stdout); `1` on zero matches; `2` on ambiguous (list candidates); `3` on malformed/missing ID.
2. Extract Bug ID, severity, root cause(s), and review acceptance criteria
3. Redeclare root causes from the bug document into the workflow context
4. Create the git branch. Build the name and ensure checkout with:

   ```bash
   branch=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-branch-name.sh" fix "<BUG-NNN>" "<2-4 word description>")
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-branch.sh" "$branch"
   ```

   `build-branch-name.sh` calls `slugify.sh` internally (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/slugify.sh" "<description>"`), handling lowercasing, punctuation stripping, stopword removal (`a`, `an`, `the`, `of`, `for`, `to`, `and`, `or`), and the 4-token cap. Exit codes: `build-branch-name.sh` returns `1` when slugify produces an empty slug (ask for a more descriptive title) and `2` on invalid type. `ensure-branch.sh` returns `0` on success, `2` on missing arg, `3` on dirty working tree (stash or commit first).
5. Address each root cause systematically, implementing fixes and tracking with todos
6. **Check off each acceptance criterion** in the bug document with:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-acceptance.sh" "<bug-doc>" "<AC matcher>"
   ```

   Literal substring match (not regex), fence-aware. Exit codes: `0` on `checked` / `already checked` (idempotent); `1` on criterion not found; `2` on ambiguous; `3` on missing arg.
7. Commit changes with:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/commit-work.sh" fix <category> "<description>"
   ```

   **The script does not stage files** — run `git add <paths>` first. It runs `git commit -m "fix(<category>): <description>"` and prints the short SHA on success. Exit codes: `0` on success (SHA on stdout); `1` on commit failure (git stderr passes through); `2` on missing/invalid type arg.
8. Verify reproduction steps no longer trigger the bug
9. Run tests/build verification
10. Create the pull request with:

    ```bash
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/create-pr.sh" fix "<BUG-NNN>" "<summary>" [--closes <issueRef>]
    ```

    Does `git push -u origin <branch>` then `gh pr create` against `scripts/assets/pr-body.tmpl`. **MUST include `--closes #N` if an issue exists** — auto-closes the linked issue on merge. Exit codes: `0` on success (PR URL on stdout); `1` on push or PR-creation failure; `2` on missing/invalid args.
11. Update bug document completion section (status, date, PR link)

> **Note:** Issue tracking (start/completion comments) is handled by the orchestrator via `managing-work-items`. This skill focuses on root cause driven execution and verification.

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill is forked by `orchestrating-workflows` once per bug (bug chain step 4), so its output flows to a parent orchestrator rather than directly to the user.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" -- issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output (e.g., the commit/push trail or the acceptance-criterion checkmark edits).
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show (e.g., successful `Edit` confirmations, `git push` tracking lines).
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in skill-authored prose. Existing Unicode em dashes in tables and reference docs are retained.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (e.g., `resolve-requirement-doc.sh`, `build-branch-name.sh`, `ensure-branch.sh`, `check-acceptance.sh`, `commit-work.sh`, `create-pr.sh` failures; `npm test` / `npm run build` / `npm run lint` failing output).
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., disambiguation when multiple bug files match the provided ID, description re-prompt when `build-branch-name.sh` exits `1` on an empty slug, selection prompt when no bug argument is supplied and multiple bug documents exist).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) -> {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `->` is the documented emitter format; do not rewrite to ASCII.
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

This skill is forked by `orchestrating-workflows` once per bug (bug chain step 4). Emit `done | artifact=<path> | <note-of-at-most-10-words>` as the **final line** on success, and `failed | <one-sentence reason>` on failure. The `Found **N errors**, **N warnings**, **N info**` shape is reserved for `reviewing-requirements` only and MUST NOT be emitted here.

`artifact=` points to the file(s) the bug fix actually produced. Because a bug fix typically commits to multiple files (source edits + bug-document checkmark edits) and finishes with a pull request, use the most-representative single reference: the PR URL or the fix branch name when the PR is created successfully, or the bug document path (`requirements/bugs/<ID>-*.md`) when no PR-identifying artifact is available. Example: `done | artifact=requirements/bugs/BUG-NNN-*.md | PR #<N> created`.

**PR creation is this skill's responsibility.** Unlike `implementing-plan-phases`, this skill is NOT asked to skip PR creation when orchestrated — the bug chain has no separate PR-creation step. Step 10 (Create Pull Request) runs in both orchestrated and standalone invocations. The orchestrator extracts the PR number from this subagent's output (or falls back to `gh pr list --head <branch>`) and uses it for downstream chain steps.

**Precedence**: the return contract takes precedence over the lite rules when the two conflict. The subagent MUST emit the contract shape as the final line of the response even if it reads like narration.

## Workflow Checklist

Copy this checklist to track progress:

```
Bug Fix Execution:
- [ ] Locate bug document (get Bug ID)
- [ ] Extract severity, root causes, and acceptance criteria
- [ ] Redeclare root causes as trackable work items
- [ ] Create git branch: fix/BUG-XXX-description
- [ ] Address each root cause systematically (RC-1, RC-2, ...)
- [ ] Check off each acceptance criterion in bug document (- [ ] → - [x]) as verified
- [ ] Commit with fix(category): message format
- [ ] Verify reproduction steps no longer trigger the bug
- [ ] Run tests/build verification
- [ ] Create pull request (include "Closes #N" in body if issue exists)
- [ ] Update bug document (status → Completed, date, PR link)
```

**Important:** Including `Closes #N` in the PR body auto-closes the linked GitHub issue when merged. Without it, the issue must be closed manually.

See [references/workflow-details.md](references/workflow-details.md) for detailed guidance on each step.

## Root Cause Driven Execution

Bug fixes are organized around root causes identified in the bug document. This ensures systematic coverage and traceability.

### Workflow

1. **Redeclare root causes at start** — Load the root causes from the bug document into the todo list as trackable work items
2. **Address root causes systematically** — Work through each root cause in order, implementing the fix for that specific cause before moving to the next
3. **Verify per root cause** — After addressing each root cause, verify that the corresponding `(RC-N)` acceptance criteria pass
4. **Confirm full coverage** — Before creating the PR, confirm that every `RC-N` has been addressed and its acceptance criteria are met

### Discovering New Root Causes

If a new root cause is discovered during execution:

- Document it in the bug document as a new `RC-N` entry
- Add corresponding acceptance criteria with the `(RC-N)` tag
- Address it as part of the fix

## Branch Naming

Format: `fix/BUG-XXX-{2-4-word-description}`. Always assemble via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-branch-name.sh" fix "<BUG-NNN>" "<description>"` (see Quick Start step 4) rather than hand-kebabing — the script applies slugify normalization uniformly.

- Uses Bug ID (not GitHub issue number) for consistent naming
- Keep description brief but descriptive (2-4 words)

Examples:
- `fix/BUG-001-null-pointer-crash`
- `fix/BUG-002-incorrect-total-calc`
- `fix/BUG-003-missing-input-validation`

## Commit Message Format

Format: `fix(category): brief description`. Assemble via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/commit-work.sh" fix <category> "<description>"` (see Quick Start step 7). **Callers must `git add` relevant paths before invoking** — the script does not auto-stage.

| Category | Use When |
|----------|----------|
| `runtime-error` | Crashes, exceptions, unhandled errors |
| `logic-error` | Incorrect calculations, wrong conditions, flawed algorithms |
| `ui-defect` | Visual bugs, layout issues, rendering problems |
| `performance` | Slowness, memory leaks, resource exhaustion |
| `security` | Vulnerabilities, auth bypasses, data exposure |
| `regression` | Previously working functionality that broke |

Examples:
- `fix(runtime-error): handle null user in profile lookup`
- `fix(logic-error): correct discount calculation for bulk orders`
- `fix(ui-defect): fix modal overlay z-index stacking`

## Verification Checklist

Before creating the PR, verify:

- [ ] All root causes from bug document are addressed
- [ ] Each `(RC-N)` tagged acceptance criterion is met
- [ ] Reproduction steps no longer trigger the bug
- [ ] Tests pass (if applicable)
- [ ] Build succeeds
- [ ] Changes match the scope defined in bug document
- [ ] No unintended side effects or regressions

## References

- **Detailed workflow guidance**: [workflow-details.md](references/workflow-details.md) - Step-by-step instructions for each phase
- **PR template**: [assets/pr-template.md](assets/pr-template.md) - Pull request format for bug fixes

## Relationship to Other Skills

| Task Type | Recommended Approach |
|-----------|---------------------|
| Bug already documented | Use this skill (`executing-bug-fixes`) |
| Bug needs documentation first | Use `documenting-bugs`, then this skill |
| Chore or maintenance task | Use `documenting-chores` -> `executing-chores` |
| New feature with requirements | Use `documenting-features` -> `creating-implementation-plans` -> `implementing-plan-phases` |
| Quick fix (no tracking needed) | Direct implementation |

After executing a bug fix, consider running `/reviewing-requirements` for code-review reconciliation after PR review (optional but recommended), then `/executing-qa` to verify the implementation against the test plan, and `/finalizing-workflow` to merge.
