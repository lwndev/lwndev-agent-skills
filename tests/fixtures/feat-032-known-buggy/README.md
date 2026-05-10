# FEAT-032 known-buggy fixture

End-to-end fixture for the FEAT-032 NFR-4 acceptance criterion: drives the
deterministic glue of `ISSUES-FOUND -> addressing-qa-findings (fix) -> re-QA
PASS -> addressing-qa-findings (adopt) -> finalize` against a real on-disk
project layout.

## ID

The fixture uses the synthetic `FEAT-999` workflow ID so it satisfies the
`^(FEAT|CHORE|BUG)-[0-9]+$` regex enforced by `qa-dispatch.sh` and
`workflow-state.sh init`. Real product workflows will not collide because the
fixture lives under `tests/fixtures/` and is only consumed by Bats drivers in
a copied tempdir.

## Layout

- `src/buggy-fn.ts` — known-buggy production code. `validateInput` rejects the
  empty string but not whitespace-only input. The fix-phase test patches this
  file to trim before checking.
- `tests/unit/buggy-fn.test.ts` — peer test for the SUT. Covers the happy path
  and the empty-string path; passes against the bug.
- `tests/unit/qa-input-validation.test.ts` — pre-authored QA test. Imports the
  same SUT as the peer test so `adopt-qa-test.sh` resolves the peer
  deterministically. Adopts to `tests/unit/buggy-fn.qa.test.ts`.
- `package.json`, `vitest.config.ts`, `tsconfig.json` — minimal vitest project
  (no node_modules; the e2e test does not run vitest, only the deterministic
  glue scripts).
- `.sdlc/qa/.executing-qa-baseline-FEAT-999` — re-QA marker required by
  `detect-re-qa-mode.sh`.
- `seed/FEAT-999-state.json` — workflow-state seed (verdict `ISSUES-FOUND`,
  `qaFixAttempts: 0`, `adoptedTests: []`, `qaLoopCap: 2`). The fixture's own
  `.gitignore` matches `.sdlc/workflows/` to mirror the ephemeral-state
  posture, so the seed is tracked under `seed/` and copied to
  `.sdlc/workflows/FEAT-999.json` by the Bats `setup()` after `cp -R`.
- `qa/test-results/QA-results-FEAT-999.md` — pre-existing QA artifact
  so `check-fix-prechecks.sh` passes.

## Intended outcomes

After driving the loop end-to-end against a copy of this fixture, the test
asserts:

- `qa-dispatch.sh FEAT-999` emits `dispatch=fix-phase` initially.
- `qa-dispatch.sh FEAT-999` emits `dispatch=adopt-phase` after the
  verdict transitions to `PASS` and `qaFixAttempts > 0`.
- `qa-dispatch.sh FEAT-999` emits `dispatch=advance` after adoption
  records the moved path.
- `run-adopt-loop.sh` prints `tests/unit/buggy-fn.qa.test.ts` to stdout.
- After adoption, no tracked file matches the FR-9 v1 glob set
  (`tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`,
  `tests/bats/qa/qa-*.bats`).
- The negative variant (skipping the adopt step) leaves the QA file in place
  and trips the FR-9 safety-net in `preflight-checks.sh` with the verbatim
  error message.

## Why a copied fixture

The Bats driver runs `git mv` against the QA test, so it must operate on a
mutable git working tree. The driver copies the fixture into a temp dir and
runs `git init` there to avoid mutating the source-of-truth fixture under
`tests/fixtures/`.
