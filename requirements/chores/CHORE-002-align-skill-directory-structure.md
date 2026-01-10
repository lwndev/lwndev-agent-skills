# Chore: Align Skill Directory Structure with Spec

## Chore ID

`CHORE-002`

## Category

`refactoring`

## Description

Review and update skill directory structures in `src/skills/` to match the Agent Skills specification. Current skills use `reference/` (singular) and `templates/` directories, but the spec defines `references/` (plural) and `assets/` as the standard optional directories.

## Affected Files

- `src/skills/creating-implementation-plans/reference/` → `references/`
- `src/skills/creating-implementation-plans/templates/` → `assets/`
- `src/skills/documenting-chores/reference/` → `references/`
- `src/skills/documenting-chores/templates/` → `assets/`
- `src/skills/documenting-features/reference/` → `references/`
- `src/skills/documenting-features/templates/` → `assets/`
- `src/skills/executing-chores/reference/` → `references/`
- `src/skills/executing-chores/templates/` → `assets/`
- `src/skills/implementing-plan-phases/reference/` → `references/`
- `src/skills/managing-git-worktrees/reference/` → `references/`
- All `SKILL.md` files with internal links to these directories

## Acceptance Criteria

- [x] All `reference/` directories renamed to `references/`
- [x] All `templates/` directories renamed to `assets/`
- [x] All internal links in `SKILL.md` files updated to reflect new paths
- [x] `asm validate` passes for all skills
- [x] `npm run build` succeeds
- [x] All tests pass

## Notes

- The spec at `docs/agent-skills/agent-skills-specification.md` (lines 189-218) defines the standard optional directories as `scripts/`, `references/`, and `assets/`
- Consider whether `templates/` should remain as a separate convention or be consolidated into `assets/` per spec
- Update any documentation that references the old directory names
