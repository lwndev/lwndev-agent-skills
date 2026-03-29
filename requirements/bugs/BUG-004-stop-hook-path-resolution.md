# Bug: Stop Hook Path Resolves Relative to Working Directory

## Bug ID

`BUG-004`

## GitHub Issue

[#102](https://github.com/lwndev/lwndev-marketplace/issues/102)

## Category

`logic-error`

## Severity

`medium`

## Description

The `orchestrating-workflows` skill's Stop hook command `scripts/stop-hook.sh` resolves relative to the user's working directory instead of the skill directory, causing the hook to fail with "No such file or directory" every time the skill stops.

## Steps to Reproduce

1. Install the `lwndev-sdlc` plugin
2. Invoke `/orchestrating-workflows` with any argument
3. Allow the skill to stop naturally or press Ctrl+C
4. Observe the stop hook error: `Stop hook error: Failed with non-blocking status code: /bin/sh: scripts/stop-hook.sh: No such file or directory`

## Expected Behavior

The stop hook at `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/stop-hook.sh` should execute successfully, checking workflow state and blocking or allowing stop as appropriate.

## Actual Behavior

The hook command `scripts/stop-hook.sh` resolves relative to the current working directory (the user's project). Since `scripts/stop-hook.sh` doesn't exist at the project root, the hook fails with "No such file or directory." The error is non-blocking, so the skill still stops, but the stop-protection logic never runs.

## Root Cause(s)

1. The SKILL.md frontmatter in `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:10` declares the hook command as a bare relative path (`scripts/stop-hook.sh`). Claude Code resolves hook commands relative to the current working directory, not the skill's own directory, so the path only works if the user happens to be in the skill directory itself (which never happens in practice).

2. No environment variable is used to anchor the path. Claude Code exposes `${CLAUDE_PLUGIN_ROOT}` for hook commands (documented in hooks reference and plugins reference), and string substitution is applied to frontmatter `command` fields before execution. The fix should use `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/stop-hook.sh` to construct the correct absolute path.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`
- `scripts/__tests__/orchestrating-workflows.test.ts`

## Acceptance Criteria

- [x] The Stop hook command in SKILL.md frontmatter uses an absolute path anchored by an environment variable (`${CLAUDE_PLUGIN_ROOT}` or `${CLAUDE_SKILL_DIR}`) instead of a bare relative path (RC-1, RC-2)
- [ ] The stop hook executes successfully when the skill is invoked from any working directory (RC-1)
- [x] The hook command uses a documented, supported environment variable for path resolution (RC-2)

## Completion

**Status:** `In Progress`

**Completed:** TBD

**Pull Request:** [#104](https://github.com/lwndev/lwndev-marketplace/pull/104)

## Notes

- The bug was observed while testing the `orchestrating-workflows` skill in the `lwndev-marketplace` repo after copying it to the project's `.claude/skills/` directory via the `test-skill` script. The agent may have been resolving the hook against the source `plugins/` path rather than the project scope. However, the fix targets the plugin distribution path only — the skill is not intended to run as a project skill.
- The `orchestrating-workflows` skill is the only skill in the plugin that uses a `type: command` hook; all other skills with Stop hooks use `type: prompt` (LLM evaluation), which avoids this path resolution issue.
- Inside `stop-hook.sh` itself, the script already uses `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` to resolve sibling scripts correctly — the problem is purely that the shell never reaches the script.
- Claude Code documentation confirms `${CLAUDE_PLUGIN_ROOT}` undergoes string substitution in frontmatter `command` fields (see `plugins-reference.md` and the changelog fix for `allowed-tools` frontmatter substitution).
- Environment: Claude Code with `lwndev-sdlc` plugin v1.4.0, macOS/bash.
