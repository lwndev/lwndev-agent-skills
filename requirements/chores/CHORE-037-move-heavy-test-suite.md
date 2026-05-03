# Chore: Move heavy test suite from pre-commit to pre-push

## Chore ID

`CHORE-037`

## GitHub Issue

[#257](https://github.com/lwndev/lwndev-marketplace/issues/257)

## Category

`configuration`

## Description

Split the husky hook tiers so `.husky/pre-commit` runs only fast checks (lint-staged, lint, format) and a new `.husky/pre-push` runs the heavyweight gate (`npm test`, `npm audit`, `npm run validate`). Eliminates the multi-minute per-commit tax that punishes marker, doc, and WIP commits and triggers an orchestrator stop-hook polling spiral.

## Affected Files

- `.husky/pre-commit` (modified — drop heavy invocations)
- `.husky/pre-push` (new — full test/audit/validate gate)
- `README.md` (modified — Development section documents the hook split)

## Acceptance Criteria

- [x] `.husky/pre-commit` runs `npx lint-staged`, `npm run lint`, and `npm run format:check` only; no `npm test`, `npm audit`, or `npm run validate` invocation
- [x] `.husky/pre-push` exists, is executable, and runs `npm test`, `npm audit --audit-level=high`, and `npm run validate` in that order
- [x] A doc-only commit (e.g., editing a `requirements/**/*.md` file) completes in under 5 seconds locally on the maintainer's machine
- [x] `git push` of a branch containing a deliberately failing Vitest or Bats test is blocked by the pre-push hook (non-zero exit prevents the push)
- [x] `.github/workflows/ci.yml` is unchanged (CI remains the authoritative gate)
- [x] The README "Development" section documents the split: pre-commit scope, pre-push scope, and the rationale that CI is still authoritative
- [x] The existing PreToolUse layout-validator hook (`scripts/hooks/validate-test-layout-hook.ts`) is untouched — it operates on tool calls, not git, and is independent of this hook split

## Completion

**Status:** `Complete`

**Completed:** 2026-05-03

**Pull Request:** [#259](https://github.com/lwndev/lwndev-marketplace/pull/259)

## Notes

- Path-based scoping ("skip tests for markdown-only commits") was considered and rejected because this repo has load-bearing markdown fixtures (SKILL.md files consumed by `validate()`, requirement-doc fixtures parsed by skill scripts, templates under `assets/`); a markdown change can legitimately break tests, so a static include/exclude rule is unsafe.
- Tradeoff accepted: a locally broken commit can exist between push boundaries. `git bisect` is unaffected and broken state never reaches a shared branch because pre-push and CI both gate.
- Lint-staged config in `package.json` is unchanged; pre-commit continues to invoke it as today.
