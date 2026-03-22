# Chore: Acceptance Criteria Checkoff During Execution

## Chore ID

`CHORE-018`

## GitHub Issue

[#58](https://github.com/lwndev/lwndev-marketplace/issues/58)

## Category

`refactoring`

## Description

Update the `executing-chores`, `executing-bug-fixes`, and `implementing-plan-phases` skills to consistently check off acceptance criteria checkboxes (`- [ ]` to `- [x]`) in their source requirement/plan documents as each criterion is verified or completed during execution. Currently, checkboxes remain unchecked even after the work is done, making progress tracking and completeness verification harder.

## Affected Files

- `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-chores/references/workflow-details.md`
- `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-bug-fixes/references/workflow-details.md`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md`

## Acceptance Criteria

- [x] `executing-chores` instructions require checking off each acceptance criterion in the chore document as it is verified
- [x] `executing-bug-fixes` instructions require checking off each acceptance criterion in the bug document as it is verified
- [x] `implementing-plan-phases` instructions require checking off each deliverable in the implementation plan as it is completed
- [x] All three skills follow a consistent pattern for when and how checkboxes are updated

## Completion

**Status:** `Completed`

**Completed:** 2026-03-22

**Pull Request:** [#60](https://github.com/lwndev/lwndev-marketplace/pull/60)

## Notes

- The checkbox update should happen at the point each criterion is verified, not in a batch at the end
- For `implementing-plan-phases`, the relevant checkboxes are phase deliverables rather than acceptance criteria
- All three skills should use the same edit pattern (e.g., `- [ ]` to `- [x]`) for consistency
