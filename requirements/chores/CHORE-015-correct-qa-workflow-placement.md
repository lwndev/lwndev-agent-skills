# Chore: Correct QA Workflow Placement

## Chore ID

`CHORE-015`

## GitHub Issue

[#46](https://github.com/lwndev/lwndev-marketplace/issues/46)

## Category

`documentation`

## Description

Correct the placement of `documenting-qa` and `executing-qa` in the SDLC workflow chains. They are currently shown as a standalone 4th chain but should be integrated into the three main chains: `documenting-qa` runs after `reviewing-requirements` (before execution), and `executing-qa` runs after execution (as a final verification gate).

## Affected Files

- `README.md`
- `CLAUDE.md`
- `plugins/lwndev-sdlc/README.md`
- `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`

## Acceptance Criteria

- [ ] Workflow chains show 3 chains (not 4) with QA steps integrated
- [ ] `documenting-qa` is positioned after `reviewing-requirements` and before execution/implementation in all references
- [ ] `executing-qa` is positioned after execution steps in all references
- [ ] `documenting-qa` SKILL.md "When to Use" reflects its pre-execution role
- [ ] All skill Relationship tables reflect the corrected workflow
- [ ] `documenting-*` skills recommend `documenting-qa` after reviewing-requirements
- [ ] `executing-*` skills recommend `executing-qa` after execution
- [ ] No references to a standalone "QA Validation" chain remain
- [ ] `npm run validate` passes (10/10 skills)
- [ ] `npm test` passes

## Completion

**Status:** `Completed`

**Completed:** 2026-03-21

**Pull Request:** [#47](https://github.com/lwndev/lwndev-marketplace/pull/47)

## Notes

See implementation plan at `/Users/leif/.claude/plans/snuggly-leaping-zephyr.md` for detailed file-by-file changes.
