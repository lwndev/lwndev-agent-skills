# Feature Requirements: finalizing-workflow Absorbs Pre-Merge Bookkeeping

## Overview

Extend `finalizing-workflow/SKILL.md` with a pre-merge step that performs four mechanical updates to the requirement document before `gh pr merge` runs: flip acceptance-criteria checkboxes from `[ ]` to `[x]`, set the `## Completion` section to `Complete` with today's date and the PR URL, and trim/extend the `## Affected Files` list to match the actual PR diff. The clerical updates are deterministic (`gh`/`git`/`jq`/`grep`-driven), require no model reasoning once the inputs are known, and belong in the finalize step — not in QA — because `gh` and `git` are already in the finalizer's toolbelt and the PR has already been inspected by the reviewers.

## Feature ID

`FEAT-019`

## GitHub Issue

[#169](https://github.com/lwndev/lwndev-marketplace/issues/169)

## Priority

Medium — These clerical updates used to live in `executing-qa`'s reconciliation half and were removed wholesale when FEAT-018 rewrote the QA skills around an executable oracle. Today, no skill performs them: merged PRs leave their requirement docs with unticked ACs, an empty `## Completion` section, and an `## Affected Files` list that mirrors the plan rather than what was actually shipped. Missing the bookkeeping does not block merge, so this is not urgent — but the cost of restoring it is small, and without it the requirement-doc audit trail becomes unreliable over time (e.g., the `CHORE-033` doc's ACs are partly hand-ticked; the `FEAT-017` doc has no Completion section at all). Splitting this out lets it ship independently of the wider QA redesign.

## User Story

As a developer running SDLC workflows, I want `finalizing-workflow` to perform the four mechanical requirement-doc updates (AC checkoff, completion status with PR link, affected-files reconciliation) automatically before merging so that the requirement document is an accurate audit trail of what was built, without manual bookkeeping after every workflow.

## Motivation

Issue #169 identifies four updates that used to be performed by the old `executing-qa` reconciliation loop:

1. Flip `## Acceptance Criteria` checkboxes `[ ]` → `[x]` to match implementation state
2. Set `## Completion` section to `Complete` with today's date
3. Add the PR link to the requirement doc
4. Trim or extend the `## Affected Files` list to match the actual PR diff

