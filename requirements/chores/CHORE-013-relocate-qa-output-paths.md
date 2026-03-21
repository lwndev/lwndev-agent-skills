# Chore: Relocate QA Output Paths

## Chore ID

`CHORE-013`

## GitHub Issue

[#33](https://github.com/lwndev/lwndev-marketplace/issues/33)

## Category

`refactoring`

## Description

QA skills currently save test plans to `test/test-plans/` and results to `test/test-results/`, which conflicts with projects that use the common `tests/` directory convention. Relocate QA output paths to a distinct location that avoids ambiguity with project test directories.

## Affected Files

- `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template.md`
- `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md`

## Acceptance Criteria

- [ ] Test plans are no longer written to `test/test-plans/`
- [ ] Test results are no longer written to `test/test-results/`
- [ ] New output paths do not conflict with common project directory conventions (`test/`, `tests/`, `src/`, `lib/`)
- [ ] All path references in documenting-qa SKILL.md are updated to the new location
- [ ] All path references in executing-qa SKILL.md are updated to the new location
- [ ] Asset templates reflect the new output paths
- [ ] Plugin validates successfully after changes (`npm run validate`)

## Completion

**Status:** `Completed`

**Completed:** 2026-03-20

**Pull Request:** [#36](https://github.com/lwndev/lwndev-marketplace/pull/36)

## Notes

- The issue proposes three options: root-level (`test-plans/`, `test-results/`), distinct parent (`qa/test-plans/`, `qa/test-results/`), or nested under requirements (`requirements/qa/`). Final path choice should be evaluated during implementation.
- Split from issue #32; original feature is FEAT-004 / #23.
