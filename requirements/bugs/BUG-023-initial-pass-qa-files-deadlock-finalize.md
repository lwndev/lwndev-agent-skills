# Bug Report: Initial-run PASS produces un-adopted qa-* files that deadlock finalizing-workflow's FR-9 preflight gate

**Bug ID:** BUG-023
**Date Reported:** 2026-05-31
**Reported By:** leif@lwndev.com (GitHub issue #303)
**Severity:** High
**Status:** Open
**Component:** orchestrating-workflows (qa-dispatch.sh) / finalizing-workflow (preflight-checks.sh FR-9) / addressing-qa-findings (detect-phase.sh, SKILL.md — only if Mechanism A is chosen)

---

## Summary

A workflow whose QA passes on the first run (no regression, no fix loop) deadlocks at `finalizing-workflow`. `executing-qa` commits its tests under the `qa-*` prefix, but an initial-run PASS never triggers the adoption step that renames them to the adopted `*.qa.*` form. `finalize.sh`'s FR-9 preflight safety-net then blocks the merge on exactly those just-created `qa-*` files. No orchestrator path bridges initial-run PASS -> adoption, so the chain cannot finalize without manual intervention.

---

## Environment

- Plugin: `lwndev-sdlc@1.27.0`
- Backend: Azure DevOps (deadlock is backend-independent — FR-9 uses `git ls-files`, not the PR backend)
- Surfaced by: BUG-001 bug-chain run, 2026-05-26 (QA passed 19/19 first run)

---

## Reproduction Steps

1. Run any bug/chore/feature chain via `/orchestrating-workflows {ID}` where production code is already correct, so `executing-qa` returns PASS on the first run (`qaFixAttempts=0`).
2. `executing-qa` commits `tests/unit/qa-{ID}-*.test.ts`; `qa-dispatch.sh` returns `advance`. No `addressing-qa-findings` adopt phase runs.
3. Orchestrator advances to `finalizing-workflow` and forks it.
4. `finalize.sh` -> `preflight-checks.sh` FR-9 block exits non-zero naming the brand-new `qa-{ID}-*` files.
5. Chain cannot finalize.

---

## Expected Behavior

An initial-run PASS leaves the branch in a state `finalize.sh` accepts, with no manual `git mv`. An initial-PASS chain finalizes end-to-end with no manual file surgery.

---

## Actual Behavior

FR-9 preflight block exits non-zero with *"QA test files were not adopted; the addressing-qa-findings skill did not complete cleanly"*, naming the three `tests/unit/qa-BUG-001-*.test.ts` files the same run had just created. Chain deadlocks. Observed downstream symptom (#293): the forked finalize agent may delete the files to unblock itself.

---

## Root Cause Analysis

Two correct-in-isolation contracts combine into a deadlock:

1. **`qa-dispatch.sh` — initial-run PASS short-circuits adoption.** On `qaLastVerdict=PASS` with `qaFixAttempts=0` it returns `dispatch=advance` directly. `adopt-phase` is reachable only on a post-fix PASS (`qaFixAttempts>0 && adoptedTests==0`). See `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/qa-dispatch.sh` (the `PASS)` case, ~lines 109-121).

2. **`finalize.sh` FR-9 safety-net — blocks any tracked `qa-*`-prefixed file on the branch.** `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh` (FR-9 block, ~lines 344-391) uses **`git ls-files`** against `tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`. (Corrected during review: the gate is `git ls-files`, NOT `git diff --name-only --diff-filter=A origin/main...HEAD`. `git ls-files` matches ALL tracked files at those paths regardless of whether they were added since `origin/main` diverged — this is the authoritative behavior and any ID-scoping fix, Mechanism C, must reason about `git ls-files` semantics, not diff semantics.) The adopted `*.qa.test.ts` infix is intentionally NOT matched — only the `qa-*` prefix. So files in the form `executing-qa` writes on an initial run always trip the gate until adopted.

Net effect: every chain that passes QA on the first attempt produces un-adopted `qa-*` files (contract 1) that the FR-9 gate rejects (contract 2). The gate was designed to catch genuinely-orphaned QA files (a fix loop that didn't complete adoption) but cannot distinguish those from QA files that legitimately have no adoption path because the run passed first-try.

Note: `workflow-state.sh record-adopted-test` updates state only and does NOT satisfy the git-based FR-9 gate.

---

## Acceptance Criteria

- [x] A chain (bug/chore/feature) that returns QA PASS on the first run (`qaFixAttempts=0`) finalizes end-to-end with no manual `git mv` and no FR-9 block.
- [x] The chosen mechanism is documented in the relevant SKILL.md and reference docs.
- [x] `record-adopted-test` and the git-based FR-9 gate are reconciled so state and on-disk reality agree (or the gate stops depending on a state-invisible signal).
- [x] Regression test: a fixture driving an initial-run-PASS chain reaches finalize and asserts the preflight passes — i.e. `git ls-files 'tests/unit/qa-*.test.ts' 'tests/unit/qa-*.test.js' 'tests/bats/qa/qa-*.bats'` returns no tracked files on the branch (NOT "newly added relative to origin/main" — the gate is `git ls-files`, see RC-2). Canonical leaves: `tests/bats/skills/orchestrating-workflows/qa-dispatch.bats` (dispatch branch) and a `tests/bats/skills/finalizing-workflow/` preflight test.

---

## Proposed Fix

Candidate mechanisms from the issue (one to be selected during planning/review):

- **(A)** `qa-dispatch.sh` fires `adopt-phase` on initial-run PASS (not just post-fix PASS), so adoption renames `qa-*` -> `*.qa.*` before finalize.
  - **Verified-during-review scope (do not under-estimate):** the existing adopt path is gated by `addressing-qa-findings/scripts/detect-phase.sh` — `detect_adopt()` requires `[[ verdict==PASS && attempts -gt 0 && adopted_count -eq 0 ]]`. On initial PASS, `qaFixAttempts=0` falls through to `phase=unknown` and `addressing-qa-findings` exits `failed | unable to auto-detect phase from state`. Mechanism A therefore requires changing **both** `qa-dispatch.sh` (dispatch branch) **and** `detect-phase.sh` (relax the `attempts -gt 0` guard for the initial-PASS-with-qa-files case), **and** updating `addressing-qa-findings/SKILL.md` (its Relationship table currently states "QA verdict PASS on first run -> advance directly to finalizing-workflow").
  - The `adopt-qa-test.sh` / `run-adopt-loop.sh` rename machinery is a pure `git mv` with no fix-commit / failing-then-passing dependency, so it works on an initial PASS once the guard allows it. FR-13 (adopt-qa-test.sh = sole owner of `qa-*` rename/deletion) is preserved.
  - Dispatch must condition `adopt-phase` on actual git-visible un-adopted `qa-*` files (`git ls-files` against the canonical ephemeral globs); when none exist, initial PASS must still `advance` (covers trivial no-test changes and EXPLORATORY-ONLY). Treat `run-adopt-loop.sh` exit 2 (no files) as clean -> advance.
- **(B)** `executing-qa` writes tests directly in the adopted `*.qa.*` form once a run is graded PASS (no separate adopt step for the no-regression path).
- **(C)** FR-9 gate scoped to genuinely-orphaned files (e.g. only block `qa-*` files belonging to a different workflow ID than the one being finalized), so a chain's own just-created QA files do not block its own finalize.

---

## Related Issues

- **#293** — downstream symptom: when the FR-9 gate blocks, the forked finalize agent overreaches and deletes files. This bug is the root it reacts to.
- **#265** — frames v1 adoption as a fix-path step only; that framing omits the initial-PASS path.
- **#266** — one-time cleanup of accumulated orphan `qa-*` files; does not address the per-run deadlock.
- GitHub issue: lwndev/lwndev-marketplace#303

---

## Completion

**Status:** `Complete`

**Completed:** 2026-06-01

**Pull Request:** [#308](https://github.com/lwndev/lwndev-marketplace/pull/308)
