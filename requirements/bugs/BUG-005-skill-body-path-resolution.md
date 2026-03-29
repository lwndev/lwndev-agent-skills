# Bug: SKILL.md Body Paths Use Bare Relative References

## Bug ID

`BUG-005`

## GitHub Issue

[#105](https://github.com/lwndev/lwndev-marketplace/issues/105)

## Category

`logic-error`

## Severity

`high`

## Description

The `orchestrating-workflows` SKILL.md body references `scripts/workflow-state.sh` 29 times using bare relative paths. When the skill runs as an installed plugin, these paths resolve against the user's working directory instead of the skill directory, causing every workflow state command to fail with "No such file or directory."

## Steps to Reproduce

1. Install the `lwndev-sdlc` plugin
2. Invoke `/orchestrating-workflows` with any argument (e.g., a feature title)
3. The skill instructs the LLM to run `scripts/workflow-state.sh init {ID} feature`
4. The command fails because `scripts/workflow-state.sh` does not exist relative to the user's project directory

## Expected Behavior

All `scripts/workflow-state.sh` references in the SKILL.md body should use `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh`, which Claude Code substitutes with the absolute skill directory path before presenting the content to the LLM.

## Actual Behavior

Bare relative paths like `scripts/workflow-state.sh init {ID} feature` are used throughout the SKILL.md body. These resolve against the user's current working directory at runtime, causing "No such file or directory" errors for every workflow state operation (init, advance, pause, resume, fail, status, set-pr, phase-count, populate-phases).

## Root Cause(s)

1. All 29 occurrences of `scripts/workflow-state.sh` in `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (lines 104-359) use bare relative paths without the `${CLAUDE_SKILL_DIR}` prefix. Claude Code documentation states that `${CLAUDE_SKILL_DIR}` is the correct variable for referencing bundled scripts in SKILL.md body content, as it resolves to the directory containing the skill's `SKILL.md` file regardless of the user's working directory.

2. This is the same class of bug as BUG-004 (stop hook path resolution, issue #102), but affects the SKILL.md markdown body rather than the frontmatter hooks. BUG-004 was fixed using `${CLAUDE_PLUGIN_ROOT}` in frontmatter `command` fields; this bug requires `${CLAUDE_SKILL_DIR}` in the body content, which is the documented variable for SKILL.md body references per the Claude Code skills documentation.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`
- `scripts/__tests__/orchestrating-workflows.test.ts`

## Acceptance Criteria

- [x] All 29 occurrences of `scripts/workflow-state.sh` in the SKILL.md body are prefixed with `${CLAUDE_SKILL_DIR}/`, with no bare references remaining (RC-1)
- [x] The `${CLAUDE_SKILL_DIR}` variable is used (not `${CLAUDE_PLUGIN_ROOT}`) since these are body content references, not frontmatter hook commands (RC-2)
- [x] Workflow state commands execute successfully when the skill runs from any user working directory (RC-1, RC-2)
- [x] A test verifies that no bare `scripts/workflow-state.sh` references remain in the SKILL.md body (RC-1)

## Completion

**Status:** `In Progress`

**Completed:** 2026-03-29

**Pull Request:** [#106](https://github.com/lwndev/lwndev-marketplace/pull/106)

## Notes

- This is the same class of bug as #102 / BUG-004, which fixed the frontmatter stop hook path using `${CLAUDE_PLUGIN_ROOT}`. The body content uses a different variable (`${CLAUDE_SKILL_DIR}`) per Claude Code documentation.
- The frontmatter stop hook (line 10) was already fixed in PR #104 and uses `${CLAUDE_PLUGIN_ROOT}` — that path should not be changed.
- The fix is purely mechanical: prefix each of the 29 bare `scripts/workflow-state.sh` references with `${CLAUDE_SKILL_DIR}/`.
- Environment: Claude Code with `lwndev-sdlc` plugin v1.4.0, macOS/bash.
