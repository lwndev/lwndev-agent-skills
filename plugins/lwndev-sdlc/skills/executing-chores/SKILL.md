---
name: executing-chores
description: Executes chore task workflows including branch creation, implementation, and pull request creation. Use when the user says "execute chore", "implement this chore", "run the chore workflow", or references chore documents in requirements/chores/.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
argument-hint: <chore-id>
---

# Executing Chores

Execute chore task workflows with systematic tracking from branch creation through pull request.

## When to Use This Skill

- User says "execute chore", "implement this chore", or "run the chore workflow"
- User references a chore document in `requirements/chores/`
- Implementing documented maintenance work
- Continuing chore work previously started

## Arguments

- **When argument is provided**: Match against `requirements/chores/` files by ID prefix (e.g., `CHORE-007` matches `CHORE-007-migrate-config.md`). On no match, inform the user and fall back to interactive selection. On multiple matches, present options and ask the user to choose.
- **When no argument is provided**: Scan `requirements/chores/` and prompt the user to select one if multiple exist.

## Quick Start

1. Locate the chore document — resolve a `CHORE-NNN` ID with:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<CHORE-NNN>"
   ```

   Exit codes: `0` on exactly-one match (path on stdout); `1` on zero matches; `2` on ambiguous (list candidates); `3` on malformed/missing ID.
2. Extract Chore ID and review acceptance criteria.
3. Create the git branch. Build the name and ensure checkout with:

   ```bash
   branch=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-branch-name.sh" chore "<CHORE-NNN>" "<2-4 word description>")
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-branch.sh" "$branch"
   ```

   `build-branch-name.sh` calls `slugify.sh` internally — lowercasing, punctuation stripping, stopword removal (`a`, `an`, `the`, `of`, `for`, `to`, `and`, `or`), 4-token cap. Exit codes: `build-branch-name.sh` returns `1` on empty slug (ask for a more descriptive title), `2` on invalid type. `ensure-branch.sh` returns `0` on success, `2` on missing arg, `3` on dirty working tree (stash or commit first).
4. Execute the defined changes, tracking with todos.
5. **Check off each acceptance criterion** in the chore document with:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-acceptance.sh" "<chore-doc>" "<AC matcher>"
   ```

   Literal substring match (not regex), fence-aware. Exit codes: `0` on `checked` / `already checked` (idempotent); `1` on criterion not found; `2` on ambiguous; `3` on missing arg.
6. Commit changes with:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/commit-work.sh" chore <category> "<description>"
   ```

   **The script does not stage files** — run `git add <paths>` first. Runs `git commit -m "chore(<category>): <description>"` and prints the short SHA. Exit codes: `0` on success (SHA on stdout); `1` on commit failure (git stderr passes through); `2` on missing/invalid type arg.
7. Run build-health verification (lint, format:check, test, build) via the shared script:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-build-health.sh"
   ```

   Detects the available `package.json` scripts and runs them in order, halting on the first non-zero exit. Interactive: on a `lint` or `format:check` failure, the script offers to run the matching `lint:fix` / `format` (only when the script exists) and re-run. Non-zero exit halts the chore with `failed | <reason>`. Exit `0` on pass or graceful skip (no `package.json` / no recognized scripts / `npm` absent), `1` on failure, `2` on malformed args.
8. Create the pull request with:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/create-pr.sh" chore "<CHORE-NNN>" "<summary>" [--closes <issueRef>]
   ```

   Does `git push -u origin <branch>` then `gh pr create` against `scripts/assets/pr-body.tmpl`. **MUST include `--closes #N` if an issue exists** — auto-closes the linked issue on merge. Exit codes: `0` on success (PR URL on stdout); `1` on push or PR-creation failure; `2` on missing/invalid args.
9. Update chore document completion section (status, date, PR link).

