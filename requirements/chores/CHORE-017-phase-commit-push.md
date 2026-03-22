# Chore: Add Phase Commit and Push

## Chore ID

`CHORE-017`

## GitHub Issue

[#41](https://github.com/lwndev/lwndev-marketplace/issues/41)

## Category

`refactoring`

## Description

Enhance the `implementing-plan-phases` skill to commit and push changes to the remote after each phase is completed. Currently the workflow does not persist changes between phases, risking overwrites in subsequent phases and making it difficult to identify the source and timing of problems.

## Affected Files

- `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/workflow-example.md`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/github-templates.md`

## Acceptance Criteria

- [ ] SKILL.md workflow checklist includes a commit-and-push step after verification and before marking phase complete
- [ ] step-details.md contains a new step with commit message format and push instructions
- [ ] workflow-example.md reflects the commit-and-push step in its walkthrough
- [ ] Commit message format includes phase number and name for traceability (e.g., `feat(FEAT-XXX): complete phase N - <phase name>`)
- [ ] Push uses `-u` flag to set upstream tracking on the feature branch
- [ ] Step ordering ensures commit/push occurs after verification passes but before the plan status is updated to complete
- [ ] All step number references are renumbered consistently across all affected files (current Steps 9-10 become Steps 10-11)
- [ ] New step includes guidance on staging changed files before committing
- [ ] Phase completion comment template in github-templates.md references the commit SHA for traceability
- [ ] Step 9 includes error recovery guidance for push failures (network issues, authentication, rejected pushes)

## Completion

**Status:** `Completed`

**Completed:** 2026-03-22

**Pull Request:** [#57](https://github.com/lwndev/lwndev-marketplace/pull/57)

## Notes

- The commit-and-push step should slot in between the current Step 8 (Verify Deliverables) and Step 9 (Update Plan Status), becoming a new Step 9 and shifting subsequent steps
- This ensures only verified work gets committed and that the git history provides a clear per-phase audit trail
- The push ensures remote backup and visibility for collaborators between phases
