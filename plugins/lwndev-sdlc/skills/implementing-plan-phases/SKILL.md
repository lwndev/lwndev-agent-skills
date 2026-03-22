---
name: implementing-plan-phases
description: Required workflow for implementing phases from plans in requirements/implementation/. Enforces status tracking (Pending → 🔄 In Progress → ✅ Complete), GitHub issue comments, branch naming (feat/{ID}-summary), and verification sequence. Use when the user says "run phase workflow", "execute phase workflow", "start phase N workflow", or asks to implement from an implementation plan document.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
---

# Implementing Plan Phases

Execute implementation plan phases with systematic tracking and verification.

## When to Use

- User says "run phase workflow", "execute phase workflow", or "start phase N workflow"
- User asks to implement from an implementation plan document
- References files in `requirements/implementation/`

## Quick Start

1. Locate implementation plan in `requirements/implementation/`
2. Identify target phase (user-specified or next pending)
3. Update plan status to "🔄 In Progress"
   ```markdown
   **Status:** 🔄 In Progress
   ```
4. Update GitHub issue with phase start:
   ```bash
   gh issue comment <ISSUE_NUM> --body "🔄 Starting Phase N: <Name>..."
   ```
5. Create feature branch (if not already exists): `feat/{Feature ID}-{2-3-word-summary}`
6. Load implementation steps into todos
7. Execute each step, **checking off each deliverable** in the implementation plan (`- [ ]` → `- [x]`) as it is completed
8. Verify deliverables (tests pass, build succeeds)
9. Commit and push changes to remote
10. Update plan status to "✅ Complete"
11. Update GitHub issue with completion comment:
    ```bash
    gh issue comment <ISSUE_NUM> --body "✅ Completed Phase N: <Name>..."
    ```
12. **After all phases complete:** Create pull request **(MUST include `Closes #N` if issue exists)**

## Workflow

Copy this checklist and track progress:

```
Phase Implementation:
- [ ] Locate implementation plan
- [ ] Identify target phase
- [ ] Update plan status to "🔄 In Progress"
- [ ] Post GitHub issue start comment
- [ ] Create/switch to feature branch
- [ ] Load steps into todos
- [ ] Execute implementation steps, checking off deliverables (- [ ] → - [x]) as completed
- [ ] Verify deliverables
- [ ] Commit and push changes to remote
- [ ] Update plan status to "✅ Complete"
- [ ] Post GitHub issue completion comment
- [ ] Create pull request after all phases complete (include "Closes #N" in body if issue exists)
```

**Important:** Including `Closes #N` in the PR body auto-closes the linked GitHub issue when merged. Without it, the issue must be closed manually.

See [step-details.md](references/step-details.md) for detailed guidance on each step.

## Phase Structure

Implementation plans follow this format:

```markdown
### Phase N: [Phase Name]
**Feature:** [FEAT-XXX](../features/...) | [#IssueNum](https://github.com/...)
**Status:** Pending | 🔄 In Progress | ✅ Complete

#### Rationale
Why this phase comes at this point in the sequence.

#### Implementation Steps
1. Specific action to take
2. Another specific action
3. Write tests for new functionality

#### Deliverables
- [ ] `path/to/file.ts` - Description
- [ ] `tests/path/to/file.test.ts` - Tests
```

The GitHub issue number `[#N]` is used for status updates.

## Branch Naming

Format: `feat/{Feature ID}-{2-3-word-summary}`

Examples:
- `feat/FEAT-001-scaffold-skill-command`
- `feat/FEAT-002-validate-skill-command`
- `feat/FEAT-007-chore-task-skill`

## Verification

Before marking a phase complete, verify:

- All deliverables created/modified
- Tests pass: `npm test`
- Build succeeds: `npm run build`
- Coverage meets threshold (if specified)
- Changes committed and pushed to remote
- Plan status updated with checkmarks
- GitHub issue updated
- After all phases: create PR per Step 12

## References

- **Complete workflow example**: [workflow-example.md](references/workflow-example.md) - Full Phase 2 implementation walkthrough
- **GitHub issue templates**: [github-templates.md](references/github-templates.md) - Comment templates for issue updates
- **Detailed step guidance**: [step-details.md](references/step-details.md) - In-depth explanation of each workflow step
- **PR template**: [assets/pr-template.md](assets/pr-template.md) - Pull request format for feature implementations
