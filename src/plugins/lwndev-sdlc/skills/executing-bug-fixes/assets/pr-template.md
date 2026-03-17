# Pull Request Template for Bug Fixes

Copy and customize this template when creating a bug fix PR.

---

## Template

```markdown
## Bug
[BUG-XXX](requirements/bugs/BUG-XXX-description.md)

## Summary
[Brief description of what this fix addresses - 1-2 sentences]

## Root Cause(s)
From the bug document:
1. **RC-1:** [Root cause 1 description]
2. **RC-2:** [Root cause 2 description]

## How Each Root Cause Was Addressed

| RC | Fix Applied | Files Changed |
|----|-------------|---------------|
| RC-1 | [What was done to fix RC-1] | `path/to/file1.ts` |
| RC-2 | [What was done to fix RC-2] | `path/to/file2.ts`, `path/to/file3.ts` |

## Changes
- [Change 1]
- [Change 2]
- [Change 3]

## Testing
- [ ] RC-1 acceptance criteria verified
- [ ] RC-2 acceptance criteria verified
- [ ] Reproduction steps no longer trigger the bug
- [ ] Tests pass
- [ ] Build succeeds
- [ ] No regressions

## Related
- Closes #N <!-- REQUIRED if bug document has a GitHub Issue link - enables auto-close on merge -->

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

**Important:** If the bug document links to a GitHub issue, you MUST include `Closes #N` in the Related section. This auto-closes the issue when the PR is merged. Without it, the issue must be closed manually.

---

## Filled Example

```markdown
## Bug
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
| RC-1 | Applied tax rate to subtotal before calculating discount | `src/services/order-calculator.ts` |
| RC-2 | Used `Math.round()` with 2-decimal precision for discount amounts | `src/services/order-calculator.ts`, `src/utils/currency.ts` |

## Changes
- Applied tax calculation before discount in `calculateOrderTotal()`
- Added `roundCurrency()` utility for consistent 2-decimal rounding
- Updated discount logic to use `roundCurrency()` for all percentage calculations
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
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

---

## Usage with gh CLI

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

---

## Section Guidelines

### Bug Link
- Always link to the bug document
- Use relative path from repository root
- Use Bug ID (e.g., `BUG-001`) not the GitHub issue number

### Summary
- Keep to 1-2 sentences
- Focus on what was fixed and why
- Reference the root causes briefly

### Root Cause(s)
- Copy the numbered root causes directly from the bug document
- Use the exact `RC-N` numbering from the bug document
- Keep descriptions concise but clear

### How Each Root Cause Was Addressed
- One row per root cause
- **RC** column: `RC-1`, `RC-2`, etc.
- **Fix Applied** column: Brief description of the specific fix for that root cause
- **Files Changed** column: List the files modified to address that root cause
- This table provides traceability from root cause to fix

### Changes
- List concrete changes made
- Group related changes
- Use consistent formatting (bullets)
- Include context when helpful ("Added `roundCurrency()` utility for consistent 2-decimal rounding")

### Testing
- Include per-root-cause verification items (one per `RC-N`)
- Include reproduction verification ("Reproduction steps no longer trigger the bug")
- Include standard checks: tests pass, build succeeds, no regressions
- Check off items that pass
- Add custom checks if the fix requires specific verification

### Related
- **Use `Closes #N` to auto-close linked issue on merge** — REQUIRED if bug document has a GitHub Issue link
- Use "Refs #N" to link without closing
- List any other related PRs or issues
