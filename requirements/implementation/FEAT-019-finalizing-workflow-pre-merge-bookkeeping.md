# Implementation Plan: Finalizing Workflow Pre-Merge Bookkeeping

## Overview

This plan extends `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` with a `## Pre-Merge Bookkeeping` section that performs four deterministic clerical updates to the active requirement document immediately before `gh pr merge` runs: acceptance-criteria checkbox flip, `## Completion` section upsert (with today's date and PR link), and `## Affected Files` list reconciliation against the actual PR diff. A corresponding test file is created in `scripts/__tests__/finalizing-workflow.test.ts` to verify the new behavior.

FEAT-018 removed the write-back reconciliation loop from `executing-qa`, leaving merged PRs with unticked ACs, empty Completion sections, and stale Affected Files lists. FEAT-019 restores the clerical work by absorbing it into `finalizing-workflow`, which already holds `gh` and `git` in its toolbelt and runs at the only point in the chain where all bookkeeping inputs (PR number, PR URL, final diff, approved state) are guaranteed to be present.

The modification is strictly additive: no existing step in `finalizing-workflow` is changed, renumbered, or removed. `executing-qa/SKILL.md` is not touched. The two phases below are ordered to allow human review of the skill edit independently of test authoring.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-019 | [#169](https://github.com/lwndev/lwndev-marketplace/issues/169) | [FEAT-019-finalizing-workflow-pre-merge-bookkeeping.md](../features/FEAT-019-finalizing-workflow-pre-merge-bookkeeping.md) | Medium | Medium | 🔄 In Progress |

## Recommended Build Sequence

### Phase 1: Skill Edit — Frontmatter and Pre-Merge Bookkeeping Section

**Feature:** [FEAT-019](../features/FEAT-019-finalizing-workflow-pre-merge-bookkeeping.md) | [#169](https://github.com/lwndev/lwndev-marketplace/issues/169)
**Status:** ✅ Complete

#### Rationale

All skill-level changes are self-contained edits to one file (`plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md`). Grouping them in a single phase means the diff is reviewable as a unit before any test scaffolding is written, minimising back-and-forth between skill prose and test expectations. No new files are created; no other skill is touched.

Phase 1 produces the artifact under test, which is a prerequisite for meaningful Phase 2 test authorship — but Phase 2 can be drafted speculatively in parallel by a human reviewer against the requirements document alone.

#### Implementation Steps

1. **Update `allowed-tools` frontmatter (NFR-7 / FR-7)**
   Open `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md`. In the YAML frontmatter, add `Edit` and `Glob` to the `allowed-tools` list after `Read`. The final list must be: `Bash`, `Read`, `Edit`, `Glob`. Do **not** add `Write`.

2. **Relocate the confirmation prompt from `## Execution` to a new `## Pre-Merge Bookkeeping` section (FR-1)**
   - Remove the existing confirmation prompt paragraph from the top of `## Execution` (lines beginning "After all pre-flight checks pass, confirm intent…" through the blockquote `> Ready to merge PR #N…`).
   - Insert a new top-level section `## Pre-Merge Bookkeeping` between `## Pre-Flight Checks` and `## Execution`.
   - Open the new section with the relocated (and extended) confirmation prompt:
     > Ready to merge PR #N ("PR title") and finalize the requirement document. Proceed?
   - Add a note: "Wait for user confirmation. If the user declines, abort before running any bookkeeping. Bookkeeping runs once after confirmation; `## Execution` proceeds without a second prompt."

3. **Add Step BK-1 — Derive Work Item ID From Branch Name (FR-2)**
   Inside `## Pre-Merge Bookkeeping`, add a sub-step explaining the branch-name parsing rules:
   - `^feat/(FEAT-[0-9]+)-` → derived ID `FEAT-NNN`, directory `requirements/features/`
   - `^chore/(CHORE-[0-9]+)-` → derived ID `CHORE-NNN`, directory `requirements/chores/`
   - `^fix/(BUG-[0-9]+)-` → derived ID `BUG-NNN`, directory `requirements/bugs/`
   - Any other pattern → skip all bookkeeping with info-level message (see FR-7 row 1); continue to `## Execution`.
   - State that the branch name was already captured by Pre-Flight Check 2 (`git branch --show-current`); no new shell call is required.

4. **Add Step BK-2 — Locate the Requirement Document (FR-3)**
   Using the derived ID and directory from BK-1, locate the doc via Glob pattern `{directory}/{ID}-*.md`:
   - Zero matches → skip all bookkeeping with warning (FR-7 row 2); continue to `## Execution`.
   - Two or more matches → skip all bookkeeping with error-level warning ("workspace inconsistency — investigate"); continue to `## Execution`.
   - Exactly one match → store the resolved path for BK-3 and BK-4.

5. **Add Step BK-3 — Idempotency Check (FR-4)**
   Before any edits, check all three conditions:
   1. The `## Acceptance Criteria` section is absent, or present with zero `- [ ]` lines.
   2. A `## Completion` section exists containing `**Status:** \`Complete\`` or `**Status:** \`Completed\``.
   3. A `**Pull Request:**` line within `## Completion` contains `[#N]` or `/pull/N` where N equals the current PR number (from Pre-Flight Check 3; no new `gh` call).
   If all three hold → skip bookkeeping silently; proceed to `## Execution` (FR-7 row 3).
   If any fails → proceed to BK-4.

6. **Add Step BK-4 — Four Mechanical Updates (FR-5)**
   Document each sub-step in order:
   - **BK-4.1 (FR-5.1): Acceptance Criteria Checkoff** — Read the doc; for every `- [ ]` line within `## Acceptance Criteria` (up to next `## ` heading or EOF), replace with `- [x]`. Preserve text verbatim. If section absent, skip silently.
   - **BK-4.2 (FR-5.2): Completion Section Upsert** — Construct the block (below). If `## Completion` exists, replace its body in place (heading preserved, all sub-sections replaced). If absent, append (preceded by a blank line) at end of doc.

     ```
     ## Completion

     **Status:** `Complete`

     **Completed:** YYYY-MM-DD

     **Pull Request:** [#N](https://github.com/{owner}/{repo}/pull/N)
     ```

     Date: `date -u +%Y-%m-%d`. PR number and URL: `gh pr view --json number,url --jq '{number: .number, url: .url}'`. On `gh` failure: omit the `**Pull Request:**` line; write Status + date only; log a warning (NFR-5).

   - **BK-4.3 (FR-5.3): Affected Files Reconciliation** — Fetch PR files: `gh pr view {N} --json files --jq '.files[].path' | sort`. If section absent → skip silently. If present: files in PR but not in doc → append as `` - `path` `` bullets; files in doc not in PR → annotate `(planned but not modified)` (idempotent — skip if already present); files in both → leave unchanged. On `gh` failure → skip sub-step; log warning.
   - **BK-4.4 (FR-5.4):** Confirm this is satisfied by BK-4.2 (the `**Pull Request:**` line). No additional edit.

7. **Add Step BK-5 — Bookkeeping Commit and Push (FR-6)**
   - Run `git status --porcelain`. No changes → skip commit and push; proceed to `## Execution`.
   - Changes → stage only the requirement doc (`git add {resolved-path}`), commit with:
     ```
     chore({ID}): finalize requirement document

     - Tick completed acceptance criteria
     - Set completion status with PR link
     - Reconcile affected files against PR diff
     ```
     then `git push`.
   - State: new commit only (no amend, no force-push). Git author identity uses whatever `git config user.name`/`user.email` are set; if identity not configured, stop and report — do not auto-configure.
   - If push fails → stop and report; do not proceed to `## Execution` (FR-7 row 4).

8. **Extend `## Error Handling` table (FR-7)**
   Append four new rows to the existing table:

   | Scenario | Action |
   |----------|--------|
   | Branch name does not match workflow ID pattern (`feat/`, `chore/`, `fix/`) | Skip bookkeeping. Emit info-level message: `[info] Branch {name} does not match workflow ID pattern; skipping bookkeeping.` Continue to merge. |
   | Requirement doc not found for derived ID | Skip bookkeeping. Emit warning-level message: `[warn] No requirement doc found for {ID} under {directory}; skipping bookkeeping.` Continue to merge. |
   | Requirement doc already finalized (FR-4 idempotency check passes) | Skip bookkeeping silently. Continue to merge. No message required. |
   | Bookkeeping commit or push fails | Stop. Report the error. Do not merge. |

9. **Update "Relationship to Other Skills" table row (FR-9)**
   Change the existing row:
   - From: `| **Merge PR and reset to main** | **Use this skill (\`finalizing-workflow\`)** |`
   - To: `| **Merge PR and reset to main (and finalize requirement doc)** | **Use this skill (\`finalizing-workflow\`)** |`

10. **Verify `CLAUDE.md` for stale prose (FR-10)**
    Grep `CLAUDE.md` for any mention of `executing-qa` performing reconciliation write-backs. The current line "its test-plan reconciliation mode is still available as a standalone invocation" refers to `reviewing-requirements`, not `executing-qa` — no change required unless a Phase 1 pass discovers additional stale references.

11. **Confirm `executing-qa/SKILL.md` is untouched (NFR-2)**
    Do not edit `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`. If in doubt, re-read the file and confirm no `## Acceptance Criteria`, `## Affected Files`, or `## Completion` edit instructions are present (they are not, post-FEAT-018).

12. **Run `npm run validate`**
    Confirm the plugin passes validation after all edits.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — `allowed-tools` updated to include `Edit` and `Glob`
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — `## Pre-Merge Bookkeeping` section inserted between `## Pre-Flight Checks` and `## Execution`, containing steps BK-1 through BK-5
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — confirmation prompt relocated and extended to cover requirement-doc finalization
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — `## Error Handling` table gains four new rows (FR-7)
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — "Relationship to Other Skills" row updated (FR-9)
- [x] `npm run validate` passes

#### Verification Criteria

- [ ] Diff of `finalizing-workflow/SKILL.md` shows `allowed-tools` contains exactly: `Bash`, `Read`, `Edit`, `Glob`
- [ ] Section order in skill is: `## Pre-Flight Checks` → `## Pre-Merge Bookkeeping` → `## Execution`
- [ ] The original confirmation prompt does **not** appear in `## Execution`; the new extended prompt appears in `## Pre-Merge Bookkeeping`
- [ ] All five bookkeeping steps (BK-1 through BK-5) are present and reference the correct FR numbers
- [ ] Error table contains the four new rows with exact wording from FR-7
- [ ] "Relationship to Other Skills" row contains "(and finalize requirement doc)"
- [ ] No changes to `executing-qa/SKILL.md` (verify with `git diff`)
- [ ] `npm run validate` exits 0

---

### Phase 2: Test Coverage — `scripts/__tests__/finalizing-workflow.test.ts`

**Feature:** [FEAT-019](../features/FEAT-019-finalizing-workflow-pre-merge-bookkeeping.md) | [#169](https://github.com/lwndev/lwndev-marketplace/issues/169)
**Status:** Pending

#### Rationale

Test authorship is isolated in its own phase so it can proceed (or be reviewed) independently of Phase 1's skill-prose edits. The test file is created from scratch — no existing `finalizing-workflow.test.ts` exists. Tests validate the bookkeeping logic described in the skill by exercising the documented rules against synthetic requirement documents with mocked `gh` and `git` responses, following established Vitest conventions (`fileParallelism: false`).

Phase 2 depends on Phase 1 only for the SKILL.md structural assertions (which assert section headings introduced in Phase 1). All doc-mutation and logic tests are self-contained against synthetic fixtures and mocked shell commands.

#### Implementation Steps

1. **Create `scripts/__tests__/finalizing-workflow.test.ts`**
   Use the existing test file structure from `executing-qa.test.ts` and `executing-chores.test.ts` as a model. Import from `vitest`, `node:fs`, `node:path`, `node:os`. Set `SKILL_DIR = 'plugins/lwndev-sdlc/skills/finalizing-workflow'` and `SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md')`.

2. **SKILL.md structural assertions** (verify Phase 1 edits landed correctly)
   - `allowed-tools` contains `Edit` and `Glob`
   - `## Pre-Merge Bookkeeping` section exists and appears before `## Execution`
   - `## Error Handling` table contains the four new rows (match key phrases from each row)
   - "Relationship to Other Skills" table contains `Merge PR and reset to main (and finalize requirement doc)`
   - Existing sections (`## Pre-Flight Checks`, `## Execution`, `## Completion`, `## Error Handling`) are still present

3. **Unit tests — Branch-name parsing (FR-2)**
   Using a helper function that mimics the parsing logic (or by testing the regex patterns documented in the skill), assert:
   - `feat/FEAT-019-foo` → derived ID `FEAT-019`, directory `requirements/features/`
   - `chore/CHORE-033-fix` → derived ID `CHORE-033`, directory `requirements/chores/`
   - `fix/BUG-011-stop-hook` → derived ID `BUG-011`, directory `requirements/bugs/`
   - `release/lwndev-sdlc-v1.13.0` → no match (skip bookkeeping)
   - `bug/BUG-011-stop-hook` → no match (non-canonical prefix)
   - `main` → no match

4. **Unit tests — Requirement doc location (FR-3)**
   Using a `tmp` directory with synthetic files, verify the glob resolution logic:
   - One file matching `FEAT-019-*.md` → resolved path returned
   - Zero files → skip-with-warning path taken
   - Two files matching same ID → skip-with-error path taken

5. **Unit tests — Idempotency detection (FR-4)**
   Using synthetic doc content strings, assert the three-condition check:
   - All ACs ticked (`- [x]`), Completion has `Complete`, PR link matches current PR number → idempotency passes (skip)
   - One `- [ ]` present → idempotency fails (proceed to edits)
   - Completion section absent → idempotency fails
   - PR link present but wrong number → idempotency fails
   - No `## Acceptance Criteria` section → AC condition satisfied (carve-out per FR-4)

6. **Unit tests — AC checkoff (FR-5.1)**
   Using synthetic doc strings:
   - Mixed `- [ ]` / `- [x]` in AC section → all become `- [x]`, non-AC section untouched
   - AC section absent → doc unchanged
   - Only `- [x]` already → doc unchanged (idempotent)
   - AC items with trailing text preserved verbatim

7. **Unit tests — Completion section upsert (FR-5.2)**
   Using synthetic docs (operate on temp files with `Edit` or by testing the logic directly):
   - No `## Completion` section → block appended at end with correct structure
   - Existing `## Completion` with stale status → body replaced, heading line preserved
   - `gh` call fails → `**Pull Request:**` line omitted; Status + date written; warning logged
   - Date format matches `YYYY-MM-DD` pattern

8. **Unit tests — Affected Files reconciliation (FR-5.3)**
   - File in PR not in doc → new bullet appended in sorted order
   - File in doc not in PR → annotated `(planned but not modified)`; existing description preserved
   - File in both → unchanged
   - No `## Affected Files` section → sub-step skipped silently
   - Annotation idempotency: line already ending with `(planned but not modified)` → not double-annotated

9. **Unit tests — Commit message format (FR-6)**
   Mock `git commit` invocation and verify:
   - Commit message starts with `chore({ID}): finalize requirement document`
   - Body contains the three prescribed bullet lines
   - No `--amend` flag used
   - No `--force` or `--force-with-lease` in `git push`

10. **Integration tests — End-to-end happy path**
    Using a temp git repo with a synthetic feature branch:
    - Requirement doc has unticked ACs, no `## Completion` section, an `## Affected Files` section listing one planned file
    - Mock `gh pr view` to return a synthetic PR (number, title, url, files)
    - Run bookkeeping logic
    - Assert: ACs all `- [x]`; `## Completion` block present with today's date and PR link; PR file appended to Affected Files; planned-but-not-PR file annotated
    - Assert: one new commit on branch with prescribed message; no amend; no force-push

11. **Integration tests — Idempotency (end-to-end)**
    Using a synthetic branch whose requirement doc already satisfies all three FR-4 conditions:
    - Assert: no new commit produced; doc is byte-identical to pre-run state; `gh pr merge` would still be invoked (bookkeeping path exited cleanly)

12. **Integration tests — `gh pr view --json files` fails (NFR-5 row 2)**
    Mock `--json files` call to fail; `--json number,url` succeeds:
    - FR-5.1 runs normally; FR-5.2 completes with PR link; FR-5.3 skipped with warning
    - Commit still produced; merge proceeds

13. **Integration tests — Both `gh` calls fail (NFR-5 row 3)**
    Mock all `gh pr view` calls to fail:
    - FR-5.1 runs; FR-5.2 writes Status + date only (no PR link); FR-5.3 skipped
    - Commit still produced

14. **Integration tests — `git push` fails (FR-6 / FR-7 row 4)**
    Mock `git push` to exit non-zero:
    - Assert: merge is **not** invoked; error is reported

15. **Integration tests — Non-matching branch name (FR-7 row 1)**
    Branch name `release/lwndev-sdlc-v1.13.0`:
    - Assert: no doc edits; info-level message emitted; merge proceeds

16. **Run `npm test`** to confirm all new tests pass and no existing tests regress.

#### Deliverables

- [ ] `scripts/__tests__/finalizing-workflow.test.ts` — new file, all test cases passing
- [ ] `npm test` passes (zero failures)

#### Verification Criteria

- [ ] `scripts/__tests__/finalizing-workflow.test.ts` exists and is non-empty
- [ ] Running `npm test -- --testPathPatterns=finalizing-workflow` produces 0 failures
- [ ] All unit test cases for FR-2, FR-3, FR-4, FR-5.1, FR-5.2, FR-5.3, FR-6 are present
- [ ] All integration test scenarios listed in steps 10–15 are present
- [ ] `npm test` (full suite) exits 0 with no pre-existing tests regressed

---

## Shared Infrastructure

No new shared utilities are required. The bookkeeping logic operates exclusively through tools already available to `finalizing-workflow`: `Read`, `Edit`, `Glob`, and `Bash` (for `gh`, `git`, and `date`). No additions to `scripts/lib/` are needed.

## Testing Strategy

**Unit tests** (`scripts/__tests__/finalizing-workflow.test.ts`, Phase 2 steps 2–9):
- SKILL.md structural assertions (content-based, no execution)
- Branch-name parsing regex coverage (all documented patterns plus negative cases)
- Idempotency detection logic against synthetic doc strings
- Per-sub-step doc mutation logic (AC checkoff, Completion upsert, Affected Files reconciliation) against synthetic temp files
- Commit message format assertion via mocked `git`

**Integration tests** (Phase 2 steps 10–15):
- Happy path end-to-end against a synthetic temp git repo with mocked `gh`/`git`
- Idempotency re-run (no second commit, doc byte-identical)
- Graceful degradation: `--json files` failure, both `gh` failures
- Push-failure abort (merge not invoked)
- Non-matching branch name skip

**Not covered by automated tests** (documented in requirements as manual testing):
- Real small chore workflow end-to-end (manual)
- Release branch skip (manual)
- Re-run with deliberate AC un-tick (manual re-entry path)

Note per residual warnings: the "post-push-failure re-run" path and "stale PR link" scenario are not covered by integration tests. These are low-probability edge cases; they can be added as follow-up if the manual test exercise surfaces issues.

## Dependencies and Prerequisites

| Dependency | Status |
|------------|--------|
| FEAT-018 (QA executable oracle redesign) — removed write-back reconciliation from `executing-qa` | Landed (#172) |
| FEAT-017 (remove code-review reconciliation step) — simplified post-merge state | Landed |
| CHORE-023 (add finalizing-workflow skill) — created the skill being extended | Landed |

No new package dependencies. `gh`, `git`, and `date` are already used by `finalizing-workflow`.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Edit tool conflicts if requirement doc has unexpected section ordering | Medium | Low | FR-5 sub-steps operate independently; each reads the current state before writing. If `Edit` fails due to a stale match, the skill aborts and reports the conflict — safe, no silent corruption. |
| `gh pr view --json files` silently truncates large file lists | Low | Low | FR-5.3 operates on the returned list as-is. For typical PRs (< 100 files), `gh` returns the full list. Edge case documented in NFR-5. |
| Bookkeeping commit triggers branch-protection rules (no direct push) | Medium | Low | FR-6 push error path stops the skill and reports the failure before merging. User must resolve (e.g., temporarily lift protection or use a PR for the bookkeeping commit — out of scope for this feature). |
| Double-annotation bug on FR-5.3 partial re-run | Low | Low | FR-5.3 explicitly checks for existing `(planned but not modified)` suffix before appending. Covered by unit test (Phase 2 step 8). |
| Test fixtures becoming brittle if SKILL.md section headings change | Low | Low | Structural assertions match substring content, not line numbers. Resilient to whitespace and ordering changes within sections. |

## Success Criteria

- `finalizing-workflow/SKILL.md` gains `## Pre-Merge Bookkeeping` between `## Pre-Flight Checks` and `## Execution` documenting all five bookkeeping steps (BK-1 through BK-5) with correct FR references
- `allowed-tools` in `finalizing-workflow/SKILL.md` frontmatter contains `Edit` and `Glob`
- Error table gains four rows matching the exact wording in FR-7
- "Relationship to Other Skills" row updated to reflect requirement-doc finalization
- `executing-qa/SKILL.md` is unchanged (diff is empty for that file)
- Existing `finalizing-workflow` steps (Pre-Flight Checks, Execution sequence) are unchanged
- `scripts/__tests__/finalizing-workflow.test.ts` exists with full unit and integration coverage
- `npm run validate` passes
- `npm test` passes (all new tests green, no regressions)
- A real manual test run through a chore workflow produces a post-merge requirement doc with ticked ACs, a valid `## Completion` block (today's date, PR link), and an `## Affected Files` list matching `gh pr view --json files`

## Code Organization

```
plugins/lwndev-sdlc/skills/finalizing-workflow/
└── SKILL.md                            ← Phase 1: all edits land here

scripts/__tests__/
└── finalizing-workflow.test.ts         ← Phase 2: new file (does not exist today)
```

No other files are created or modified by this feature.

---

## Residual Review Warnings (Tracked, Not Blocking)

The following observations from the review step may be addressed as optional polish during Phase 1 implementation. None are plan-blockers.

| Warning | Disposition |
|---------|-------------|
| User Story says "four" updates but parenthetical lists three | Cosmetic — fix the User Story prose in the requirements doc if desired; does not affect skill content |
| FR-5.2 could drop the redundant `number` fetch (`--json url` is enough) | The implementation plan adopts `--json number,url` as written in FR-5.2; the redundancy is harmless. If implementer prefers `--json url`, that is a valid micro-optimization to apply during Phase 1 step 6. |
| FR-1 says "four-step procedure" but FR-6 is a fifth step in practice | Use "five-step" in the skill prose (BK-1 through BK-5) for accuracy. The requirements doc wording need not be changed. |
| FR-8 phrasing "add (or extend) a test file" — file will be created, not extended | Phase 2 creates the file from scratch. No action required. |
| Integration tests don't cover "post-push-failure re-run" path | Noted as a gap. Can be added as a follow-up test if the manual test pass surfaces issues. |
| "Stale PR link" scenario is implicit, not documented explicitly | Covered by FR-4 idempotency check (PR number mismatch fails condition 3). No additional explicit scenario needed. |
| FR-6 error handling doesn't call out `git add` failure explicitly | Phase 1 step 7 may add a note: "if `git add` fails, stop and report — treat as a non-recoverable error" to be consistent with push-failure handling. |
