# Chore: Multi-Plugin Marketplace Restructure

## Chore ID

`CHORE-011`

## GitHub Issue

[#26](https://github.com/lwndev/lwndev-marketplace/issues/26)

## Category

`refactoring`

## Description

Restructure the repository from single-plugin hardcoded layout to a multi-plugin marketplace architecture. Move skills inside the plugin source directory (`src/plugins/lwndev-sdlc/skills/`), parameterize build tooling to discover and process N plugins, and update documentation to reflect the marketplace-centric framing.

## Affected Files

- `src/plugin/plugin.json` → `src/plugins/lwndev-sdlc/plugin.json`
- `src/plugin/README.md` → `src/plugins/lwndev-sdlc/README.md`
- `src/skills/*` → `src/plugins/lwndev-sdlc/skills/*`
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
- `README.md`
- `CLAUDE.md`
- `.claude-plugin/marketplace.json` (verification only)

## Acceptance Criteria

- [ ] `src/plugins/lwndev-sdlc/` contains `plugin.json`, `README.md`, and `skills/` with all 7 skill directories
- [ ] `src/plugin/` and `src/skills/` no longer exist
- [ ] `constants.ts` exports `PLUGINS_SOURCE_DIR` and parameterized helper functions instead of hardcoded single-plugin constants
- [ ] `skill-utils.ts` exports `getSourcePlugins()` and accepts `pluginName` parameter on `getSourceSkills()` and `pluginBuildExists()`
- [ ] `build.ts` discovers and builds all plugins under `src/plugins/`
- [ ] `scaffold.ts` prompts for plugin selection when multiple plugins exist
- [ ] `npm run build` produces the same `dist/lwndev-sdlc-plugin/` output as before
- [ ] All tests pass (`npm test`)
- [ ] `README.md` is marketplace-centric, not plugin-centric
- [ ] `CLAUDE.md` reflects the new directory structure and architecture
- [ ] Marketplace manifest source paths resolve to valid built plugin directories

## Completion

**Status:** `In Progress`

**Completed:** YYYY-MM-DD

**Pull Request:** [#N](https://github.com/lwndev/lwndev-marketplace/pull/N)

## Notes

- Phases 1-3 (file moves, code changes, test updates) must ship as a single PR to keep CI green
- Phase 4 (README/CLAUDE.md updates) and Phase 5 (marketplace validation test) can be independent follow-up PRs
- The `dist/` output structure is unchanged — only the source layout and tooling change
- See issue #26 for the full phased implementation plan
