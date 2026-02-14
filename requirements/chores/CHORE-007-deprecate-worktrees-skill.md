# Chore: Deprecate managing-git-worktrees Skill

## Chore ID

`CHORE-007`

## GitHub Issue

[#12](https://github.com/lwndev/lwndev-agent-skills/issues/12)

## Category

`cleanup`

## Description

Deprecate and remove the `managing-git-worktrees` skill from the repository. The skill is no longer needed in the project's skill portfolio, and removing it reduces maintenance burden and keeps the skill set focused on actively used workflows.

## Affected Files

- `src/skills/managing-git-worktrees/` (entire directory removal)
- `CLAUDE.md` (remove references to managing-git-worktrees)
- `dist/` (remove any build artifacts for this skill)
- `scripts/__tests__/build.test.ts` (remove assertion for `managing-git-worktrees.skill`)

## Acceptance Criteria

- [ ] `src/skills/managing-git-worktrees/` directory is deleted
- [ ] Skill is uninstalled from any active scopes
- [ ] `CLAUDE.md` no longer references `managing-git-worktrees`
- [ ] No build artifacts remain in `dist/` for this skill
- [ ] All tests pass
- [ ] Build script runs successfully

## Completion

**Status:** `Completed`

**Completed:** 2026-02-14

**Pull Request:** [#16](https://github.com/lwndev/lwndev-agent-skills/pull/16)

## Notes

- The skill count in `CLAUDE.md` was updated from "six" to "five" existing skills
- The workflow chain listing was updated to remove the `managing-git-worktrees` entry
- The skill was only installed at personal scope (`~/.claude/skills/`); no project-scope installation existed
- `build.test.ts` had an explicit `toContain('managing-git-worktrees.skill')` assertion that was not identified in the original scope — removal was required for tests to pass
