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
argument-hint: "<plan-file> [phase-number]"
---

# Implementing Plan Phases

Execute implementation plan phases with systematic tracking and verification.

## When to Use

- User says "run phase workflow", "execute phase workflow", or "start phase N workflow"
- User asks to implement from an implementation plan document
- References files in `requirements/implementation/`

## Arguments

- **When argument is provided**: Parse the argument as `<plan-file> [phase-number]`. Match the first part against files in `requirements/implementation/` by ID prefix (e.g., `FEAT-001` matches `FEAT-001-podcast-cli-features.md`). If a phase number is provided (e.g., `FEAT-001 3`), target that specific phase. If the phase number exceeds the plan's phase count, display available phases and ask the user to choose. If no match is found for the plan file, inform the user and fall back to interactive selection.
- **When no argument is provided**: Scan `requirements/implementation/` for plan documents and prompt the user to select one. Then identify the next pending phase automatically.

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
9. **Always** commit and push changes to remote — do not ask the user for confirmation
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
- [ ] Always commit and push changes to remote (do not prompt — this is mandatory)
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
- Changes committed and pushed to remote (blocking — do not update plan status until push succeeds)
- Plan status updated with checkmarks
- GitHub issue updated
- After all phases: create PR per Step 12

## References

- **Complete workflow example**: [workflow-example.md](references/workflow-example.md) - Full Phase 2 implementation walkthrough
- **GitHub issue templates**: [github-templates.md](references/github-templates.md) - Comment templates for issue updates
- **Detailed step guidance**: [step-details.md](references/step-details.md) - In-depth explanation of each workflow step
- **PR template**: [assets/pr-template.md](assets/pr-template.md) - Pull request format for feature implementations
