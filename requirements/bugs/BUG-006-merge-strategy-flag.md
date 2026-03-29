# Bug: Missing Merge Strategy Flag

## Bug ID

`BUG-006`

## GitHub Issue

[#101](https://github.com/lwndev/lwndev-marketplace/issues/101)

## Category

`logic-error`

## Severity

`medium`

## Description

The `finalizing-workflow` skill instructs the agent to run `gh pr merge --delete-branch` without a merge strategy flag. When `gh` runs non-interactively (as it does inside Claude Code), it requires an explicit `--merge`, `--rebase`, or `--squash` flag and fails with: `--merge, --rebase, or --squash required when not running interactively`.

## Steps to Reproduce

1. Complete a workflow through the QA step so a PR is ready to merge
2. Run `/finalizing-workflow` to merge the PR
3. The skill executes `gh pr merge --delete-branch` without a merge strategy flag
4. The merge command fails with the error: `--merge, --rebase, or --squash required when not running interactively`

## Expected Behavior

The merge command should succeed on the first attempt by including an explicit merge strategy flag (e.g., `--merge`).

## Actual Behavior

The merge command fails because `gh` requires `--merge`, `--rebase`, or `--squash` when running non-interactively. The agent must retry with a strategy flag manually added.

## Root Cause(s)

1. The merge command in `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md:67` is `gh pr merge --delete-branch` without a merge strategy flag. The `gh` CLI requires one of `--merge`, `--rebase`, or `--squash` when running non-interactively.
2. The instruction on `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md:70` explicitly says "Use the repository's default merge strategy (no `--merge`, `--squash`, or `--rebase` flag)", reinforcing the incorrect behavior by telling the agent not to add the required flag.

## Affected Files

- `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md`

## Acceptance Criteria

- [x] The merge command in SKILL.md includes an explicit `--merge` flag alongside `--delete-branch` (RC-1)
- [x] The instructional text no longer tells the agent to omit the merge strategy flag (RC-2)
- [x] The merge command succeeds on first attempt when executed non-interactively by Claude Code (RC-1, RC-2)

## Completion

**Status:** `In Progress`

**Completed:** 2026-03-29

**Pull Request:** [#108](https://github.com/lwndev/lwndev-marketplace/pull/108)

## Notes

- This was encountered during CHORE-028 execution (PR #100)
- Using `--merge` preserves full commit history, which is the most common default for non-squash repos
- The `gh` CLI only auto-detects merge strategy in interactive (TTY) mode; Claude Code always runs non-interactively
