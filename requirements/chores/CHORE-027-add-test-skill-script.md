# Chore: Add test-skill Utility Script

## Chore ID

`CHORE-027`

## GitHub Issue

[#95](https://github.com/lwndev/lwndev-marketplace/issues/95)

## Category

`configuration`

## Description

Add a TypeScript utility script that copies plugin skills or agents into project scope (`.claude/skills/` or `.claude/agents/`) for local testing before deploying the plugin. This is needed during development of the workflow orchestration feature (#89, #90, #91) to test new and modified skills locally.

## Affected Files

- `scripts/test-skill.ts`
- `scripts/lib/constants.ts`
- `scripts/__tests__/test-skill.test.ts`
- `scripts/__tests__/constants.test.ts`
- `package.json`

## Acceptance Criteria

- [x] `scripts/test-skill.ts` exists with CLI argument parsing (`--plugin`, `--agent`, `--remove`, `--help`)
- [x] Script copies full skill directories from `plugins/{plugin}/skills/{name}/` to `.claude/skills/{name}/`
- [x] Script copies agent `.md` files from `plugins/{plugin}/agents/{name}.md` to `.claude/agents/{name}.md`
- [x] `--remove` flag cleans up copied skill or agent from project scope
- [x] Plugin is auto-detected when only one exists; `--plugin` flag for explicit selection
- [x] Overwrites existing destination with warning
- [x] Fails gracefully with available names listed when skill/agent not found
- [x] `npm run test-skill` script added to `package.json`
- [x] `PROJECT_SKILLS_DIR`, `PROJECT_AGENTS_DIR`, `getPluginAgentsDir()` added to `scripts/lib/constants.ts`
- [x] Tests cover copy, overwrite, remove, error handling, and plugin auto-detection for both skills and agents
- [x] All existing tests continue to pass

## Completion

**Status:** `Completed`

**Completed:** 2026-03-29

**Pull Request:** [#96](https://github.com/lwndev/lwndev-marketplace/pull/96)

## Notes

- This script supports the workflow orchestration work tracked in #89, #90, #91
- The orchestrator skill (`orchestrating-workflows`) will need to be tested locally before being added to the plugin
