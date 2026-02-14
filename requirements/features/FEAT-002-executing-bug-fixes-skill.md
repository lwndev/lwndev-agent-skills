# Feature Requirements: Executing Bug Fixes Skill

## Overview

Add an `executing-bug-fixes` skill that executes bug fix workflows from branch creation through pull request, with root cause driven execution that systematically addresses each root cause from the bug document and verifies traceability.

## Feature ID

`FEAT-002`

## GitHub Issue

[#9](https://github.com/lwndev/lwndev-agent-skills/issues/9)

## Priority

High - Completes the `documenting-bugs` → `executing-bug-fixes` skill chain, paralleling the existing `documenting-chores` → `executing-chores` chain

## User Story

As a developer, I want to execute a documented bug fix workflow so that I can systematically address each root cause, verify all acceptance criteria, and create a pull request with full traceability from root cause to fix.

## Functional Requirements

### FR-1: Skill Structure

Create a new skill directory following the established `executing-chores` pattern:

```
src/skills/executing-bug-fixes/
├── SKILL.md
├── assets/
│   └── pr-template.md
└── references/
    ├── workflow-details.md
    └── github-templates.md
```

### FR-2: SKILL.md

The skill instruction file must:

- Use YAML frontmatter with `name: executing-bug-fixes` and a description covering trigger phrases ("execute bug fix", "fix this bug", "run the bug fix workflow") and references to `requirements/bugs/`
- Follow the same structure and tone as `executing-chores/SKILL.md`
- Define "When to Use This Skill" covering: executing documented bug fixes, referencing bug documents, implementing fixes, and continuing previously started work
- Document the Quick Start workflow (see FR-3)
- Document root cause driven execution (see FR-4)
- Specify branch naming: `fix/BUG-XXX-{2-4-word-description}` using Bug ID
- Specify commit format: `fix(category): brief description` with categories (`runtime-error`, `logic-error`, `ui-defect`, `performance`, `security`, `regression`)
- Include a verification checklist (see FR-7)
- Include a "Relationship to Other Skills" table referencing `documenting-bugs` as the prerequisite skill
- Document that PR body must include `Closes #N` when a GitHub issue exists

### FR-3: Quick Start Workflow

The SKILL.md Quick Start must define these steps (mirroring `executing-chores`):

1. Locate bug document in `requirements/bugs/`
2. Extract Bug ID, severity, root cause(s), and review acceptance criteria
3. Redeclare root causes from the bug document into the workflow context
4. Note GitHub issue number if linked (needed for PR to auto-close issue)
5. Post start comment on GitHub issue (if exists) — include root causes
6. Create git branch: `fix/BUG-XXX-description`
7. Address each root cause systematically, implementing fixes and tracking with todos
8. Commit changes with `fix(category): description` messages
9. Verify each root cause is addressed and reproduction steps no longer trigger the bug
10. Run tests/build verification
11. Create pull request (MUST include `Closes #N` if issue exists)
12. Update bug document completion section (status, date, PR link)

### FR-4: Root Cause Driven Execution

The SKILL.md must document the root cause driven execution workflow:

1. **Redeclare root causes at start** — Load the root causes from the bug document into the todo list as trackable work items
2. **Address root causes systematically** — Work through each root cause in order, implementing the fix for that specific cause before moving to the next
3. **Verify per root cause** — After addressing each root cause, verify that the corresponding `(RC-N)` acceptance criteria pass
4. **Confirm full coverage** — Before creating the PR, confirm that every `RC-N` has been addressed and its acceptance criteria are met

Additionally, if a new root cause is discovered during execution:
- Document it in the bug document as a new `RC-N` entry
- Add corresponding acceptance criteria with the `(RC-N)` tag
- Address it as part of the fix

### FR-5: PR Template (`assets/pr-template.md`)

The PR template must mirror the chore PR template but adapted for bug fixes, including:

| Section | Description |
|---------|-------------|
| **Bug** | Link to bug document (`BUG-XXX`) |
| **Summary** | Brief description of the fix (1-2 sentences) |
| **Root Cause(s)** | Redeclared root causes from the bug document |
| **How Each Root Cause Was Addressed** | Traceability table mapping `RC-N` to fix applied and files changed |
| **Changes** | Bullet list of changes |
| **Testing** | Checklist with per-root-cause verification, reproduction verification, tests pass, build succeeds, no regressions |
| **Related** | `Closes #N` (required if bug document has a GitHub Issue link) |

Key differences from chore template: includes Root Cause(s) section, "How Each Root Cause Was Addressed" traceability table, and per-root-cause verification in the testing checklist.

### FR-6: Workflow Details (`references/workflow-details.md`)

Mirror `executing-chores/references/workflow-details.md` with these phases:

**Phase 1: Initialization**
1. Locate bug document in `requirements/bugs/`
2. Extract Bug ID, severity, category, reproduction steps, and root causes
3. Redeclare root causes — list them explicitly as work items to track
4. Check GitHub issue if linked, post starting comment (include root causes)
5. Create git branch: `fix/BUG-XXX-description`

**Phase 2: Execution**
6. Load acceptance criteria into todos, grouped by root cause
7. For each root cause (RC-1, RC-2, ...): investigate, implement fix, verify `(RC-N)` acceptance criteria, mark as addressed
8. Verify reproduction steps no longer trigger the bug
9. Commit with `fix(category): message` format

**Phase 3: Completion**
10. Confirm all root causes addressed — verify every `RC-N` has been fixed and its criteria met
11. Run tests/build verification
12. Create pull request (MUST include `Closes #N` if issue exists) with root cause traceability table
13. Update bug document completion section

**Error Recovery** — Same patterns as chore workflow (dirty working directory, branch already exists, tests failing, PR already exists, GitHub CLI unavailability) plus bug-specific recovery:
- New root cause discovered during fix — Add to bug document, add acceptance criteria, address it
- Root cause cannot be fully addressed — Document limitation in bug document Notes section, mark criterion as partially met with explanation

### FR-7: GitHub Templates (`references/github-templates.md`)

Mirror `executing-chores/references/github-templates.md` with these adaptations:

- **Starting work comment** — Includes root causes to address, acceptance criteria checklist, branch name, and status
- **Work complete comment** — Includes per-RC resolution status with checkmarks, verification summary (all root causes addressed, reproduction steps verified, tests passing, build successful)
- **Commit message examples** — Table of categories with examples using `fix(category): description` format
- **PR title format** and full body template with root cause traceability

### FR-8: Verification Checklist

The SKILL.md must include a pre-PR verification checklist:

- [ ] All root causes from bug document are addressed
- [ ] Each `(RC-N)` tagged acceptance criterion is met
- [ ] Reproduction steps no longer trigger the bug
- [ ] Tests pass (if applicable)
- [ ] Build succeeds
- [ ] Changes match the scope defined in bug document
- [ ] No unintended side effects or regressions

## Non-Functional Requirements

### NFR-1: Consistency

- SKILL.md must follow the same structure and tone as `executing-chores/SKILL.md`
- PR template must follow the same style as the chore PR template
- Workflow details and GitHub templates must use the same format as their chore counterparts
- Branch naming, commit format, and PR conventions must be consistently documented across all files

### NFR-2: Build and Test Compatibility

- The new skill must build successfully with `npm run build`
- All existing tests must continue to pass with `npm test`
- The skill must validate correctly via the `ai-skills-manager` `validate()` API

## Dependencies

- Existing `executing-chores` skill as the structural reference
- `documenting-bugs` skill (FEAT-001) must be implemented first, since this skill reads from `requirements/bugs/`
- `ai-skills-manager` for build and validation

## Edge Cases

1. **Bug document has a single root cause**: Workflow still follows the same structure but with only one RC to track
2. **New root cause discovered during execution**: Must be added to the bug document and addressed (documented in FR-4)
3. **Root cause cannot be fully addressed**: Document limitation, mark as partially met with explanation
4. **No GitHub issue linked**: Skip GitHub comment steps, omit `Closes #N` from PR
5. **Bug document missing root causes section**: Agent should investigate the codebase and add root causes before proceeding
6. **Multiple bugs sharing a root cause**: Each bug gets its own fix workflow; shared fixes should reference both documents

## Testing Requirements

### Build Validation

- `npm run build` succeeds with the new skill included
- Skill package is generated in `dist/`

### Existing Test Suite

- All existing tests pass (`npm test`)
- No regressions introduced

### Automated Tests

New tests must be added to the existing test suite (`scripts/__tests__/`) following the established patterns in `build.test.ts` and `skill-utils.test.ts`.

#### Build Integration Tests (in `build.test.ts`)

| Test | Description |
|------|-------------|
| **Skill package exists** | `dist/executing-bug-fixes.skill` is present after `npm run build` |
| **Package is valid archive** | `unzip -t` succeeds on `executing-bug-fixes.skill` |
| **Package contains SKILL.md** | `unzip -l` shows `SKILL.md` inside the package |

#### Source Skill Discovery Tests (in `skill-utils.test.ts`)

| Test | Description |
|------|-------------|
| **Skill is discoverable** | `getSourceSkills()` returns an entry with `name: 'executing-bug-fixes'` |
| **Description is present** | The discovered skill has a non-empty `description` |
| **Path is correct** | The discovered skill's `path` contains `src/skills/executing-bug-fixes` |

#### Skill Content Validation Tests (new `executing-bug-fixes.test.ts`)

Create a dedicated test file `scripts/__tests__/executing-bug-fixes.test.ts` with these tests:

| Test | Description |
|------|-------------|
| **SKILL.md frontmatter** | Contains `name: executing-bug-fixes` and a non-empty `description` field |
| **SKILL.md required sections** | Contains "When to Use This Skill", "Quick Start", "Verification Checklist", and "Relationship to Other Skills" sections |
| **SKILL.md prerequisite reference** | References `documenting-bugs` as the prerequisite skill |
| **SKILL.md branch format** | Specifies `fix/BUG-XXX-description` branch naming format |
| **SKILL.md commit format** | Specifies `fix(category): description` commit message format |
| **SKILL.md root cause workflow** | Documents root cause driven execution (redeclare, address systematically, verify per RC) |
| **SKILL.md Closes #N enforcement** | Documents that PR body must include `Closes #N` when GitHub issue exists |
| **PR template exists** | `assets/pr-template.md` file exists |
| **PR template root cause section** | PR template contains a "Root Cause(s)" section |
| **PR template traceability table** | PR template contains "How Each Root Cause Was Addressed" table |
| **PR template per-RC testing** | PR template testing checklist includes per-root-cause verification items |
| **PR template Closes #N** | PR template includes `Closes #N` placeholder |
| **Workflow details exists** | `references/workflow-details.md` file exists |
| **Workflow 3 phases** | Workflow details contains Phase 1 (Initialization), Phase 2 (Execution), Phase 3 (Completion) |
| **Workflow root cause redeclaration** | Phase 1 includes redeclaring root causes from bug document |
| **Workflow reproduction verification** | Phase 2 or 3 includes verifying reproduction steps no longer trigger the bug |
| **GitHub templates exists** | `references/github-templates.md` file exists |
| **GitHub templates start comment** | Contains a starting work comment template with root causes listed |
| **GitHub templates completion comment** | Contains a completion comment template with per-RC resolution status |

#### Validation API Test

| Test | Description |
|------|-------------|
| **Skill validates** | `validate()` from `ai-skills-manager` passes for the `executing-bug-fixes` skill directory |

## Acceptance Criteria

- [ ] `SKILL.md` follows the same structure and tone as `executing-chores/SKILL.md`
- [ ] SKILL.md documents the root cause driven execution workflow
- [ ] Workflow redeclares root causes from bug document at initialization
- [ ] Execution phase addresses root causes systematically (RC-1, RC-2, ...)
- [ ] Verification confirms every `RC-N` is addressed before PR creation
- [ ] Branch naming uses `fix/BUG-XXX-description` format
- [ ] Commit messages use `fix(category): description` format
- [ ] PR template includes Root Cause(s) section and "How Each Root Cause Was Addressed" traceability table
- [ ] PR template testing checklist includes per-root-cause verification
- [ ] `references/workflow-details.md` covers all 3 phases with root-cause-driven adaptations
- [ ] `references/github-templates.md` includes root causes in both start and completion comments
- [ ] Workflow handles discovery of new root causes during execution
- [ ] Workflow includes explicit step to verify reproduction steps no longer trigger the bug
- [ ] PR body enforces `Closes #N` when GitHub issue exists (matching chore behavior)
- [ ] Skill correctly references `documenting-bugs` as the prerequisite skill
- [ ] All existing tests pass after adding the new skill
- [ ] Build succeeds with the new skill included
- [ ] `build.test.ts` updated to check for `executing-bug-fixes.skill` in dist
- [ ] `skill-utils.test.ts` updated to verify `executing-bug-fixes` is discoverable
- [ ] New `executing-bug-fixes.test.ts` validates SKILL.md frontmatter, required sections, and prerequisite reference
- [ ] New `executing-bug-fixes.test.ts` validates SKILL.md documents root cause driven workflow, branch/commit formats, and Closes #N enforcement
- [ ] New `executing-bug-fixes.test.ts` validates PR template includes root cause section, traceability table, and per-RC testing
- [ ] New `executing-bug-fixes.test.ts` validates workflow details covers all 3 phases with root cause redeclaration and reproduction verification
- [ ] New `executing-bug-fixes.test.ts` validates GitHub templates include root causes in start and completion comments
- [ ] Validation API test confirms skill passes `validate()`
