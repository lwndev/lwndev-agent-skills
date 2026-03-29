# Chore: Align Pre-commit Lint With CI

## Chore ID

`CHORE-028`

## GitHub Issue

[#99](https://github.com/lwndev/lwndev-marketplace/issues/99)

## Category

`configuration`

## Description

Add full `npm run lint` and `npm run format:check` steps to the pre-commit hook so that local lint and format coverage matches CI. Currently, the pre-commit hook only runs `lint-staged` (which lints/formats staged files), while CI runs `eslint scripts/` and `prettier --check scripts/` against all files. This mismatch allows pre-existing issues on `main` to pass locally but fail in CI when an unrelated PR triggers a build.

## Affected Files

- `.husky/pre-commit`

## Acceptance Criteria

- [x] Pre-commit hook runs `npm run lint` (full project lint) in addition to `lint-staged`
- [x] Pre-commit hook runs `npm run format:check` (full project format check) in addition to `lint-staged`
- [x] The lint and format steps in the pre-commit hook match the corresponding CI steps
- [x] All existing pre-commit steps (`lint-staged`, `npm test`, `npm audit --audit-level=high`) are preserved
- [x] Pre-commit hook executes successfully on a clean working tree

## Completion

**Status:** `In Progress`

**Completed:** 2026-03-29

**Pull Request:** [#100](https://github.com/lwndev/lwndev-marketplace/pull/100)

## Notes

- `lint-staged` is still useful for auto-fixing staged files before commit; the full lint/format steps serve as a safety net to catch project-wide issues
- PR #98 failed CI due to a Prettier formatting issue in `constants.test.ts` that was already on `main` but never staged in the PR -- this is the motivating incident
- CI also runs `npm run validate` (plugin validation), but this is intentionally excluded from the pre-commit hook -- validation is slower and plugin structure is unlikely to drift between commits
- CI runs `npm audit` without flags; pre-commit runs `npm audit --audit-level=high`. This divergence is out of scope for CHORE-028 (AC3 targets lint and format steps only)
- Intended pre-commit ordering: `lint-staged` (auto-fix staged files) → `npm run lint` (full project lint) → `npm run format:check` (full format check) → `npm test` → `npm audit`
