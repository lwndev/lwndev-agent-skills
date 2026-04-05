# GitHub Templates

Consolidated templates for all GitHub issue interactions. This file is the single source of truth for issue comment templates, commit message formats, PR body templates, and issue creation templates used across all workflow types (features, chores, bug fixes).

## Table of Contents

- [Issue Comment Templates](#issue-comment-templates)
  - [phase-start](#phase-start)
  - [phase-completion](#phase-completion)
  - [work-start](#work-start)
  - [work-complete](#work-complete)
  - [bug-start](#bug-start)
  - [bug-complete](#bug-complete)
- [Closing Issue (Final Phase)](#closing-issue-final-phase)
- [Commit Messages](#commit-messages)
  - [Feature Commits](#feature-commits)
  - [Chore Commits](#chore-commits)
  - [Bug Fix Commits](#bug-fix-commits)
- [Pull Request Templates](#pull-request-templates)
  - [Feature PR](#feature-pr)
  - [Chore PR](#chore-pr)
  - [Bug Fix PR](#bug-fix-pr)
- [Creating New Issues](#creating-new-issues)
  - [Chore Issue](#chore-issue)
  - [Bug Issue](#bug-issue)

---

## Issue Comment Templates

These templates correspond to the `--type` argument values in the `managing-work-items comment` invocation.

### phase-start

Post when beginning a new implementation phase (used by `implementing-plan-phases`):

```bash
gh issue comment <ISSUE_NUM> --body "🔄 Starting Phase <N>: <Phase Name>

**Work Item:** FEAT-XXX

**Implementation Steps:**
1. <Step 1>
2. <Step 2>
...

**Expected Deliverables:**
- <Deliverable 1>
- <Deliverable 2>
...

**Status:** 🔄 In Progress"
```

**Example:**

```bash
gh issue comment 2 --body "🔄 Starting Phase 2: Validation Engine

**Work Item:** FEAT-002

**Implementation Steps:**
1. Create file-exists validator
2. Create required-fields validator
3. Create validation orchestrator
4. Write file-exists tests
5. Write required-fields tests
6. Write orchestrator tests

**Expected Deliverables:**
- src/validators/file-exists.ts
- src/validators/required-fields.ts
- src/generators/validate.ts
- tests/unit/validators/file-exists.test.ts
- tests/unit/validators/required-fields.test.ts
- tests/unit/generators/validate.test.ts

**Status:** 🔄 In Progress"
```

### phase-completion

Post when an implementation phase is complete (used by `implementing-plan-phases`):

```bash
gh issue comment <ISSUE_NUM> --body "✅ Completed Phase <N>: <Phase Name>

**Work Item:** FEAT-XXX

**Deliverables Verified:**
- [x] <Deliverable 1>
- [x] <Deliverable 2>
...

**Verification:**
- ✅ Tests passing
- ✅ Build successful
- ✅ Coverage: <X>%

**Commit:** \`<short SHA>\` — \`feat(FEAT-XXX): complete phase N - <phase name>\`

**Status:** ✅ Complete"
```

**Example:**

```bash
gh issue comment 2 --body "✅ Completed Phase 2: Validation Engine

**Work Item:** FEAT-002

**Deliverables Verified:**
- [x] src/validators/file-exists.ts - File/directory existence validation
- [x] src/validators/required-fields.ts - Required fields validation
- [x] src/generators/validate.ts - Validation orchestration
- [x] tests/unit/validators/file-exists.test.ts - File existence tests
- [x] tests/unit/validators/required-fields.test.ts - Required fields tests
- [x] tests/unit/generators/validate.test.ts - Orchestrator tests

**Verification:**
- ✅ Tests passing
- ✅ Build successful
- ✅ Coverage: 85%

**Commit:** \`a1b2c3d\` — \`feat(FEAT-002): complete phase 2 - validation engine\`

**Status:** ✅ Complete"
```

### work-start

Post when beginning work on a chore (used by `executing-chores`):

```bash
gh issue comment <ISSUE_NUM> --body "🔄 **Starting work on CHORE-XXX**

**Chore Document:** [CHORE-XXX](../requirements/chores/CHORE-XXX-description.md)

**Acceptance Criteria:**
- [ ] Criterion 1
- [ ] Criterion 2

**Branch:** \`chore/CHORE-XXX-description\`

**Status:** 🔄 In Progress"
```

**Example:**

```bash
gh issue comment 15 --body "🔄 **Starting work on CHORE-003**

**Chore Document:** [CHORE-003](../requirements/chores/CHORE-003-cleanup-unused-imports.md)

**Acceptance Criteria:**
- [ ] Remove unused imports from src/
- [ ] Run linter to verify no import errors
- [ ] Build passes

**Branch:** \`chore/CHORE-003-cleanup-unused-imports\`

**Status:** 🔄 In Progress"
```

### work-complete

Post when chore work is complete and PR is created (used by `executing-chores`):

```bash
gh issue comment <ISSUE_NUM> --body "✅ **Completed CHORE-XXX**

**Pull Request:** #<PR_NUM>

**Acceptance Criteria Verified:**
- [x] Criterion 1
- [x] Criterion 2

**Verification:**
- ✅ Tests passing
- ✅ Build successful

**Status:** ✅ Complete - Ready for review"
```

**Example:**

```bash
gh issue comment 15 --body "✅ **Completed CHORE-003**

**Pull Request:** #42

**Acceptance Criteria Verified:**
- [x] Remove unused imports from src/
- [x] Run linter to verify no import errors
- [x] Build passes

**Verification:**
- ✅ Tests passing
- ✅ Build successful

**Status:** ✅ Complete - Ready for review"
```

### bug-start

Post when beginning work on a bug fix (used by `executing-bug-fixes`):

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

### bug-complete

Post when bug fix work is complete and PR is created (used by `executing-bug-fixes`):

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

## Closing Issue (Final Phase)

When all implementation phases are complete, close the issue:

```bash
gh issue close <ISSUE_NUM> --comment "✅ All phases complete

**Feature Summary:**
- Phase 1: <Name> ✅
- Phase 2: <Name> ✅
- Phase 3: <Name> ✅
...

All deliverables implemented, tested, and verified.

Implementation complete."
```

**Example:**

```bash
gh issue close 2 --comment "✅ All phases complete

**Feature Summary:**
- Phase 1: YAML Parsing Infrastructure ✅
- Phase 2: Validation Engine ✅
- Phase 3: Enhanced Validation Rules ✅
- Phase 4: Command Integration & Output ✅

All deliverables implemented, tested, and verified.

FEAT-002 validate command implementation complete."
```

---

## Commit Messages

### Feature Commits

```
feat(FEAT-XXX): complete phase N - <phase name>

Optional longer description explaining the change.

Refs: FEAT-XXX
```

### Chore Commits

**Format:**

```
chore(category): brief description

Optional longer description explaining the change.

Refs: CHORE-XXX
```

**Categories:**

| Category | When to Use |
|----------|-------------|
| `dependencies` | Package updates, version bumps, security patches |
| `documentation` | README updates, comment fixes, doc corrections |
| `refactoring` | Code cleanup, restructuring without behavior changes |
| `configuration` | Config file updates, tooling changes, CI/CD |
| `cleanup` | Removing dead code, unused files, deprecated features |

**Examples:**

```
chore(dependencies): update typescript to 5.5.4
```

```
chore(documentation): fix typos in contributing guide
```

```
chore(cleanup): remove deprecated API endpoints
```

```
chore(dependencies): update react to v19

Breaking changes addressed:
- Updated createRoot usage
- Migrated from ReactDOM.render

Refs: CHORE-005
```

```
chore(refactoring): extract validation logic to utils

Consolidates duplicate validation code from:
- src/commands/scaffold.ts
- src/commands/validate.ts

No behavior changes.

Refs: CHORE-007
```

### Bug Fix Commits

**Format:**

```
fix(category): brief description

Optional longer description explaining the change.

Refs: BUG-XXX
```

**Categories:**

| Category | When to Use |
|----------|-------------|
| `runtime-error` | Crashes, exceptions, unhandled errors |
| `logic-error` | Incorrect calculations, wrong conditions, flawed algorithms |
| `ui-defect` | Visual bugs, layout issues, rendering problems |
| `performance` | Slowness, memory leaks, resource exhaustion |
| `security` | Vulnerabilities, auth bypasses, data exposure |
| `regression` | Previously working functionality that broke |

**Examples:**

```
fix(runtime-error): handle null user in profile lookup
```

```
fix(logic-error): correct discount calculation for bulk orders
```

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

## Pull Request Templates

### Feature PR

```bash
gh pr create --title "feat(FEAT-XXX): <description>" --body "## Feature
[FEAT-XXX](requirements/features/FEAT-XXX-description.md)

## Summary
Brief description of what this feature implements.

## Changes
- Change 1
- Change 2
- Change 3

## Testing
- [ ] Tests pass
- [ ] Build succeeds

## Related
- Closes #N <!-- REQUIRED if feature has a GitHub Issue link -->

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

### Chore PR

```bash
gh pr create --title "chore(category): description" --body "## Chore
[CHORE-XXX](requirements/chores/CHORE-XXX-description.md)

## Summary
Brief description of what this chore accomplishes.

## Changes
- Change 1
- Change 2
- Change 3

## Testing
- [ ] Tests pass
- [ ] Build succeeds
- [ ] Linting passes (if applicable)

## Related
- Closes #N <!-- REQUIRED if chore document has a GitHub Issue link -->

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

**Example:**

```bash
gh pr create --title "chore(dependencies): update typescript to 5.5" --body "## Chore
[CHORE-001](requirements/chores/CHORE-001-update-dependencies.md)

## Summary
Updates TypeScript from 5.4 to 5.5.4 for latest features and bug fixes.

## Changes
- Updated typescript in package.json
- Updated @types/node to compatible version
- Fixed one type error exposed by stricter checking

## Testing
- [x] Tests pass
- [x] Build succeeds
- [x] Linting passes

## Related
- Closes #12

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

### Bug Fix PR

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

---

## Creating New Issues

### Chore Issue

```bash
gh issue create --title "chore: brief description" --body "## Summary
Brief description of the maintenance work needed.

## Category
[dependencies|documentation|refactoring|configuration|cleanup]

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Notes
Any relevant context or constraints.

## Related
- Related issues or PRs (if any)"
```

**Example:**

```bash
gh issue create --title "chore: update npm dependencies" --body "## Summary
Update all npm dependencies to latest compatible versions. Address any security vulnerabilities.

## Category
dependencies

## Acceptance Criteria
- [ ] All packages updated to latest compatible versions
- [ ] No high/critical security vulnerabilities
- [ ] Build and tests pass
- [ ] No breaking changes (or documented if unavoidable)

## Notes
Last dependency update was 3 months ago. npm audit showing 2 moderate vulnerabilities.

## Related
- Security advisory for lodash CVE-2024-XXXX"
```

### Bug Issue

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
# Chore labels
gh issue create --title "..." --body "..." --label "chore" --label "dependencies"

# Bug labels
gh issue create --title "..." --body "..." --label "bug" --label "high-priority"
```

Common labels:
- `chore`, `dependencies`, `documentation`, `tech-debt`, `maintenance`
- `bug`, `critical`, `high-priority`, `regression`, `security`