> **Note:** Issue tracking (start/completion comments) is handled by the orchestrator via `managing-work-items`. This skill focuses on chore execution and verification.

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill is forked by `orchestrating-workflows` once per chore (chore chain step 4), so its output flows to a parent orchestrator rather than directly to the user.

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
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., disambiguation when multiple chore files match the provided ID, description re-prompt when `build-branch-name.sh` exits `1` on an empty slug, selection prompt when no chore argument is supplied and multiple chore documents exist).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) → {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `→` is the documented emitter format; do not rewrite to ASCII.
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

This skill is forked by `orchestrating-workflows` once per chore (chore chain step 4). Emit `done | artifact=<path> | <note-of-at-most-10-words>` as the **final line** on success, and `failed | <one-sentence reason>` on failure. The `Found **N errors**, **N warnings**, **N info**` shape is reserved for `reviewing-requirements` only and MUST NOT be emitted here.

`artifact=` points to the file(s) the chore actually produced. Because a chore typically commits to multiple files (source edits + chore-document checkmark edits) and finishes with a pull request, use the most-representative single reference: the PR URL or the feature branch name when the PR is created successfully, or the chore document path (`requirements/chores/<ID>-*.md`) when no PR-identifying artifact is available. Example: `done | artifact=requirements/chores/CHORE-NNN-*.md | PR #<N> created`.

**PR creation is this skill's responsibility.** Unlike `implementing-plan-phases`, this skill is NOT asked to skip PR creation when orchestrated — the chore chain has no separate PR-creation step. Step 8 (Create Pull Request) runs in both orchestrated and standalone invocations. The orchestrator extracts the PR number from this subagent's output (or falls back to `gh pr list --head <branch>`) and uses it for downstream chain steps.

**Precedence**: the return contract takes precedence over the lite rules when the two conflict. The subagent MUST emit the contract shape as the final line of the response even if it reads like narration.

## Workflow Checklist

Copy this checklist to track progress:

```
Chore Execution:
- [ ] Locate chore document (get Chore ID)
- [ ] Create git branch: chore/CHORE-XXX-description
- [ ] Load acceptance criteria into todos
- [ ] Execute defined changes
- [ ] Check off each acceptance criterion in chore document (- [ ] → - [x]) as verified
- [ ] Commit with chore(category): message format
- [ ] Run tests/build verification
- [ ] Create pull request (include "Closes #N" in body if issue exists)
- [ ] Update chore document (status → Completed, date, PR link)
```

**Important:** Including `Closes #N` in the PR body auto-closes the linked GitHub issue when merged. Without it, the issue must be closed manually.

See [references/workflow-details.md](references/workflow-details.md) for detailed guidance on each step.

## Branch Naming

Format: `chore/CHORE-XXX-{2-4-word-description}`. Always assemble via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-branch-name.sh" chore "<CHORE-NNN>" "<description>"` (see Quick Start step 3) — the script applies slugify normalization uniformly.

- Uses Chore ID (not GitHub issue number) for consistent naming
- Brief but descriptive (2-4 words)

Examples:
- `chore/CHORE-001-update-dependencies`
- `chore/CHORE-002-fix-readme-typos`
- `chore/CHORE-003-cleanup-unused-imports`

## Commit Message Format

Format: `chore(category): brief description`. Assemble via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/commit-work.sh" chore <category> "<description>"` (Quick Start step 6). **Callers must `git add` relevant paths before invoking** — the script does not auto-stage.

Categories: `dependencies`, `documentation`, `refactoring`, `configuration`, `cleanup`

Examples:
- `chore(dependencies): update typescript to 5.5`
- `chore(documentation): fix typos in README`
- `chore(cleanup): remove unused imports`

## Verification Checklist

Before creating the PR, verify:

- [ ] All acceptance criteria from chore document are met
- [ ] `verify-build-health.sh` exits 0 (lint, format:check, test, build all pass)
- [ ] Changes match the chore document scope
- [ ] No unintended side effects

## References

- **Detailed workflow guidance**: [workflow-details.md](references/workflow-details.md) - Step-by-step instructions for each phase
- **PR template**: [assets/pr-template.md](assets/pr-template.md) - Pull request format for chores

## Relationship to Other Skills

| Task Type | Recommended Approach |
|-----------|---------------------|
| Chore already documented | Use this skill (`executing-chores`) |
| Chore needs documentation first | Use `documenting-chores`, then this skill |
| New feature with requirements | Use `documenting-features` -> `creating-implementation-plans` -> `implementing-plan-phases` |
| Quick fix (no tracking needed) | Direct implementation |

After executing a chore, consider `/reviewing-requirements` for code-review reconciliation after PR review (optional but recommended), then `/executing-qa` to verify against the test plan, and `/finalizing-workflow` to merge.
