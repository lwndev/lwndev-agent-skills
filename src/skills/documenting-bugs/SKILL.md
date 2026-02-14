---
name: documenting-bugs
description: Creates structured bug report documents for tracking defects and issues. Use when the user needs to document a bug, unexpected behavior, regression, UI/UX defect, performance issue, or security vulnerability with root cause analysis and traceable acceptance criteria.
---

# Documenting Bugs

Create structured bug report documents that capture defects with reproduction steps, severity classification, root cause analysis, and traceable acceptance criteria linking each fix back to its underlying cause.

## When to Use This Skill

- Documenting reported bugs or unexpected behavior
- Recording regressions in previously working functionality
- Tracking UI/UX defects or visual glitches
- Capturing performance issues or resource problems
- Documenting security vulnerabilities or auth bypasses
- Any defect that requires root cause analysis before fixing

## Quick Start

1. Check for existing bugs in `requirements/bugs/` to determine the next Bug ID
2. **Ask for GitHub issue URL** if not provided (optional but recommended for traceability)
3. Identify the bug category (see [references/categories.md](references/categories.md))
4. **Investigate the codebase** — read files, trace call paths, and identify root causes before finalizing the document
5. Create bug document using the template
6. Save to `requirements/bugs/BUG-XXX-description.md`

## File Location

All bug documents go in: `requirements/bugs/`

Naming format: `BUG-XXX-{2-4-word-description}.md`

Examples:
- `BUG-001-auth-token-expired.md`
- `BUG-002-broken-csv-export.md`
- `BUG-003-memory-leak-polling.md`

## Bug ID Assignment

To assign the next Bug ID:

1. Check existing files in `requirements/bugs/`
2. Find the highest `BUG-XXX` number
3. Increment by 1 for the new bug
4. If no bugs exist, start with `BUG-001`

## Template

See [assets/bug-document.md](assets/bug-document.md) for the full template.

### Structure Overview

```
# Bug: [Brief Title]
- Bug ID, GitHub Issue (optional), Category, Severity
- Description (1-2 sentences)
- Steps to Reproduce
- Expected Behavior
- Actual Behavior
- Root Cause(s) — numbered entries with file references
- Affected Files
- Acceptance Criteria — with (RC-N) traceability tags
- Completion (status, date, PR link)
- Notes (optional)
```

## Categories

Six bug categories with specific guidance:

| Category | Use For |
|----------|---------|
| `runtime-error` | Crashes, unhandled exceptions, fatal errors |
| `logic-error` | Incorrect behavior, wrong calculations, bad state |
| `ui-defect` | Visual glitches, layout issues, rendering problems |
| `performance` | Slowness, memory leaks, resource exhaustion |
| `security` | Vulnerabilities, auth bypasses, data exposure |
| `regression` | Previously working functionality that broke |

See [references/categories.md](references/categories.md) for detailed guidance on each category.

## Severity Levels

| Severity | Definition |
|----------|------------|
| `critical` | Application unusable, data loss, security breach |
| `high` | Major feature broken, no workaround |
| `medium` | Feature impaired, workaround exists |
| `low` | Minor issue, cosmetic, edge case |

## Verification Checklist

Before finalizing, verify:

- [ ] Bug ID is unique (not already used)
- [ ] Category matches the type of defect
- [ ] Severity accurately reflects the impact
- [ ] Steps to reproduce are clear and complete
- [ ] Root causes are investigated and documented with file references
- [ ] Every root cause has at least one corresponding acceptance criterion
- [ ] Every acceptance criterion references at least one root cause using `(RC-N)` tags
- [ ] Affected files list is complete
- [ ] GitHub issue is linked (if one exists)

## Relationship to Other Skills

| Task Type | Recommended Approach |
|-----------|---------------------|
| New feature with requirements | Use `documenting-features` skill |
| Chore/maintenance task | Use `documenting-chores` skill |
| Bug or defect report | Use this skill (`documenting-bugs`) |
| Quick fix (no tracking needed) | Direct implementation |

After documenting a bug, use the `executing-bug-fixes` skill to implement the fix with proper branch management and PR creation.
