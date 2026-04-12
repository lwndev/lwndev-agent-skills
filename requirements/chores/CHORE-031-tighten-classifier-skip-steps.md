# Chore: Tighten Bug Classifier and Skip Unnecessary Fork Steps

## Chore ID

`CHORE-031`

## GitHub Issue

[#138](https://github.com/lwndev/lwndev-marketplace/issues/138)

## Category

`refactoring`

## Description

Refactor `_classify_bug` in `workflow-state.sh` so that severity alone or RC count alone cannot promote a bug to `high` complexity (which forces Opus). Then make the orchestrator skip `reviewing-requirements` standard review (step 2) on `complexity == low` bug/chore chains and skip test-plan reconciliation (step 4) when the plan has no cross-reference mapping sections or `complexity == low`.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh`
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`

## Acceptance Criteria

- [x] `_classify_bug` no longer returns `high` from severity alone or RC count alone
- [x] A BUG-009-equivalent bug (documentation category, 1-line fix, severity=high) resolves to `sonnet`
- [x] Bug/chore chains with `complexity == low` skip `reviewing-requirements` step 2
- [x] Test-plan reconciliation fork is skipped when the plan has no cross-reference mapping sections or `complexity == low`
- [x] Feature-chain behavior is unchanged by all of the above

## Completion

**Status:** `In Progress`

**Completed:** 2026-04-12

**Pull Request:** TBD

## Notes

- This bundles T1, T2, and T6 from the parent issue #137. T2 and T6 are downstream consumers of T1's classifier output, so they should ship together as one testable unit.
- The `_classify_bug` change requires both severity >= medium AND (rc_count >= 4 OR category in {security, performance}) to return `high`. Raw severity alone tops out at `medium`. RC count alone maxes at `medium`.
- The step-skipping changes only affect bug and chore chains. Feature chains must remain untouched.
