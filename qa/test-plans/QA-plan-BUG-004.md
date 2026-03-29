# QA Test Plan: Stop Hook Path Resolution Fix

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-BUG-004 |
| **Requirement Type** | BUG |
| **Requirement ID** | BUG-004 |
| **Source Documents** | `requirements/bugs/BUG-004-stop-hook-path-resolution.md` |
| **Date Created** | 2026-03-29 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/orchestrating-workflows.test.ts` — "should have hooks field with Stop command hook" | Verifies SKILL.md frontmatter contains a Stop hook with `type: command` | PENDING |
| `scripts/__tests__/orchestrating-workflows.test.ts` — "should have stop-hook.sh" | Verifies `stop-hook.sh` exists at the expected path | PENDING |
| `scripts/__tests__/orchestrating-workflows.test.ts` — "should pass validate() with all checks" | Validates the skill via `ai-skills-manager` | PENDING |
| `scripts/__tests__/orchestrating-workflows.test.ts` — stop hook behavior tests (6 tests) | Verifies exit codes for various workflow states (no .active, empty .active, in-progress, paused, complete, stale, failed) | PENDING |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Verify Stop hook command in SKILL.md frontmatter uses `${CLAUDE_PLUGIN_ROOT}` prefix instead of bare relative path | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | RC-1, RC-2, AC-1 | High | -- |
| Verify Stop hook command path resolves to `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/stop-hook.sh` | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | AC-1, AC-3 | High | -- |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No existing test validates that the hook command path is anchored by an environment variable — the current test only checks that a Stop hook of `type: command` exists | `scripts/__tests__/orchestrating-workflows.test.ts:43-47` | RC-1, RC-2 | Update or add a test that asserts the command field contains `${CLAUDE_PLUGIN_ROOT}` |
| Runtime path resolution cannot be tested in the unit test suite (requires Claude Code hook execution with plugin installed) | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:10` | AC-2 | Manual verification by invoking the skill as a plugin and observing stop hook behavior |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| RC-1 | Hook command uses bare relative path `scripts/stop-hook.sh` | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:10` — `command` field in frontmatter hooks section | Code review: verify `command` field no longer uses bare relative path | -- |
| RC-2 | No environment variable anchors the path; should use `${CLAUDE_PLUGIN_ROOT}` | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:10` — `command` field should be `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/stop-hook.sh` | Code review + automated test: verify command contains `${CLAUDE_PLUGIN_ROOT}` | -- |
| AC-1 | Stop hook command uses absolute path anchored by environment variable | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:10` | Code review + regex test against frontmatter | -- |
| AC-2 | Stop hook executes successfully from any working directory | Runtime behavior when plugin is installed | Manual verification: invoke `/orchestrating-workflows` and confirm no "No such file or directory" error on stop | -- |
| AC-3 | Hook command uses a documented, supported environment variable | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:10` | Code review: confirm `${CLAUDE_PLUGIN_ROOT}` is used (documented in `plugins-reference.md` and `hooks.md`) | -- |

## Deliverable Verification

| Deliverable | Source | Expected Path | Status |
|-------------|--------|---------------|--------|
| Updated SKILL.md with corrected hook command path | BUG-004 fix | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | -- |
| New or updated test asserting `${CLAUDE_PLUGIN_ROOT}` in hook command | BUG-004 coverage gap | `scripts/__tests__/orchestrating-workflows.test.ts` | -- |

## Verification Checklist

- [ ] SKILL.md frontmatter `command` field no longer contains bare `scripts/stop-hook.sh` (RC-1)
- [ ] SKILL.md frontmatter `command` field is `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/stop-hook.sh` (RC-2, AC-1, AC-3)
- [ ] Existing stop hook behavior tests still pass (regression baseline)
- [ ] Existing `ai-skills-manager` validation still passes (regression baseline)
- [ ] New or updated test verifies `${CLAUDE_PLUGIN_ROOT}` is present in the hook command (AC-1, AC-3)
- [ ] No stop hook error ("No such file or directory") when skill runs as installed plugin (AC-2, manual)

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
