# QA Test Plan: BUG-023 — initial-run PASS qa-* files deadlock finalize FR-9 gate

**Workflow ID:** BUG-023
**Date:** 2026-05-31
**Author:** orchestrating-workflows (documenting-qa)
**Chosen mechanism:** A — `qa-dispatch.sh` fires `adopt-phase` on initial-run PASS (with un-adopted `qa-*` files present); `detect-phase.sh` guard relaxed to allow `qaFixAttempts==0`; `addressing-qa-findings/SKILL.md` relationship table updated.
**Source inputs:** Bug summary + GitHub issue #303 + verified codebase contracts (`qa-dispatch.sh`, `detect-phase.sh`, `preflight-checks.sh`). No PR/diff at plan time (fix not yet implemented). Plan probes the observable contract for Mechanism A.

---

## Overview

Adversarial QA for the initial-PASS adoption fix. The change must make an initial-run-PASS chain (`qaFixAttempts=0`) reach finalize with the FR-9 `git ls-files` gate passing — WITHOUT weakening the gate against genuinely-orphaned files, and without breaking the existing post-fix adoption path. Assume the fix is broken until proven otherwise: hunt the inputs/states that re-introduce the deadlock or silently swallow real orphans.

---

## Dimension 1 — Inputs

- **[P0] Initial PASS, one un-adopted `qa-*` file.** Canonical repro. `qaLastVerdict=PASS`, `qaFixAttempts=0`, one committed `tests/unit/qa-BUG-023-*.test.ts`. Expect dispatch `adopt-phase` -> rename to `*.qa.test.ts` -> re-dispatch `advance` -> finalize preflight passes (`git ls-files` of the three globs returns empty).
- **[P0] Initial PASS, zero `qa-*` files.** Trivial change, no tests authored. Dispatch must return `advance` (NOT `adopt-phase` against nothing). `detect-phase`/adopt loop must no-op cleanly, not error.
- **[P1] Initial PASS, multiple `qa-*` files** (`-a`, `-b`, `-c`). Every file adopted, not just the first. Partial adoption must not report success.
- **[P1] Bats-only `qa-*` files** (`tests/bats/qa/qa-BUG-023-*.bats`, no vitest). Adopted to correct `*.qa.bats` sibling; gate clears.
- **[P1] EXPLORATORY-ONLY verdict, no `qa-*` files written.** Dispatch advances; no adopt attempt against a non-existent file.
- **[P2] Mixed branch:** some `qa-*` and some already-adopted `*.qa.*` present. Only `qa-*` acted on; `*.qa.*` untouched (idempotent).

## Dimension 2 — State transitions

- **[P0] No infinite loop after adoption.** Post-adoption `adoptedTests>0` -> re-dispatch returns `advance`, not `adopt-phase` again. Trace the full initial-PASS dispatch sequence terminates.
- **[P0] Post-fix PASS path unchanged.** `qaFixAttempts>0 && adoptedTests==0` still -> `adopt-phase`. Regression guard on the existing fix-loop adoption.
- **[P0] `detect-phase.sh` initial-PASS routing.** After the guard relaxation, `verdict=PASS && attempts==0 && adopted==0 && qa-* files exist` -> `phase=adopt` (not `phase=unknown`). And `attempts==0 && no qa-* files` must NOT route to adopt.
- **[P1] Full fix loop still terminal:** ISSUES-FOUND -> fix -> PASS -> adopt -> advance reaches finalize cleanly.
- **[P1] record-adopted-test vs git reality reconciled (AC-3).** After adoption, `adoptedTests` state array and on-disk `git mv` result agree. State "adopted" while git still shows `qa-*` (or vice versa) is a failure.

## Dimension 3 — Environment

