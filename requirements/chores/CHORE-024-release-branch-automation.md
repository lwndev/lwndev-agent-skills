# Chore: Automate Release Branch Creation

## Chore ID

`CHORE-024`

## GitHub Issue

[#49](https://github.com/lwndev/lwndev-marketplace/issues/49)

## Category

`refactoring`

## Description

The release script (`npm run release`) commits directly to whatever branch is currently checked out. During the v1.3.0 release, the release commit landed on `main` and had to be manually moved to a release branch after the fact. The script should automatically create a `release/<plugin>-v<version>` branch when run from `main`, refuse to proceed if the branch already exists, and commit in place when already on a non-main branch. The `releasing-plugins` skill should be updated to remove the manual branch creation step.

## Affected Files

- `scripts/release.ts`
- `scripts/lib/git-utils.ts`
- `scripts/__tests__/release.test.ts`
- `.claude/skills/releasing-plugins/SKILL.md`

## Acceptance Criteria

- [x] Release script creates `release/<plugin>-v<version>` branch when run from `main`
- [x] Release script errors if on `main` and branch creation is not possible (e.g., branch already exists)
- [x] Release script commits in place when already on a non-main branch
- [x] `releasing-plugins` skill Phase 1 instructions updated to reflect automated branching
- [x] Skill no longer requires manual branch creation before running the script

## Completion

**Status:** `Completed`

**Completed:** 2026-03-28

**Pull Request:** [#81](https://github.com/lwndev/lwndev-marketplace/pull/81)

## Notes

- Related to `CHORE-016-release-skill-stop-hook.md`, which added the Stop hook and manual branch creation step to the skill. This chore moves the branching responsibility from the skill (human step) into the script (automated step).
- The script already uses `execSync` for git operations (staging and committing), so adding branch creation follows the existing pattern.
- The `release-tag.ts` script is unaffected — it runs on `main` after merge and does not need branching logic.
