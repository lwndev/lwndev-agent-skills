# Chore: Make Phase Commit-Push Mandatory

## Chore ID

`CHORE-030`

## GitHub Issue

[#97](https://github.com/lwndev/lwndev-marketplace/issues/97)

## Category

`refactoring`

## Description

Strengthen the commit-and-push instruction in the `implementing-plan-phases` skill so that Claude always commits and pushes at phase end without prompting the user. The current language is not forceful enough, causing Claude to sometimes present committing as optional.

## Affected Files

- `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/workflow-example.md`

## Acceptance Criteria

- [x] SKILL.md commit-and-push step uses explicit "always" / "do not ask" language
- [x] step-details.md reinforces mandatory commit-push with no-confirmation directive
- [x] workflow-example.md reflects the mandatory commit-push behavior
- [x] Commit-push is listed as a blocking requirement before phase status can be updated to Complete
- [x] No duplicate commit-push instructions exist in `orchestrating-workflows` (confirmed: none exist)
- [x] Validation passes (`npm run validate`)

## Completion

**Status:** `Completed`

**Completed:** 2026-03-29

**Pull Request:** [#110](https://github.com/lwndev/lwndev-marketplace/pull/110)

## Notes

- Follows up on CHORE-017 which added the commit-and-push step; this chore strengthens the language to prevent Claude from treating it as optional.
- The `orchestrating-workflows` skill was checked and contains no commit/push instructions, so no cleanup is needed there.
- This is a wording/instruction change only — no code logic changes.
