---
name: executing-bug-fixes
description: Executes bug fix workflows from branch creation through pull request with root cause driven execution. Use when the user says "execute bug fix", "fix this bug", "run the bug fix workflow", or references bug documents in requirements/bugs/.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
argument-hint: <bug-id>
---

# Executing Bug Fixes

Execute bug fix workflows with root cause driven execution from branch creation through pull request.

## When to Use This Skill

- User says "execute bug fix", "fix this bug", or "run the bug fix workflow"
- User references a bug document in `requirements/bugs/`
- User wants to implement a documented bug fix
- Continuing bug fix work that was previously started

## Arguments

- **When argument is provided**: Match the argument against files in `requirements/bugs/` by ID prefix (e.g., `BUG-003` matches `BUG-003-login-timeout-error.md`). If no match is found, inform the user and fall back to interactive selection. If multiple matches are found, present the options and ask the user to choose.
- **When no argument is provided**: Scan `requirements/bugs/` for bug documents and prompt the user to select one if multiple exist.

## Quick Start

1. Locate bug document in `requirements/bugs/`
2. Extract Bug ID, severity, root cause(s), and review acceptance criteria
3. Redeclare root causes from the bug document into the workflow context
4. Create git branch: `fix/BUG-XXX-description`
5. Address each root cause systematically, implementing fixes and tracking with todos
6. **Check off each acceptance criterion** in the bug document (`- [ ]` → `- [x]`) as it is verified
7. Commit changes with `fix(category): description` messages
8. Verify reproduction steps no longer trigger the bug
9. Run tests/build verification
10. Create pull request **(MUST include `Closes #N` if issue exists)**
11. Update bug document completion section (status, date, PR link)

> **Note:** Issue tracking (start/completion comments) is handled by the orchestrator via `managing-work-items`. This skill focuses on root cause driven execution and verification.

## Workflow Checklist

Copy this checklist to track progress:

```
Bug Fix Execution:
- [ ] Locate bug document (get Bug ID)
- [ ] Extract severity, root causes, and acceptance criteria
- [ ] Redeclare root causes as trackable work items
- [ ] Create git branch: fix/BUG-XXX-description
- [ ] Address each root cause systematically (RC-1, RC-2, ...)
- [ ] Check off each acceptance criterion in bug document (- [ ] → - [x]) as verified
- [ ] Commit with fix(category): message format
- [ ] Verify reproduction steps no longer trigger the bug
- [ ] Run tests/build verification
- [ ] Create pull request (include "Closes #N" in body if issue exists)
- [ ] Update bug document (status → Completed, date, PR link)
```

**Important:** Including `Closes #N` in the PR body auto-closes the linked GitHub issue when merged. Without it, the issue must be closed manually.

See [references/workflow-details.md](references/workflow-details.md) for detailed guidance on each step.

## Root Cause Driven Execution

Bug fixes are organized around root causes identified in the bug document. This ensures systematic coverage and traceability.

### Workflow

1. **Redeclare root causes at start** — Load the root causes from the bug document into the todo list as trackable work items
2. **Address root causes systematically** — Work through each root cause in order, implementing the fix for that specific cause before moving to the next
3. **Verify per root cause** — After addressing each root cause, verify that the corresponding `(RC-N)` acceptance criteria pass
4. **Confirm full coverage** — Before creating the PR, confirm that every `RC-N` has been addressed and its acceptance criteria are met

### Discovering New Root Causes

If a new root cause is discovered during execution:

- Document it in the bug document as a new `RC-N` entry
- Add corresponding acceptance criteria with the `(RC-N)` tag
- Address it as part of the fix

## Branch Naming

Format: `fix/BUG-XXX-{2-4-word-description}`

- Uses Bug ID (not GitHub issue number) for consistent naming
- Description should be lowercase with hyphens
- Keep description brief but descriptive (2-4 words)

Examples:
- `fix/BUG-001-null-pointer-crash`
- `fix/BUG-002-incorrect-total-calc`
- `fix/BUG-003-missing-input-validation`

## Commit Message Format

Format: `fix(category): brief description`

| Category | Use When |
|----------|----------|
| `runtime-error` | Crashes, exceptions, unhandled errors |
| `logic-error` | Incorrect calculations, wrong conditions, flawed algorithms |
| `ui-defect` | Visual bugs, layout issues, rendering problems |
| `performance` | Slowness, memory leaks, resource exhaustion |
| `security` | Vulnerabilities, auth bypasses, data exposure |
| `regression` | Previously working functionality that broke |

Examples:
- `fix(runtime-error): handle null user in profile lookup`
- `fix(logic-error): correct discount calculation for bulk orders`
- `fix(ui-defect): fix modal overlay z-index stacking`

## Verification Checklist

Before creating the PR, verify:

- [ ] All root causes from bug document are addressed
- [ ] Each `(RC-N)` tagged acceptance criterion is met
- [ ] Reproduction steps no longer trigger the bug
- [ ] Tests pass (if applicable)
- [ ] Build succeeds
- [ ] Changes match the scope defined in bug document
- [ ] No unintended side effects or regressions

## References

- **Detailed workflow guidance**: [workflow-details.md](references/workflow-details.md) - Step-by-step instructions for each phase
- **PR template**: [assets/pr-template.md](assets/pr-template.md) - Pull request format for bug fixes

## Relationship to Other Skills

| Task Type | Recommended Approach |
|-----------|---------------------|
| Bug already documented | Use this skill (`executing-bug-fixes`) |
| Bug needs documentation first | Use `documenting-bugs`, then this skill |
| Chore or maintenance task | Use `documenting-chores` -> `executing-chores` |
| New feature with requirements | Use `documenting-features` -> `creating-implementation-plans` -> `implementing-plan-phases` |
| Quick fix (no tracking needed) | Direct implementation |

After executing a bug fix, consider running `/reviewing-requirements` for code-review reconciliation after PR review (optional but recommended), then `/executing-qa` to verify the implementation against the test plan, and `/finalizing-workflow` to merge.
