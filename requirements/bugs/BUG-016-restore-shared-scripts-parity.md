# Bug: Restore shared-scripts parity by relocating QA bats fixture

## Bug ID

`BUG-016`

## GitHub Issue

[#260](https://github.com/lwndev/lwndev-marketplace/issues/260)

## Category

`regression`

## Severity

`critical`

## Description

CHORE-037 (PR #259) added a QA fixture at `tests/bats/shared/qa-CHORE-037-husky-hooks.bats`, raising the directory's `.bats` file count to 15. The shared-scripts parity assertion at `tests/unit/shared-scripts.test.ts:106` requires the count to equal `CANONICAL_SCRIPTS.length` (14), so `npm test` fails on `main` and every downstream PR fails until the parity is restored.

## Steps to Reproduce

1. Check out `main` at commit `8922972` (post-merge of PR #259).
2. Run `npm test` (or `npm run test:unit -- --testPathPatterns=shared-scripts`).
3. Observe the failure in `tests/unit/shared-scripts.test.ts > shared-scripts library: bats fixture count > should contain a .bats fixture per canonical script`:

   ```
   AssertionError: expected 15 to be 14
    ❯ tests/unit/shared-scripts.test.ts:106:30
   ```

## Expected Behavior

`npm test` passes on `main`. The parity assertion reflects a maintained 1:1 invariant between canonical shared scripts and their bats fixtures under `tests/bats/shared/`. QA fixtures (which are not script fixtures) live somewhere that does not perturb that invariant.

## Actual Behavior

`tests/unit/shared-scripts.test.ts:103-108` counts every `.bats` under `tests/bats/shared/` (15 files post-CHORE-037) and asserts the count equals `CANONICAL_SCRIPTS.length` (14). The assertion fails. CI runs 490 (PR #259) and 491 (post-merge `main`) both reported the same red. Every PR built against `main` will fail until the count is back to 14.

## Root Cause(s)

**RC-1:** **QA fixture placed in the parity-checked directory.** `tests/bats/shared/qa-CHORE-037-husky-hooks.bats` (added by commit `361002b`) is a QA fixture for the husky hook split, not a fixture for any canonical shared script. It was placed under `tests/bats/shared/` because CLAUDE.md's "Skill Authoring" guidance directs shell-script tests to `tests/bats/shared/<name>.bats` for shared/hook coverage, and "shared/hook" was the closest match for husky-hook QA. Neither the layout validator (`scripts/test-layout-rules.ts`) nor CLAUDE.md surfaces the parity invariant enforced at `tests/unit/shared-scripts.test.ts:106`, so the placement looked correct at authoring time. (See `tests/bats/shared/qa-CHORE-037-husky-hooks.bats`.)

## Affected Files

- `tests/bats/shared/qa-CHORE-037-husky-hooks.bats` — file to relocate (move out of the parity-checked directory)
- `tests/bats/qa/qa-CHORE-037-husky-hooks.bats` — new home for the QA fixture
- `tests/unit/shared-scripts.test.ts` — re-run to confirm parity assertion at line 106 passes

## Acceptance Criteria

- [x] `tests/bats/shared/qa-CHORE-037-husky-hooks.bats` no longer exists; the QA fixture lives at `tests/bats/qa/qa-CHORE-037-husky-hooks.bats` with identical content (RC-1)
- [x] `tests/bats/shared/` contains exactly 14 `.bats` files, one per entry in `CANONICAL_SCRIPTS` (RC-1)
- [x] `npm test` passes locally on the fix branch (RC-1)
- [x] The relocated fixture is exercised by `npm run test:bats` — i.e. the recursive `tests/bats` glob in `package.json` picks it up (RC-1)
- [ ] CI on `main` is green after the fix merges (RC-1)

## Completion

**Status:** `Pending`

**Completed:** YYYY-MM-DD

**Pull Request:** [#N](https://github.com/lwndev/lwndev-marketplace/pull/N)

## Notes

Issue #260 lists two options. Option (a) — relocate the QA fixture — is recommended and adopted here because it preserves the strong 1:1 parity invariant for shared scripts and gives QA fixtures a dedicated home. Option (b) (loosening the parity assertion to "every canonical script has a fixture, extras allowed") is rejected here because it weakens the invariant. Issue #262 will codify the canonical QA bats location and a scoped parity assertion; this fix is the unblocking step.

`test:bats` in `package.json` is `npx bats -r --jobs 8 --no-parallelize-within-files tests/bats`, so any subdirectory under `tests/bats/` is picked up automatically — no script change is required to keep the relocated fixture running. The layout validator at `scripts/test-layout-rules.ts:90` also accepts any `.bats` under `tests/bats/`, so the new `tests/bats/qa/` path is already allowed.
