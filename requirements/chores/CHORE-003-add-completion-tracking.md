# Chore: Add Completion Tracking to Chores

## Chore ID

`CHORE-003`

## Category

`documentation`

## Description

Add a Completion section to the chore document template and update related skill workflows to track chore completion status, date, and PR link. This provides traceability and makes it easy to see which chores are done vs pending.

## Affected Files

- `src/skills/documenting-chores/assets/chore-document.md`
- `src/skills/documenting-chores/SKILL.md`
- `src/skills/executing-chores/SKILL.md`

## Acceptance Criteria

- [ ] Chore template has Completion section after Acceptance Criteria and before Notes
- [ ] Completion section includes Status field (`Pending` | `In Progress` | `Completed`)
- [ ] Completion section includes Completed date field
- [ ] Completion section includes Pull Request link field
- [ ] documenting-chores SKILL.md Structure Overview reflects new section
- [ ] executing-chores SKILL.md includes step to update chore document with completion details
- [ ] executing-chores Workflow Checklist includes updating chore document status

## Notes

- Mirrors the status tracking pattern used in `implementing-plan-phases` for plan documents
- The Completion section fields should be placeholder/empty when first created, then populated during execution
