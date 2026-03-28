# Chore: Update Workflow Chains

## Chore ID

`CHORE-026`

## GitHub Issue

[#67](https://github.com/lwndev/lwndev-marketplace/issues/67)

## Category

`documentation`

## Description

Update the "Relationship to Other Skills" sections in all affected skill SKILL.md files, the plugin README.md, and CLAUDE.md to reflect the expanded workflow chains that include reconciliation review steps (`reviewing-requirements` at multiple points), the `finalizing-workflow` terminal step, and the feature chain reorder (moving `documenting-qa` after `creating-implementation-plans`).

## Affected Files

- `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`
- `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md`
- `plugins/lwndev-sdlc/README.md`
- `CLAUDE.md`

## Acceptance Criteria

- [x] All 9 skill SKILL.md files have their "Relationship to Other Skills" sections updated to reflect the new workflow order
- [x] Feature chain reorder: `documenting-qa` appears after `creating-implementation-plans` in all documentation
- [x] Task tables include entries for the reconciliation review steps (test-plan reconciliation, code-review reconciliation)
- [x] Task tables include an entry for `finalizing-workflow` as the terminal step in each chain
- [x] Prose descriptions (e.g., "After documenting a feature, consider running...") are updated to mention the reconciliation steps and finalizing-workflow at the appropriate points
- [x] CLAUDE.md workflow chains are updated
- [x] Plugin README.md workflow chains are updated
- [x] Workflow descriptions clearly indicate that the reconciliation steps are optional but recommended
- [x] No functional changes to skill behavior — this is documentation only

## Completion

**Status:** `Completed`

**Completed:** 2026-03-28

**Pull Request:** [#85](https://github.com/lwndev/lwndev-marketplace/pull/85)

## Notes

- **Dependencies:** This chore depends on #64 (test-plan reconciliation), #66 (code-review reconciliation), and #70 (finalizing-workflow skill). All three are now closed and merged — no blockers remain.
- **Feature chain reorder rationale:** The `documenting-qa` skill already searches for and loads implementation plans as additional source documents. Moving QA after planning ensures the plan is always available, producing richer test plans that cover phase deliverables and technical decisions.
- **Chore/bug chains unchanged in QA ordering:** These chains have no planning step, so QA continues to follow directly after review. The inconsistency is justified.
- The three `reviewing-requirements` invocations correspond to: (1) standard review after requirements, (2) test-plan reconciliation after QA plan creation, (3) code-review reconciliation after PR review.
