# Chore: Apply Review Findings with Human Gate

## Chore ID

`CHORE-029`

## GitHub Issue

[#107](https://github.com/lwndev/lwndev-marketplace/issues/107)

## Category

`refactoring`

## Description

Update the `orchestrating-workflows` skill to parse findings returned by `reviewing-requirements` subagents and act on them: block progression on errors, surface warnings/info with a confirmation prompt, and optionally apply auto-fixable corrections before advancing to the next step. Currently the orchestrator ignores all findings and advances regardless of severity.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — add findings-handling instructions to the Forked Steps section for all `reviewing-requirements` invocations
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — add a `review-findings` pause reason for the gate to persist across sessions when unresolved errors block progression

## Acceptance Criteria

- [x] Orchestrator parses the error/warning/info findings summary returned by each `reviewing-requirements` subagent (feature steps 2, 6, 6+N+3; chore steps 2, 4, 7)
- [x] When errors are found, progression is blocked and findings are surfaced to the user
- [x] When only warnings/info are found, findings are presented to the user with a confirmation prompt before advancing
- [x] Auto-fixable corrections can be applied when the user opts in
- [x] After applying fixes, the review step is re-run to confirm resolution (max 1 re-run; if errors persist after re-run, surface remaining findings to user and pause for manual resolution)
- [x] User can choose to skip warnings and continue without applying fixes
- [x] Workflow state correctly tracks review-gate pauses and resumes

## Completion

**Status:** `In Progress`

**Completed:** 2026-03-29

**Pull Request:** [#109](https://github.com/lwndev/lwndev-marketplace/pull/109)

## Notes

### Approach: Orchestrator-driven loop

The orchestrator handles findings parsing, fix application, and re-verification in main context — subagents only perform the review itself. This aligns with the documented subagent chaining pattern and avoids limitations (subagents can't spawn subagents, each invocation is a fresh context).

**Flow for each `reviewing-requirements` fork step:**

1. Fork `reviewing-requirements` subagent as today
2. Parse the subagent's return text for the summary line: `Found **N errors**, **N warnings**, **N info**`
3. **Zero findings** (zero errors, zero warnings, zero info): Advance automatically
4. **Warnings/info only**: Surface findings to user with inline confirmation prompt ("N warnings found. Review and continue?"). If user confirms, advance. If user declines, pause with `review-findings` reason.
5. **Errors present**: Surface all findings to user. List auto-fixable items. Errors always block — ask user: apply fixes / pause for manual resolution.
6. If user opts to apply fixes: orchestrator applies corrections in main context (Edit tool), then spawns a **new** `reviewing-requirements` subagent fork to re-verify (max 1 re-run).
7. If re-run still finds errors: surface remaining findings and pause with `review-findings` reason. User fixes manually and re-invokes to resume.

### Other notes

- The `reviewing-requirements` skill already classifies findings by severity and identifies auto-fixable vs. manual-review items — the orchestrator parses this from the subagent's natural language return text
- The `review-findings` pause reason mirrors existing pause points (`plan-approval`, `pr-review`) for consistency
- Inline prompts handle warnings/info; full pauses (requiring re-invocation) handle unresolved errors
