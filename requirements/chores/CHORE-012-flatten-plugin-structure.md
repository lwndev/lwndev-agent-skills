# Chore: Flatten Plugin Structure

## Chore ID

`CHORE-012`

## GitHub Issue

[#29](https://github.com/lwndev/lwndev-marketplace/issues/29)

## Category

`refactoring`

## Description

Eliminate `src/` and `dist/` directories by moving plugins to a top-level `plugins/` directory in their final Claude Code-consumable structure. The build script becomes validate-only, and marketplace source paths point to committed directories.

## Affected Files

- `src/plugins/lwndev-sdlc/plugin.json` → `plugins/lwndev-sdlc/.claude-plugin/plugin.json`
- `src/plugins/lwndev-sdlc/README.md` → `plugins/lwndev-sdlc/README.md`
- `src/plugins/lwndev-sdlc/skills/*` → `plugins/lwndev-sdlc/skills/*`
- `scripts/lib/constants.ts`
- `scripts/lib/skill-utils.ts`
- `scripts/build.ts`
- `scripts/scaffold.ts`
- `scripts/__tests__/constants.test.ts`
- `scripts/__tests__/skill-utils.test.ts`
- `scripts/__tests__/build.test.ts`
- `scripts/__tests__/scaffold.test.ts`
- `scripts/__tests__/documenting-features.test.ts`
- `scripts/__tests__/creating-implementation-plans.test.ts`
- `scripts/__tests__/implementing-plan-phases.test.ts`
- `scripts/__tests__/documenting-chores.test.ts`
- `scripts/__tests__/executing-chores.test.ts`
- `scripts/__tests__/documenting-bugs.test.ts`
- `scripts/__tests__/executing-bug-fixes.test.ts`
- `.claude-plugin/marketplace.json`
- `.gitignore`
- `README.md`
- `CLAUDE.md`

## Acceptance Criteria

- [ ] `plugins/lwndev-sdlc/` contains `.claude-plugin/plugin.json`, `README.md`, and `skills/` with all 7 skill directories
- [ ] `src/` directory no longer exists
- [ ] `dist/` entry removed from `.gitignore`
- [ ] `build.ts` validates skills in-place without copying to a dist directory
- [ ] `scaffold.ts` writes new skills to `plugins/<name>/skills/`
- [ ] `constants.ts` uses `plugins` as source dir and has no output dir helpers
- [ ] `skill-utils.ts` no longer exports `pluginBuildExists()`
- [ ] `.claude-plugin/marketplace.json` source paths point to `./plugins/lwndev-sdlc`
- [ ] All tests pass (`npm test`)
- [ ] `npm run build` validates all skills successfully
- [ ] `README.md` and `CLAUDE.md` reflect the new structure

## Completion

**Status:** `Completed`

**Completed:** 2026-03-17

**Pull Request:** [#30](https://github.com/lwndev/lwndev-marketplace/pull/30)

## Notes

- This resolves the problem from issue #28 where marketplace source paths referenced the gitignored `dist/` directory
- The build script remains valuable as a CI validation gate
- `pluginBuildExists()` can be removed since there's no separate build output to check