FEAT-018 (landed as [#172](https://github.com/lwndev/lwndev-marketplace/pull/172)) removed the write-back reconciliation loop from `executing-qa` and replaced it with a read-only **Reconciliation Delta** (coverage surplus / coverage gap) — an audit-trail artifact, not a write-back. That redesign was the correct call for QA (it produced a real adversarial gate instead of a rubber-stamp), but the four clerical updates above were not migrated anywhere; they were dropped on the floor.

This feature restores the four updates by absorbing them into `finalizing-workflow`, which is a better home than `executing-qa` was for three reasons:

| Why here | Detail |
|---|---|
| `gh` and `git` are already in the toolbelt | `finalizing-workflow` already runs `gh pr view`, `gh pr merge`, `git checkout`, `git fetch`, `git pull`. Adding `gh pr view --json files` and `git diff main...HEAD` is a zero-infrastructure extension. |
| The PR has already been inspected by reviewers | Pre-merge is the only point in the chain where every input needed for the four updates is guaranteed to be present (PR number, PR URL, final diff, approved state). |
| The step runs after — not before — any further human edits | Running bookkeeping during QA means a subsequent PR-review round could invalidate it. Running it pre-merge means the recorded state cannot drift. |

The `executing-qa` half is **already done** (FEAT-018 removed the write-back loop). This feature only performs the additive half — the `finalizing-workflow` side.

## Current State (post-FEAT-018)

`plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` has no write-back reconciliation section. Its Step 6 ("Reconciliation Delta") produces a coverage-surplus / coverage-gap audit trail only; it does not edit the requirement doc. Verified against the current SKILL.md: no matches for `## Acceptance Criteria`, `## Affected Files`, or `## Completion` edits in `plugins/lwndev-sdlc/skills/executing-qa/`.

`plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` currently has three numbered steps inside its `## Execution` section (Merge the PR, Switch to Main, Fetch and Pull), preceded by a confirmation prompt and three `## Pre-Flight Checks` (Clean Working Directory, Identify Current Branch, Find Associated PR). There is no bookkeeping step.

Feature requirement docs in this repo are inconsistent with respect to `## Affected Files` and `## Completion` sections:

| Doc type | `## Affected Files` | `## Completion` |
|---|---|---|
| Bugs (`BUG-001`..`BUG-011`) | Present in all | Present in all |
| Chores (`CHORE-001`..`CHORE-033`) | Present in most | Present in most |
| Features (`FEAT-001`..`FEAT-018`) | Rare | Rare (only `FEAT-013` has one) |

The bookkeeping step must handle both cases (sections present → update in place; sections absent → append or skip per the rules below).

## Functional Requirements

### FR-1: Add a `## Pre-Merge Bookkeeping` Section to `finalizing-workflow/SKILL.md`

Insert a new top-level section titled `## Pre-Merge Bookkeeping` between `## Pre-Flight Checks` and `## Execution` in `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md`. The section documents the four-step bookkeeping procedure (FR-2 through FR-5).

**Confirmation prompt relocation**: The existing confirmation prompt ("Ready to merge PR #N (…). Proceed?") currently lives at the top of `## Execution`. Move this prompt to the top of `## Pre-Merge Bookkeeping` and extend the wording to cover the new responsibility:

> Ready to merge PR #N ("PR title") and finalize the requirement document. Proceed?

The prompt runs once per invocation. After user confirmation: bookkeeping runs (FR-2 through FR-6), then `## Execution` proceeds without a second prompt. If the user declines, the skill aborts before bookkeeping.

Bookkeeping runs in a single pass. It does not loop. It produces at most one commit and at most one push per invocation. If any step in the sequence fails in a non-recoverable way (FR-6), bookkeeping aborts and the merge does not run.

### FR-2: Derive Work Item ID From Branch Name

The bookkeeping step must derive the work item ID from the current branch name:

- Branch matches `^feat/(FEAT-[0-9]+)-` → derived ID is `FEAT-NNN`, requirement directory is `requirements/features/`
- Branch matches `^chore/(CHORE-[0-9]+)-` → derived ID is `CHORE-NNN`, requirement directory is `requirements/chores/`
- Branch matches `^fix/(BUG-[0-9]+)-` → derived ID is `BUG-NNN`, requirement directory is `requirements/bugs/`
- Anything else → skip all bookkeeping (FR-7 row 1: benign skip with info-level message)

Rationale for `fix/` (not `bug/`): `executing-bug-fixes/SKILL.md` documents `fix/BUG-XXX-{description}` as the canonical bug-fix branch format, and every historical bug branch in this repo uses it (`fix/BUG-011-stop-hook-findings-loop`, `fix/BUG-010-qa-stop-hook-cross-fire`, etc.).

The branch name is obtained from the Pre-Flight Check 2 (`git branch --show-current`), which has already run by this point; the bookkeeping step reuses the captured value.

### FR-3: Locate the Requirement Document

Using the derived ID and directory from FR-2, locate the requirement doc by Glob pattern `{directory}/{ID}-*.md`. There must be exactly one match:

- Zero matches → skip all bookkeeping (FR-7 row 2: benign skip with warning)
- Two or more matches → skip all bookkeeping with an error-level warning (this is a workspace inconsistency the user should investigate)
- Exactly one match → proceed

Store the resolved path for use in FR-4 and FR-5.

### FR-4: Idempotency Check — Skip if Already Finalized

Before making any edits, detect whether the doc is already finalized. The doc is considered finalized when **all** of the following hold:

1. The `## Acceptance Criteria` section either does not exist, or exists and contains zero `- [ ]` lines (all checked off). Implementation: if the heading is absent, treat this condition as satisfied (no unchecked ACs are possible). If the heading is present, within the section body (from its heading to the next `## ` heading or EOF), count lines matching `^- \[ \]` — zero matches = condition satisfied. Rationale: feature docs in this repo commonly omit the `## Acceptance Criteria` section; without this carve-out, such docs can never pass the idempotency check and would enter FR-5 on every re-run, producing redundant Completion-section rewrites.
2. A `## Completion` section exists and contains a `**Status:** \`Complete\`` or `**Status:** \`Completed\`` line. Implementation: within the `## Completion` section, grep for `^\*\*Status:\*\* \`(Complete|Completed)\`\s*$` — at least one match = condition satisfied.
3. A `**Pull Request:**` line exists within the `## Completion` section and references the current PR. Implementation: within the `## Completion` section, grep for `^\*\*Pull Request:\*\* \[#(\d+)\]\(` and/or `/pull/(\d+)\)?` — extract all matched integers and verify at least one equals the current PR number. The current PR number is already captured by Pre-Flight Check 3 (`gh pr view --json number,title,state,mergeable`) which runs before bookkeeping; FR-4 reuses that value without issuing a new `gh` call. A single line containing either `[#N]` or `/pull/N` where N equals the current PR number is sufficient for a match.

If all three conditions are met → skip bookkeeping silently and proceed to `## Execution` (FR-7 row 3: silent benign skip, no warning). This ensures a re-run of `finalizing-workflow` against an already-bookkept branch is a no-op.

If any of the three conditions is not met → proceed to FR-5.

### FR-5: Perform the Four Mechanical Updates

Execute the four updates in this order. Each update operates on the resolved doc path from FR-3 using the `Edit` tool; no shell sed/awk invocations:

#### FR-5.1: Acceptance Criteria Checkoff

Read the doc and locate the `## Acceptance Criteria` section. For every line matching `^- \[ \]` within that section (up to the next `## ` heading or EOF), replace `- [ ]` with `- [x]`. Preserve trailing whitespace and the criterion text exactly. If the section does not exist, skip this sub-step silently (some features do not have an AC section, though the convention is to include one).

#### FR-5.2: Completion Section Update

Construct the `## Completion` block:

```
## Completion

**Status:** `Complete`

**Completed:** YYYY-MM-DD

**Pull Request:** [#N](https://github.com/{owner}/{repo}/pull/N)
```

Where:
- `YYYY-MM-DD` is today's UTC date (`date -u +%Y-%m-%d`)
- `#N` is the PR number and the URL is the full PR web URL, both obtained from a single `gh` call: `gh pr view --json number,url --jq '{number: .number, url: .url}'`. The `url` JSON field returned by `gh pr view` is the HTML web URL (e.g., `https://github.com/owner/repo/pull/N`), which is the value to embed in the markdown link.

Edit behavior:
- If `## Completion` section already exists → replace the existing section's body (from the `## Completion` heading to the next `## ` heading or EOF) with the constructed block. Preserve the `## Completion` heading line itself. The replacement scope is the entire body, including any sub-headings (`### Foo`) inside it — sub-sections are replaced along with the body.
- If `## Completion` section does not exist → append the block (preceded by a single blank line) at the end of the doc.

Do **not** modify any surrounding top-level sections (e.g., `## Notes`, `## Deviation Summary`) even if they appear after `## Completion` — they stay in place.

#### FR-5.3: Affected Files Reconciliation

Fetch the list of files changed by the PR:

```bash
gh pr view {N} --json files --jq '.files[].path' | sort
```

Locate the `## Affected Files` section in the requirement doc. Parse the existing bulleted list — each line that matches `^- \`?([^\`\s—]+)\`?` yields a path (strip optional backticks and ignore any trailing `— description` suffix).

- If the section does not exist → skip this sub-step silently (features commonly omit it; do not auto-create it)
- If the section exists → compute the diff between the doc's listed paths and the actual PR files:
  - **Files in PR but not in doc** → append as new bullets at the end of the section, using the format `` - `path/to/file` `` (backtick-wrapped, no description suffix — the user may add descriptions manually)
  - **Files in doc but not in PR** → leave in place and append the comment `(planned but not modified)` after any existing description. Rationale: the list served as the plan; removed entries are historically meaningful and should not be silently deleted. The annotation lets a reader spot the drift without destroying the original planning record. **Idempotency:** before appending the annotation, check whether the line already ends with `(planned but not modified)`; if so, skip that line. This prevents double-annotation on partial re-runs (e.g., NFR-5 `gh` failure mid-step followed by a retry where FR-4's idempotency check still fails).
  - **Files in both** → leave unchanged

The section's ordering is preserved: existing entries stay in their original order; newly added entries appear at the end in sorted order.

#### FR-5.4: PR Link Coverage

The PR link is added to the doc as part of FR-5.2 (the `**Pull Request:**` line inside `## Completion`). No separate `PR link` update is needed. The issue listed this as a fourth item, but in practice it is a sub-line of the Completion section. This requirement is satisfied by FR-5.2 and recorded here only to confirm no additional edit is required.

### FR-6: Bookkeeping Commit and Push

After FR-5 completes (any of its sub-steps may have been no-ops), check whether the working directory has any staged or unstaged changes using `git status --porcelain`:

- If no changes → skip commit and push silently (all four updates were no-ops). Proceed to `## Execution`.
- If changes exist → stage only the requirement doc (`git add {resolved-path}` from FR-3), commit with the message:

  ```
  chore({ID}): finalize requirement document

  - Tick completed acceptance criteria
  - Set completion status with PR link
  - Reconcile affected files against PR diff
  ```

  then push to the current branch (`git push`). The commit and push run in the orchestrator's main context (same `Bash` tool that already runs the merge command); no subagent fork.

Do not amend any prior commit. Do not force-push. The bookkeeping commit is a new commit on top of whatever the PR branch currently has.

**Git author identity**: The commit uses whatever `git config user.name` / `git config user.email` are set to in the current environment. If `git commit` fails because an identity is not configured (common in fresh CI or devcontainer environments), report the error and stop — the user must configure `git config user.name` and `git config user.email` before re-running. Do not auto-configure an identity; do not fall back to a default. This matches the existing pattern in `executing-qa` Step 4, which also performs a `git commit` without addressing author identity.

If the push fails for any reason (network, auth, branch-protection rejection), **stop immediately** and report the error. Do not proceed to merge. This is FR-7 scenario 4.

### FR-7: Error Handling Table Additions

Extend the existing `## Error Handling` table in `finalizing-workflow/SKILL.md` with four new rows:

| Scenario | Action |
|----------|--------|
| Branch name does not match workflow ID pattern (`feat/`, `chore/`, `fix/`) | Skip bookkeeping. Emit info-level message: `[info] Branch {name} does not match workflow ID pattern; skipping bookkeeping.` Continue to merge. |
| Requirement doc not found for derived ID | Skip bookkeeping. Emit warning-level message: `[warn] No requirement doc found for {ID} under {directory}; skipping bookkeeping.` Continue to merge. |
| Requirement doc already finalized (FR-4 idempotency check passes) | Skip bookkeeping silently. Continue to merge. No message required. |
| Bookkeeping commit or push fails | Stop. Report the error. Do not merge. |

Rationale: the bookkeeping must not block the merge in benign cases (non-standard branch name, doc already finalized) — the merge is the primary job. Push failure is the exception because an un-pushed bookkeeping commit would leave the local branch ahead of origin and the PR merge would fail downstream in a more confusing way.

### FR-8: Update Completion-Tracking Tests

Extend the test suite to cover the new behavior. The tests that assert `finalizing-workflow` behavior live in `scripts/__tests__/`. The implementation must:

- Add (or extend) a test file that exercises the bookkeeping step against synthetic requirement docs covering:
  - A feature doc with an AC section but no Completion and no Affected Files sections (minimal case)
  - A chore doc with all three sections present (common case)
  - A bug doc already finalized (idempotency case)
  - A branch with a non-matching name (skip-and-warn case)
  - Two matching requirement docs for the same ID (skip-with-error case per FR-3)
- Assert that the resulting doc contains the expected text (ACs checked off, Completion block correct with today's date token, Affected Files reconciled)
- Assert that the bookkeeping commit is produced with the prescribed message and that no amend / force-push occurs
- Assert that push failure aborts merge

The tests should use mocked `gh` and `git` responses rather than hitting a real remote. The existing test conventions in `scripts/__tests__/` (Vitest, `fileParallelism: false`) apply.

### FR-9: Update the Skill Relationship Table in `finalizing-workflow/SKILL.md`

The existing "Relationship to Other Skills" table has a row `| **Merge PR and reset to main** | **Use this skill (\`finalizing-workflow\`)** |`. Update the human-readable description to reflect the absorbed responsibility:

```
| **Merge PR and reset to main (and finalize requirement doc)** | **Use this skill (`finalizing-workflow`)** |
```

The chain diagrams above the table do not need changes — the bookkeeping is an internal step inside `finalizing-workflow`, not a new chain position.

### FR-10: Update CLAUDE.md if It References Reconciliation in QA

Search `CLAUDE.md` for any prose that describes `executing-qa` as performing reconciliation write-backs to the requirement doc. If found (single current line about "test-plan reconciliation mode"), leave it as-is — it refers to `reviewing-requirements`, not `executing-qa`, and is accurate. No CLAUDE.md changes are required unless the Phase 1 implementation discovers additional stale references.

## Non-Functional Requirements

### NFR-1: No Regression in Existing `finalizing-workflow` Behavior

The three existing steps (`Merge the PR`, `Switch to Main`, `Fetch and Pull`) and the three pre-flight checks (`Clean Working Directory`, `Identify Current Branch`, `Find Associated PR`) must continue to run exactly as today. The new bookkeeping section is strictly additive; it adds one step before `## Execution` and adds rows to the error table. No existing step is modified, renumbered, or removed.

### NFR-2: No Changes to `executing-qa/SKILL.md`

FEAT-018 already removed the write-back reconciliation loop from `executing-qa/SKILL.md`. This feature does **not** touch `executing-qa/SKILL.md`. The issue's second ask ("remove reconciliation from executing-qa") is a no-op in the current codebase. If an implementation agent encounters a request to edit `executing-qa/SKILL.md`, the agent should verify against the current file — the reconciliation instructions are already absent.

### NFR-3: Idempotency

Running `finalizing-workflow` twice against the same branch (e.g., the user re-runs after a transient push failure, or the orchestrator retries) must be safe:

- First run: performs bookkeeping, produces a commit, pushes, merges
- Second run (hypothetical, if the branch still exists and the PR is still open): FR-4 idempotency check passes → skip bookkeeping silently, attempt merge (which itself succeeds or fails via existing behavior)

No corrupt state is produced by a re-run. No double-tick, double-commit, or duplicate `## Completion` section.

### NFR-4: Performance

The bookkeeping step adds at most four filesystem reads, one Edit call, two `gh pr view` calls (one `--json number,url` for FR-5.2, one `--json files` for FR-5.3), one `git add`, one `git commit`, and one `git push` to a workflow invocation. The added latency is on the order of 2–5 seconds (dominated by the `gh` calls and the push). No performance target is set; the step is strictly a small addition.

### NFR-5: Graceful Degradation on `gh` / `git` Failure

The bookkeeping step uses `gh pr view` for two distinct calls: one in FR-5.2 (`--json number,url` for the Completion block's PR link) and one in FR-5.3 (`--json files` for affected-files reconciliation). Graceful-degradation rules differ by call site:

| `gh` failure scope | FR-5.1 (AC checkoff) | FR-5.2 (Completion) | FR-5.3 (Affected Files) |
|---|---|---|---|
| `--json number,url` fails (FR-5.2 data unavailable) | Runs as normal | Omit the `**Pull Request:**` line from the Completion block; write `**Status:** \`Complete\``, `**Completed:** YYYY-MM-DD` only. Log a warning. | Skipped if the same failure prevents `--json files`; otherwise still attempted. |
| `--json files` fails (FR-5.3 data unavailable) | Runs as normal | Runs as normal | Skipped. Log a warning. |
| Both calls fail (e.g., `gh` not authenticated) | Runs as normal | Status + date only, no PR link | Skipped |
| `gh` is not on PATH at all | Runs as normal | Status + date only, no PR link | Skipped |

Bookkeeping continues through FR-6 (commit + push) even when `gh` degrades partially — the AC checkoff and the partial Completion block are still useful outputs. Log warnings for every skipped sub-step so the user knows what was degraded.

If `git` itself fails (e.g., `git status` exits non-zero), the entire bookkeeping step aborts with an error and the merge does not run — that failure mode already implies a corrupt working tree and the merge would fail anyway.

### NFR-6: No Subagent Forks

The bookkeeping step runs entirely in the `finalizing-workflow` skill's own context (main-context tool use — `Read`, `Edit`, `Bash`). No Agent-tool fork. No Skill-tool call. This is consistent with the `orchestrating-workflows` treatment of `finalizing-workflow` as a forked step (the orchestrator spawns `finalizing-workflow` in its own subagent; that subagent internally uses main-context tools for the bookkeeping work).

### NFR-7: Allowed-Tools

`finalizing-workflow/SKILL.md`'s `allowed-tools` frontmatter currently lists `Bash` and `Read`. The bookkeeping step requires `Edit` (for updating the requirement doc) and `Glob` (for locating the doc in FR-3). Add `Edit` and `Glob` to the frontmatter. Do **not** add `Write` (the step only edits an existing doc, never creates a new one).

## Dependencies

- FEAT-018 (QA executable oracle redesign) — Landed; removed the write-back reconciliation loop from `executing-qa/SKILL.md`. This feature inherits a clean executing-qa with no conflicting clerical work. Not a blocker.
- FEAT-017 (remove code-review reconciliation step) — Landed; reduced the orchestrator's step count and simplified post-merge state. Not a blocker.
- CHORE-023 (add finalizing-workflow skill) — Landed; created the skill being extended. Not a blocker.

## Edge Cases

1. **Branch name is `release/lwndev-sdlc-vX.Y.Z` or other non-workflow pattern**: Skip bookkeeping with info-level message. Merge proceeds unchanged. This is the common case for plugin releases, which are not workflow-driven and do not have requirement docs.
2. **Requirement doc was renamed between workflow start and finalize**: Glob by `{ID}-*.md` catches the new name. If no match (doc was deleted), skip with warning.
3. **Requirement doc has a `## Completion` section but no ACs section**: FR-5.1 is a no-op; FR-5.2 updates Completion. Result is still a meaningful finalization.
4. **Requirement doc has an `## Acceptance Criteria` section that is entirely empty**: FR-5.1 is a no-op. FR-5.2 still runs.
5. **PR has zero file changes (impossible for a merged PR, but legal for a draft)**: FR-5.3 reads an empty file list. The Affected Files section (if present) gets every existing entry annotated as `(planned but not modified)`. This is correct bookkeeping.
6. **PR branch is already ahead of origin by an un-pushed commit before bookkeeping**: The bookkeeping commit is layered on top. `git push` pushes both. No special handling. (This does not trigger Pre-Flight Check 1 — an un-pushed commit is a clean working directory with `git status --porcelain` returning empty; only uncommitted changes trigger the check.)
7. **Concurrent edit to the requirement doc between bookkeeping read and write**: The `Edit` tool performs an atomic read-match-write. If the file has changed since the read, `Edit` fails and the bookkeeping step aborts with the `Edit` error. The merge does not run. User can retry.
8. **Auto-fix-on-commit hooks modify the bookkeeping commit's diff**: Acceptable. The bookkeeping commit is created via `git commit` which runs hooks; if hooks modify the file, the commit reflects the modified state. No force-push, no retry loop.
9. **PR body already contains `Closes #N` or linked issue syntax**: Unrelated to this feature. The PR body is not modified by bookkeeping. Only the requirement doc's `## Completion` section is updated.
10. **User runs `finalizing-workflow` against a branch whose PR has been merged externally** (e.g., merged via GitHub UI): Pre-Flight Check 3 (`Find Associated PR`) already catches this — the PR is no longer `OPEN`, and the skill stops before bookkeeping runs.
11. **User runs `finalizing-workflow` against a feature branch whose PR was never created**: Pre-Flight Check 3 catches this — no PR exists, skill stops before bookkeeping.

## Testing Requirements

### Unit Tests

- Parse branch name `feat/FEAT-019-foo` → derived ID `FEAT-019`, directory `requirements/features/` (FR-2)
- Parse branch name `release/plugin-v1.2.3` → skip bookkeeping (FR-2)
- Parse branch name `chore/CHORE-033-fix` → derived ID `CHORE-033`, directory `requirements/chores/` (FR-2)
- Parse branch name `fix/BUG-011-stop-hook` → derived ID `BUG-011`, directory `requirements/bugs/` (FR-2)
- Parse branch name `bug/BUG-011-stop-hook` → skip bookkeeping (non-canonical prefix; FR-2)
- Glob `requirements/features/FEAT-019-*.md` returns one match → proceed (FR-3)
- Glob returns zero matches → skip with warning (FR-3, FR-7 row 2)
- Glob returns two matches → skip with error (FR-3)
- Idempotency check passes (all ACs ticked, Completion correct, PR link present) → skip silently (FR-4, FR-7 row 3)
- AC checkoff: input has mix of `- [ ]` and `- [x]` → all become `- [x]`, other lines unchanged (FR-5.1)
- Completion section does not exist → appended at end of doc with correct block (FR-5.2)
- Completion section exists with stale Status → body replaced, heading preserved (FR-5.2)
- Affected Files reconciliation: file in PR not in doc → appended (FR-5.3)
- Affected Files reconciliation: file in doc not in PR → annotated `(planned but not modified)` (FR-5.3)
- Affected Files section does not exist → skipped silently (FR-5.3)

### Integration Tests

- End-to-end: run `finalizing-workflow` against a synthetic feature branch with a requirement doc that has unticked ACs and no Completion. Verify the doc post-run has ticked ACs, a `## Completion` section with today's date and the PR link, and a bookkeeping commit on the branch. Verify `gh pr merge --merge --delete-branch` was invoked.
- Idempotency (synthetic, not post-merge re-run): set up a synthetic branch whose requirement doc already satisfies all three FR-4 conditions (all ACs ticked, `**Status:** \`Complete\`` present in `## Completion`, `**Pull Request:**` line with a matching `#N`). Run `finalizing-workflow`. Assert: no bookkeeping commit produced; the doc is byte-identical to the pre-run state; `gh pr merge` is still invoked.
- End-to-end: `gh pr view --json files` fails → FR-5.3 is skipped with a warning, FR-5.1 and FR-5.2 still run, commit is made, merge proceeds (NFR-5 row 2).
- End-to-end: both `gh pr view` calls fail (e.g., `gh` not authenticated) → FR-5.2 writes Status + date only (no PR link), FR-5.3 is skipped, commit is still produced (NFR-5 row 3).
- End-to-end: `git push` fails → merge does not run, error is reported (FR-6, FR-7 row 4).

### Manual Testing

- Run `finalizing-workflow` against a real small chore workflow end-to-end. Verify the requirement doc after merge has all ACs ticked, a `## Completion` section with today's date and PR link, and an Affected Files list that matches `gh pr view --json files`.
- Run `finalizing-workflow` against a branch named `release/lwndev-sdlc-v1.13.0`. Verify bookkeeping is skipped with an info message and merge proceeds (release branches are plugin releases, not workflow runs).
- Edit a completed requirement doc to remove one `[x]` → run `finalizing-workflow` again → verify the bookkeeping step reapplies the tick and produces a new commit. (Tests re-entry path even though normal lifecycle doesn't include it.)

## Acceptance Criteria

- [ ] `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` gains a `## Pre-Merge Bookkeeping` section inserted between `## Pre-Flight Checks` and `## Execution` that documents the four-step procedure (FR-1 through FR-5)
- [ ] The bookkeeping step derives the work item ID from the current branch name using the three documented patterns (`feat/`, `chore/`, `fix/`) (FR-2)
- [ ] The bookkeeping step locates the requirement doc by glob `{directory}/{ID}-*.md` with zero-/one-/multi-match handling (FR-3)
- [ ] The bookkeeping step skips silently when FR-4 idempotency conditions all hold (all ACs ticked, Completion `Complete`, PR link present)
- [ ] Running against a doc with unticked ACs flips every `- [ ]` in the `## Acceptance Criteria` section to `- [x]` without altering the criterion text (FR-5.1)
- [ ] Running against a doc with no `## Completion` section appends a `## Completion` block with today's UTC date and the PR number/URL (FR-5.2)
- [ ] Running against a doc with an existing `## Completion` section replaces the body in place and preserves the heading (FR-5.2)
- [ ] Running against a doc with an `## Affected Files` section reconciles the list against `gh pr view --json files` — additions appended, drops annotated `(planned but not modified)` (FR-5.3)
- [ ] Running against a doc without an `## Affected Files` section skips that sub-step silently (no auto-creation) (FR-5.3)
- [ ] The bookkeeping commit uses the prescribed message format (`chore({ID}): finalize requirement document` with a three-bullet body) and is a new commit (no amend, no force-push) (FR-6)
- [ ] Bookkeeping runs the commit and push before `gh pr merge` (FR-6)
- [ ] Push failure aborts the merge (FR-6, FR-7 row 4)
- [ ] Non-matching branch names cause a benign skip with info-level message (FR-7 row 1)
- [ ] Missing requirement doc causes a benign skip with warning-level message (FR-7 row 2)
- [ ] Already-finalized doc causes a silent skip (FR-7 row 3)
- [ ] The `## Error Handling` table in the skill gains the four new rows (FR-7)
- [ ] `finalizing-workflow/SKILL.md` frontmatter `allowed-tools` gains `Edit` and `Glob` (NFR-7)
- [ ] `finalizing-workflow/SKILL.md` "Relationship to Other Skills" table row for the skill is updated to `**Merge PR and reset to main (and finalize requirement doc)**` (FR-9)
- [ ] `CLAUDE.md` has been searched for stale prose describing `executing-qa` as performing reconciliation write-backs; either no changes were required (current state) or the discovered stale references are updated (FR-10)
- [ ] `executing-qa/SKILL.md` is **unchanged** by this feature (NFR-2)
- [ ] Existing `finalizing-workflow` steps (Merge, Switch, Fetch/Pull) and pre-flight checks run unchanged (NFR-1)
- [ ] Unit tests added or extended to cover branch-name parsing, doc location, idempotency detection, AC checkoff, Completion update, Affected Files reconciliation, commit message format, and error paths (FR-8)
- [ ] `npm run validate` passes after changes
- [ ] `npm test` passes after changes
- [ ] A real small workflow run end-to-end produces a requirement doc post-merge with ticked ACs, a valid Completion block, and an Affected Files list that matches the PR diff

## Explicitly Out of Scope

- Redesign of `documenting-qa` or the verification half of `executing-qa` (landed as FEAT-018)
- Deletion of either QA skill
- Changes to `reviewing-requirements` (any mode)
- Adding a `## Completion` or `## Affected Files` section to requirement docs that don't have one — only the Completion section is auto-appended if missing (FR-5.2); Affected Files is never auto-created (FR-5.3)
- Retroactive bookkeeping for already-merged PRs (this feature only affects workflows that run through `finalizing-workflow` after it ships)
- Standardizing requirement-doc section ordering across feature/chore/bug templates (tracked separately if desired)
- Removing stale instructions from `executing-qa/SKILL.md` — there are none post-FEAT-018 (NFR-2)

## References

- `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — target skill
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — reference only (confirms NFR-2 holds today)
- [#169](https://github.com/lwndev/lwndev-marketplace/issues/169) — this feature's driving issue
- [#163](https://github.com/lwndev/lwndev-marketplace/issues/163) — original proposal (closed in favor of FEAT-018 for the QA half and this feature for the bookkeeping half)
- [FEAT-018](FEAT-018-qa-executable-oracle-redesign.md) — the QA redesign that removed the write-back reconciliation loop from `executing-qa`
- [CHORE-023](../chores/CHORE-023-add-finalizing-workflow-skill.md) — chore that created `finalizing-workflow`
