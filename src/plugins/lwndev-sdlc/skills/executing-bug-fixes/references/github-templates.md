# GitHub Templates

Templates for GitHub interactions during bug fix execution.

## Table of Contents

- [Issue Comments](#issue-comments)
- [Commit Messages](#commit-messages)
- [Pull Request](#pull-request)
- [Creating New Issues](#creating-new-issues)

---

## Issue Comments

### Starting Work Comment

Post when beginning work on a bug fix:

```bash
gh issue comment <ISSUE_NUM> --body "🔄 **Starting work on BUG-XXX**

**Bug Document:** [BUG-XXX](../requirements/bugs/BUG-XXX-description.md)

**Severity:** [Critical|High|Medium|Low]

**Root Causes to Address:**
1. RC-1: [Root cause 1 description]
2. RC-2: [Root cause 2 description]

**Acceptance Criteria:**
- [ ] Criterion 1 (RC-1)
- [ ] Criterion 2 (RC-1)
- [ ] Criterion 3 (RC-2)

**Branch:** \`fix/BUG-XXX-description\`

**Status:** 🔄 In Progress"
```

**Example:**

```bash
gh issue comment 42 --body "🔄 **Starting work on BUG-001**

**Bug Document:** [BUG-001](../requirements/bugs/BUG-001-order-total-calculation-error.md)

**Severity:** High

**Root Causes to Address:**
1. RC-1: Tax rate not applied to subtotal before discount calculation
2. RC-2: Floating-point rounding error in percentage discount logic

**Acceptance Criteria:**
- [ ] Tax applied before discount in calculateOrderTotal() (RC-1)
- [ ] Order totals match expected values in test cases (RC-1)
- [ ] All currency amounts rounded to 2 decimal places (RC-2)
- [ ] Discount calculations use consistent rounding (RC-2)

**Branch:** \`fix/BUG-001-order-total-calc\`

**Status:** 🔄 In Progress"
```

### Work Complete Comment

Post when bug fix work is complete and PR is created:

```bash
gh issue comment <ISSUE_NUM> --body "✅ **Completed BUG-XXX**

**Pull Request:** #<PR_NUM>

**Root Cause Resolution:**
- ✅ RC-1: [Root cause 1] — Fixed
- ✅ RC-2: [Root cause 2] — Fixed

**Verification:**
- ✅ All root causes addressed
- ✅ Reproduction steps verified — bug no longer occurs
- ✅ Tests passing
- ✅ Build successful

**Status:** ✅ Complete - Ready for review"
```

**Example:**

```bash
gh issue comment 42 --body "✅ **Completed BUG-001**

**Pull Request:** #58

**Root Cause Resolution:**
- ✅ RC-1: Tax rate not applied before discount — Applied tax to subtotal before discount calculation
- ✅ RC-2: Floating-point rounding error — Added roundCurrency() utility for consistent 2-decimal rounding

**Verification:**
- ✅ All root causes addressed
- ✅ Reproduction steps verified — order totals now calculate correctly
- ✅ Tests passing
- ✅ Build successful

**Status:** ✅ Complete - Ready for review"
```

---

## Commit Messages

### Format

```
fix(category): brief description

Optional longer description explaining the change.

Refs: BUG-XXX
```

### Categories

| Category | When to Use |
|----------|-------------|
| `runtime-error` | Crashes, exceptions, unhandled errors |
| `logic-error` | Incorrect calculations, wrong conditions, flawed algorithms |
| `ui-defect` | Visual bugs, layout issues, rendering problems |
| `performance` | Slowness, memory leaks, resource exhaustion |
| `security` | Vulnerabilities, auth bypasses, data exposure |
| `regression` | Previously working functionality that broke |

### Examples

**Single-line (most bug fixes):**

```
fix(runtime-error): handle null user in profile lookup
```

```
fix(logic-error): correct discount calculation for bulk orders
```

```
fix(ui-defect): fix modal overlay z-index stacking
```

**Multi-line (when context helps):**

```
fix(logic-error): correct order total calculation

Root causes addressed:
- RC-1: Applied tax rate before discount calculation
- RC-2: Added consistent currency rounding

Refs: BUG-001
```

```
fix(security): sanitize user input in search endpoint

Prevents XSS via unescaped search query parameter.
Added input sanitization and output encoding.

Refs: BUG-015
```

---

## Pull Request

### PR Title Format

```
fix(category): brief description
```

**Examples:**
- `fix(runtime-error): handle null user in profile lookup`
- `fix(logic-error): correct order total calculation`
- `fix(ui-defect): fix modal overlay z-index stacking`

### PR Body Template

Use with `gh pr create`:

```bash
gh pr create --title "fix(category): description" --body "## Bug
[BUG-XXX](requirements/bugs/BUG-XXX-description.md)

## Summary
Brief description of what this fix addresses.

## Root Cause(s)
From the bug document:
1. **RC-1:** [Root cause 1 description]
2. **RC-2:** [Root cause 2 description]

## How Each Root Cause Was Addressed

| RC | Fix Applied | Files Changed |
|----|-------------|---------------|
| RC-1 | [What was done to fix RC-1] | \`path/to/file1.ts\` |
| RC-2 | [What was done to fix RC-2] | \`path/to/file2.ts\` |

## Changes
- Change 1
- Change 2
- Change 3

## Testing
- [ ] RC-1 acceptance criteria verified
- [ ] RC-2 acceptance criteria verified
- [ ] Reproduction steps no longer trigger the bug
- [ ] Tests pass
- [ ] Build succeeds
- [ ] No regressions

## Related
- Closes #N <!-- REQUIRED if bug document has a GitHub Issue link -->

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

**Important:** If the bug document links to a GitHub issue, you MUST include `Closes #N` in the Related section. This auto-closes the issue when the PR is merged.

**Example:**

```bash
gh pr create --title "fix(logic-error): correct order total calculation" --body "## Bug
[BUG-001](requirements/bugs/BUG-001-order-total-calculation-error.md)

## Summary
Fixes incorrect order total calculation caused by a missing tax application and a rounding error in the discount logic.

## Root Cause(s)
From the bug document:
1. **RC-1:** Tax rate not applied to subtotal before discount calculation
2. **RC-2:** Floating-point rounding error in percentage discount logic

## How Each Root Cause Was Addressed

| RC | Fix Applied | Files Changed |
|----|-------------|---------------|
| RC-1 | Applied tax rate to subtotal before calculating discount | \`src/services/order-calculator.ts\` |
| RC-2 | Used \`Math.round()\` with 2-decimal precision for discount amounts | \`src/services/order-calculator.ts\`, \`src/utils/currency.ts\` |

## Changes
- Applied tax calculation before discount in \`calculateOrderTotal()\`
- Added \`roundCurrency()\` utility for consistent 2-decimal rounding
- Updated discount logic to use \`roundCurrency()\` for all percentage calculations
- Added unit tests covering tax-before-discount and rounding edge cases

## Testing
- [x] RC-1 acceptance criteria verified — tax applied before discount
- [x] RC-2 acceptance criteria verified — totals rounded to 2 decimal places
- [x] Reproduction steps no longer trigger the bug
- [x] Tests pass
- [x] Build succeeds
- [x] No regressions

## Related
- Closes #42

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

See [assets/pr-template.md](../assets/pr-template.md) for the copyable template.

---

## Creating New Issues

### When to Create an Issue

Create a GitHub issue for a bug when:
- The bug needs tracking before a fix is ready
- A new root cause is discovered that warrants separate work
- A partial fix needs follow-up work tracked
- Multiple people might need to collaborate on the fix

### Issue Creation Template

```bash
gh issue create --title "bug: brief description" --body "## Summary
Brief description of the bug behavior.

## Severity
[Critical|High|Medium|Low]

## Reproduction Steps
1. Step 1
2. Step 2
3. Step 3

## Expected Behavior
What should happen.

## Actual Behavior
What actually happens.

## Root Causes (if known)
1. RC-1: [Description]

## Notes
Any relevant context or constraints.

## Related
- Related issues or PRs (if any)"
```

**Example:**

```bash
gh issue create --title "bug: order total incorrect with percentage discounts" --body "## Summary
Order totals are calculated incorrectly when percentage discounts are applied, resulting in overcharges.

## Severity
High

## Reproduction Steps
1. Add items totaling \$100.00 to cart
2. Apply 15% discount code
3. Observe order total shows \$85.01 instead of \$85.00

## Expected Behavior
Order total should be \$85.00 after 15% discount.

## Actual Behavior
Order total shows \$85.01 due to floating-point rounding error.

## Root Causes (if known)
1. RC-1: Tax applied after discount instead of before
2. RC-2: No rounding applied to intermediate calculations

## Notes
Affects all orders with percentage-based discounts. Fixed-amount discounts work correctly.

## Related
- Customer report #1234"
```

### Labeling Issues

If your repository uses labels:

```bash
gh issue create --title "..." --body "..." --label "bug" --label "high-priority"
```

Common bug labels:
- `bug`
- `critical`
- `high-priority`
- `regression`
- `security`
