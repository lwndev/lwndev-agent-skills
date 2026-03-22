# Chore: Add PR Creation to Implementing Plan Phases

## Chore ID

`CHORE-021`

## GitHub Issue

[#42](https://github.com/lwndev/lwndev-marketplace/issues/42)

## Category

`refactoring`

## Description

Enhance the implementing-plan-phases skill to create a pull request after all plan phases are complete. The executing-chores and executing-bug-fixes skills both include an explicit PR creation step with a dedicated PR template, but implementing-plan-phases currently ends at commit/push without creating a PR, leaving phases committed but unmerged.

## Affected Files

- `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` — added PR creation step to workflow
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/assets/` — new directory (created)
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/assets/pr-template.md` — new PR template (created)
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` — added Step 12 details
- `scripts/__tests__/implementing-plan-phases.test.ts` — added tests for PR template and PR creation step

## Acceptance Criteria

- [x] SKILL.md includes a PR creation step after all phases are complete
- [x] A `pr-template.md` asset exists in `assets/` with a structure consistent with the executing-chores and executing-bug-fixes templates
- [x] PR template includes a link to the implementation plan document
- [x] PR template includes `Closes #N` for GitHub issue linking
- [x] Plugin validates successfully (`npm run validate`)
- [x] Workflow aligns with executing-chores and executing-bug-fixes PR creation patterns

## Completion

**Status:** `Completed`

**Completed:** 2026-03-22

**Pull Request:** [#65](https://github.com/lwndev/lwndev-marketplace/pull/65)

## Notes

- The executing-chores and executing-bug-fixes PR templates share a common structure: document link, summary, changes, testing checklist, and `Closes #N` in the related section. The new template should follow this same pattern adapted for implementation plans.
- The bug-fixes template adds root cause traceability sections; the plan-phases template may want to include a phase completion summary instead.