- **[P0] Edge Case 17 lockstep preserved.** pytest (`qa-*.py`) / go-test (`qa-*.go`) globs stay ABSENT from FR-9; `adopt-qa-test.sh` still emits the structured `framework not supported in v1: pytest|go-test` stub. Mechanism A must not add those globs.
- **[P0] FR-13 sole-owner preserved.** All `qa-*` rename/deletion routes through `adopt-qa-test.sh` `git mv`. No new code path deletes/renames `qa-*` files directly.
- **[P1] Permanent QA-infra tests stay clear of FR-9.** `tests/bats/skills/<skill>/qa-dispatch.bats`, `qa-baseline.bats` etc. must not start tripping the gate (anchored globs only).
- **[P2] `git ls-files` base behavior.** Gate matches tracked files regardless of `origin/main` divergence (confirmed `git ls-files`, not `git diff`).

## Dimension 4 — Dependency failure

- **[P0] Adoption partial failure.** `adopt-qa-test.sh` fails on file 2 of 3 -> dispatch surfaces `pause:adoption-failed` with `adoptedTests` preserved (FR-5). Must NOT advance into a blocked finalize.
- **[P1] `run-adopt-loop.sh` exit 2 (no files) treated as clean.** Initial PASS with no qa-* files -> adopt loop exit 2 -> orchestrator treats as no-op and advances (does not pause/fail).
- **[P1] Missing peer-test path / unresolvable SUT.** Adopting a `qa-*` whose sibling target can't be resolved fails loudly (structured stub), not silently leaving the `qa-*` to trip FR-9 later.
- **[P2] #293 root removed.** With initial-PASS adoption in place, the finalize fork no longer faces un-adopted files and has no trigger to delete files to unblock itself.

## Dimension 5 — Cross-cutting

- **[P0] FR-9 still catches real orphans (regression).** A branch with a genuinely-orphaned `qa-*` file (abandoned fix loop, or a different workflow ID's leftover) STILL blocks finalize. Fix must not blanket-disable the gate.
- **[P0] Regression-test fixture (AC-4).** Test asserts an initial-PASS chain reaches finalize with `git ls-files 'tests/unit/qa-*.test.ts' 'tests/unit/qa-*.test.js' 'tests/bats/qa/qa-*.bats'` returning empty on the branch. Canonical leaves: `tests/bats/skills/orchestrating-workflows/qa-dispatch.bats` (dispatch branch) + a `tests/bats/skills/finalizing-workflow/` preflight test.
- **[P1] Documentation (AC-2).** Mechanism A documented where the QA lifecycle lives: `addressing-qa-findings/SKILL.md` relationship table, CLAUDE.md "QA Test Lifecycle" section, `references/qa-loop.md`. Docs match implemented behavior. Caveman Lite prose.
- **[P2] Idempotency / re-run safety.** Re-invoking dispatch or finalize after a successful initial-PASS adoption is a no-op; no double-adoption, no re-block.
- **[P2] Length/parity assertions** over dirs receiving `*.qa.*` siblings filter `*.qa.*` before counting (see `qa-BUG-016.test.ts` precedent).

---

## Out of Scope

- One-time cleanup of pre-existing accumulated orphan `qa-*` files (#266).
- Adding real pytest/go-test adoption dispatch (separate lockstep work; plan only guards the invariant is not broken).
- PR-backend specifics — deadlock is backend-independent (FR-9 is `git ls-files`).

---

## Notes

- Canonical naming: ephemeral `tests/unit/qa-*.test.ts|js`, `tests/bats/qa/qa-*.bats`; adopted siblings `{dir}/{base}.qa.{ext}` next to the peer test.
- FR-9 gate is `git ls-files` (verified `preflight-checks.sh:356`); adopted `*.qa.*` infix is NOT matched — only the `qa-*` prefix.
- `detect-phase.sh:66` current adopt guard: `[[ verdict==PASS && attempts -gt 0 && adopted_count == 0 ]]` — Mechanism A relaxes the `attempts -gt 0` clause for the initial-PASS-with-files case.

---
