# Bug: adopt-qa-test exactly-one-peer too strict

<!--
Replace [Brief Title] with a concise description (2-5 words)
Examples: "Auth Token Expiry Crash", "CSV Export Missing Columns", "Memory Leak in Polling"
-->

## Bug ID

`BUG-025`

<!--
Replace XXX with the next available number.
Check requirements/bugs/ for existing bugs and increment.
-->

## GitHub Issue

[#304](https://github.com/lwndev/lwndev-marketplace/issues/304)

<!--
Optional: Link to GitHub issue if one exists.
If no issue exists, either:
- Create one and link it here
- Remove this section entirely
-->

## Category

`logic-error`

<!--
Choose ONE category that best describes this bug:
- runtime-error: Crashes, unhandled exceptions, fatal errors
- logic-error: Incorrect behavior, wrong calculations, bad state
- ui-defect: Visual glitches, layout issues, rendering problems
- performance: Slowness, memory leaks, resource exhaustion
- security: Vulnerabilities, auth bypasses, data exposure
- regression: Previously working functionality that broke
-->

## Severity

`high`

<!--
Choose ONE severity level:
- critical: Application unusable, data loss, security breach
- high: Major feature broken, no workaround
- medium: Feature impaired, workaround exists
- low: Minor issue, cosmetic, edge case
-->

## Description

`adopt-qa-test.sh` requires exactly one resolvable peer test per QA file. Adversarial QA tests span multiple SUTs by design (cross-cutting, inputs, dependency-failure, state-transitions dimensions), so ~80% fail adoption with `multiple plausible peer tests found; expected exactly one`. This wedges the `qa-dispatch.sh` post-fix-PASS adopt branch: `adoptedTests` never populates, so dispatch keeps returning `adopt-phase` with no escape.

## Steps to Reproduce

1. Author an adversarial QA test that imports two or more SUTs, each with an existing peer test — e.g. `tests/unit/qa-foo.test.ts` importing both `../../scripts/lib/a.ts` and `../../scripts/lib/b.ts` where `a.test.ts` and `b.test.ts` both exist. (Or a single SUT whose base name matches multiple peers under `tests/`, which trips the `<<MULTI>>` parallel-test-root sentinel.)
2. Drive QA to a post-fix PASS (`ISSUES-FOUND` -> fix-phase -> re-QA `PASS`) so `qa-dispatch.sh` routes to `adopt-phase` (FR-7 row 5).
3. `addressing-qa-findings` (adopt mode) calls `adopt-qa-test.sh <qa-path>`.
4. Observe exit 2 with `adopt-qa-test: <path>: multiple plausible peer tests found; expected exactly one`. `adoptedTests` stays empty; `qa-dispatch.sh` re-routes to `adopt-phase` indefinitely.

## Expected Behavior

`adopt-qa-test.sh` tolerates multi-SUT QA tests. It requires at least one resolvable peer and, on ambiguity, picks deterministically (the lexicographically-first peer by full repo-relative path) so adoption always produces a single `*.qa.*` sibling and exits 0. The QA loop self-heals — no state surgery needed.

## Actual Behavior

Adoption exits 2 (`multiple plausible peer tests found; expected exactly one`) for both the vitest/jest and bats dispatch paths whenever a QA test resolves more than one distinct peer. The only way past is manual state surgery — populating `adoptedTests` in `.sdlc/workflows/<ID>.json` by hand without performing the `git mv` rename. A dry-run sweep of 19 real `qa-*.test.ts` files: 15 (~80%) failed with multiple plausible peers.

## Root Cause(s)

1. `dispatch_vitest_jest` in `plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts/adopt-qa-test.sh:297-304` treats more than one distinct resolved peer as a fatal error (`seen_count > 1`, or the parallel-test-root `<<MULTI>>` sentinel set at lines 245-251), emitting `multiple plausible peer tests found; expected exactly one` and exiting 2. The "exactly one peer" assumption contradicts adversarial QA tests, which import multiple SUTs by design.
2. `dispatch_bats` in `plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts/adopt-qa-test.sh:404-407` carries the identical exactly-one-peer constraint for the bats path (`seen_count > 1` -> `multiple plausible peer .bats tests found; expected exactly one`, exit 2), so multi-`load`/multi-`source` QA bats tests fail adoption the same way.

## Affected Files

- `plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts/adopt-qa-test.sh`
- `tests/bats/skills/addressing-qa-findings/adopt-qa-test.bats`

## Acceptance Criteria

- [x] `dispatch_vitest_jest` adopts a QA test that resolves multiple distinct peers: it picks the lexicographically-first peer by full repo-relative path deterministically and `git mv`s the QA file to that peer's `*.qa.test.<ext>` sibling, exiting 0 (RC-1)
- [x] The parallel-test-root `<<MULTI>>` ambiguity (one SUT base name matching multiple peers under `tests/`) is resolved deterministically (lexicographically-first full path) instead of failing, exiting 0 (RC-1)
- [x] `dispatch_bats` adopts a QA bats test that resolves multiple distinct peers: it picks the lexicographically-first peer `.bats` by full repo-relative path deterministically and `git mv`s to the `*.qa.bats` sibling, exiting 0 (RC-2)
- [x] The genuine no-peer case (zero resolvable peers — including `<<MULTI>>` set with no singular peer, i.e. `multi_seen=1` and `seen_count=0`) still exits 2 with the existing `no existing peer test found` / `no existing peer .bats test found` reason — only multi-peer-with-at-least-one-resolved ambiguity changes behavior (RC-1, RC-2)
- [x] The exit-code contract comment in `adopt-qa-test.sh` header (lines 32-41) is updated to remove "multiple plausible peers" from the exit-2 reasons, reflecting the new tolerate-and-pick behavior (RC-1, RC-2)
- [x] `tests/bats/skills/addressing-qa-findings/adopt-qa-test.bats` covers the multi-SUT vitest/jest case, the `<<MULTI>>` parallel-root case, the multi-load bats case, and the unchanged no-peer failure; the existing test asserting exit 2 for multi-SUT imports is rewritten to assert the new exit-0 + lexicographically-first sibling behavior (RC-1, RC-2)

## Completion

**Status:** `Completed`

**Completed:** 2026-06-01

**Pull Request:** [#312](https://github.com/lwndev/lwndev-marketplace/pull/312)

<!--
Optional: Brief summary of implementation if it differs from the plan
or if there are noteworthy details for future reference.
-->

## Notes

- Fix approach: Option 1 from issue #304 (tolerate multi-SUT; deterministic pick). Option 2 (skip-adopt opt-out in `qa-dispatch.sh`) was rejected — Option 1 self-heals and keeps the adopt model intact.
- `run-adopt-loop.sh` needs no change: it aborts on the first non-zero exit from `adopt-qa-test.sh`. Making multi-peer exit 0 means the loop no longer aborts on multi-SUT tests — the correct behavior falls out automatically.
- The fix lands in repo source (`plugins/lwndev-sdlc/skills/...`). The installed plugin cache is unchanged until a release, so a workflow running off the cache will not see the new behavior on the same run.
- Determinism tiebreak is defined as the lexicographically-first peer by **full repo-relative path** (not basename) so two correct implementations cannot diverge.
