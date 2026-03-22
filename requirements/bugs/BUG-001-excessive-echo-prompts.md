# Bug: Excessive Echo Permission Prompts in documenting-qa

## Bug ID

`BUG-001`

## GitHub Issue

[#34](https://github.com/lwndev/lwndev-marketplace/issues/34)

## Category

`logic-error`

## Severity

`medium`

## Description

When running `documenting-qa`, the model repeatedly asks for permission to execute `echo` commands via Bash. This degrades the user experience by requiring multiple manual approvals for unnecessary operations during skill execution.

## Steps to Reproduce

1. Run the `documenting-qa` skill with a valid requirement ID (e.g., `FEAT-004`)
2. Observe the model's behavior as it builds the test plan and delegates to the `qa-verifier` subagent
3. Note repeated permission prompts for `echo` Bash commands throughout execution

## Expected Behavior

The skill should execute without prompting for `echo` permissions. Output formatting should use direct text output rather than Bash echo commands. The `qa-verifier` subagent should only use Bash for running `npm test`, not for formatting or printing.

## Actual Behavior

The model repeatedly prompts the user for permission to run `echo` commands via Bash during skill execution, requiring multiple manual approvals that interrupt the workflow.

## Root Cause(s)

1. The `documenting-qa` SKILL.md (`plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`) does not include `Bash` in its `allowed-tools`, but the skill instructions contain no explicit guidance telling the model to avoid using Bash for output formatting. Without this guidance, the model may still attempt `echo` commands for status updates or formatted output, triggering permission prompts.

2. The `qa-verifier` agent (`plugins/lwndev-sdlc/agents/qa-verifier.md`) includes `Bash` in its tools list to support running `npm test`, but the agent prompt has no restriction discouraging use of `echo` or other unnecessary Bash commands for output formatting. The model defaults to using `echo` via Bash for printing section headers, status messages, or formatted results during verification steps.

## Affected Files

- `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`
- `plugins/lwndev-sdlc/agents/qa-verifier.md`

## Acceptance Criteria

- [ ] The `documenting-qa` SKILL.md includes guidance instructing the model to use direct text output instead of Bash/echo for all formatting and status messages (RC-1)
- [ ] The `qa-verifier` agent prompt restricts Bash usage to only running test commands (e.g., `npm test`), explicitly discouraging use of `echo` or other Bash commands for output formatting (RC-2)
- [ ] Running `documenting-qa` with a valid requirement ID completes without triggering any `echo` permission prompts (RC-1, RC-2)

## Completion

**Status:** `Pending`

**Completed:** YYYY-MM-DD

**Pull Request:** [#N](https://github.com/lwndev/lwndev-marketplace/pull/N)

## Notes

- Split from issue #32
- Original feature: FEAT-004 / #23
- The workaround is to manually approve each `echo` permission prompt as it appears
