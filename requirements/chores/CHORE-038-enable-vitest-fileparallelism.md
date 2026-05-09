# Chore: Enable Vitest fileParallelism

## Chore ID

`CHORE-038`

## GitHub Issue

[#271](https://github.com/lwndev/lwndev-marketplace/issues/271)

## Category

`configuration`

## Description

Flip `fileParallelism: false` -> `true` in `vitest.config.ts` to cut unit-test wall time ~4.4x (58.5s -> 13.5s on the reference machine). Isolate the 3 test files that currently mutate the real `plugins/` tree so parallel runs stay deterministic, and update the `CLAUDE.md` Key Patterns note to reflect the new default.

## Affected Files

- `vitest.config.ts` — flip `fileParallelism` to `true`
- `tests/unit/scaffold.test.ts` — currently writes `test-scaffold-skill/` and `test-scaffold-template/` into `plugins/lwndev-sdlc/skills/`; route writes through `mkdtemp` or mark `describe.sequential`
- `tests/unit/validate-test-layout.test.ts` — mutates real `plugins/` tree; same isolation choice
- `tests/unit/build.test.ts` — mutates real `plugins/` tree; same isolation choice
- `CLAUDE.md` — update the Key Patterns bullet that documents the sequential-run rationale

## Acceptance Criteria

- [x] `vitest.config.ts:14` set to `fileParallelism: true`
- [x] The 3 listed test files no longer mutate the real `plugins/` tree concurrently — either rerouted to `mkdtemp` or marked with `describe.sequential` / `test.sequential`
- [x] `npm run test:unit` wall time on a clean checkout ≤ 20s
- [x] `npm run test:unit` pass/fail count is identical to a baseline sequential run on the same commit (no new failures introduced by parallelization)
- [x] 10 consecutive `npm run test:unit` runs produce identical results (no new flake)
- [x] `CLAUDE.md` Key Patterns note no longer claims tests run sequentially; it accurately describes the new isolation strategy

## Completion

**Status:** `Complete`

**Completed:** 2026-05-09

**Pull Request:** [#274](https://github.com/lwndev/lwndev-marketplace/pull/274)

## Notes

- Issue #271 reports 1534 passed / 55 failed in both modes on `main` at `9b16f84`. The 55 failures are pre-existing and tracked separately — do not attempt to fix them as part of this chore.
- 29 of 53 unit-test files already use `mkdtemp`/`os.tmpdir()`. Most other `PLUGINS_DIR` references are read-only path lookups, so the parallelism risk is concentrated in the 3 files listed above.
- Prefer `mkdtemp` isolation over `describe.sequential` when feasible — it's the long-term path documented in the issue.
