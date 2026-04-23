# Workflow Example: Implementing Phase 2 of Validate Command

This example demonstrates executing Phase 2 (Validation Engine) from the validate skill command implementation plan.

## Table of Contents

- [Context](#context)
- [Step-by-Step Execution](#step-by-step-execution)
  - [1. Update Implementation Doc Status](#1-update-implementation-doc-status)
  - [2. Read the Implementation Plan](#2-read-the-implementation-plan)
  - [3. Verify Prerequisites](#3-verify-prerequisites)
  - [4. Update GitHub Issue](#4-update-github-issue)
  - [5. Create Feature Branch](#5-create-feature-branch)
  - [6. Load Todos](#6-load-todos)
  - [7. Execute Each Step](#7-execute-each-step)
  - [8. Verify Deliverables](#8-verify-deliverables)
  - [9. Commit and Push Changes](#9-commit-and-push-changes)
  - [10. Update Plan Status](#10-update-plan-status)
  - [11. Update GitHub Issue](#11-update-github-issue)
- [Common Patterns](#common-patterns)
- [Result](#result)
- [Final Phase Completion](#final-phase-completion)

## Context

The implementation plan is at `requirements/implementation/02-validate-skill-command.md`.

Phase 1 (YAML Parsing Infrastructure) is complete. Phase 2 builds the validation engine.

## Step-by-Step Execution

### 1. Update Implementation Doc Status

Mark Phase 2 as "In Progress":

```markdown
### Phase 2: Validation Engine
**Feature:** [FEAT-002](../features/02-validate-skill-command.md) | [#2](https://github.com/lwndev/ai-skills-manager/issues/2)
**Status:** 🔄 In Progress
```

This signals work has started on this phase.

### 2. Read the Implementation Plan

```bash
# Locate the plan
ls requirements/implementation/
# Output: 02-validate-skill-command.md

# Read Phase 2 details
```

Phase 2 has:
- **Rationale**: Core functionality that orchestrates all validation checks
- **Implementation Steps**: 5 numbered steps
- **Deliverables**: 6 files to create

### 3. Verify Prerequisites

Check Phase 1 status shows "Complete":

```markdown
### Phase 1: YAML Parsing Infrastructure
**Status:** ✅ Complete
```

Verify Phase 1 deliverables exist:
- `src/utils/frontmatter-parser.ts`
- `src/types/validation.ts`
- `tests/unit/utils/frontmatter-parser.test.ts`

Extract GitHub issue number from phase header: `[#2]`

### 4. Update GitHub Issue

Post a comment to issue #2:

```bash
gh issue comment 2 --body "🔄 Starting Phase 2: Validation Engine

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

### 5. Create Feature Branch

```bash
git checkout -b feat/FEAT-002-validate-skill-command
```

### 6. Load Todos

Use TodoWrite with these items:

```
1. Create file-exists validator
2. Create required-fields validator
3. Create validation orchestrator
4. Write file-exists tests
5. Write required-fields tests
6. Write orchestrator tests
7. Verify all deliverables
```

### 7. Execute Each Step

**Step 1: Create file-exists validator**

Mark todo in_progress. Create `src/validators/file-exists.ts`:

```typescript
import * as fs from 'fs';
import * as path from 'path';

export interface FileExistsResult {
  exists: boolean;
  resolvedPath: string;
  error?: string;
}

export function validateFileExists(skillPath: string): FileExistsResult {
  // Handle file path pointing directly to SKILL.md
  if (skillPath.endsWith('SKILL.md')) {
    skillPath = path.dirname(skillPath);
  }

  const skillFile = path.join(skillPath, 'SKILL.md');

  if (!fs.existsSync(skillPath)) {
    return {
      exists: false,
      resolvedPath: skillFile,
      error: `Directory not found: ${skillPath}`
    };
  }

  if (!fs.existsSync(skillFile)) {
    return {
      exists: false,
      resolvedPath: skillFile,
      error: `SKILL.md not found in: ${skillPath}`
    };
  }

  return { exists: true, resolvedPath: skillFile };
}
```

Mark todo completed. Continue with next step.

**Steps 2-6: Continue pattern...**

Each step follows: mark in_progress, implement, mark completed.

### 8. Verify Deliverables

Run `verify-phase-deliverables.sh` (see `SKILL.md` Step 7 and `step-details.md`):

```bash
bash "$SCRIPTS/verify-phase-deliverables.sh" requirements/implementation/02-validate-skill-command.md 2
```

The JSON stdout shows `files.ok` listing the six deliverable files, `test: pass`, `build: pass`, `coverage: pass`, and exits `0`.

### 9. Commit and Push Changes

Commit and push via `commit-and-push-phase.sh` — no prompt, always mandatory:

```bash
bash "$SCRIPTS/commit-and-push-phase.sh" FEAT-002 2 "validation engine"
```

The script stages with `git add -A`, commits as `feat(FEAT-002): complete phase 2 - validation engine`, detects upstream, and pushes (`-u origin <branch>` on first push). Stdout: `pushed feat/FEAT-002-validate-skill-command`.

### 10. Update Plan Status

Transition Phase 2 to `✅ Complete` via `plan-status-marker.sh`:

```bash
bash "$SCRIPTS/plan-status-marker.sh" requirements/implementation/02-validate-skill-command.md 2 complete
```

The phase block now reads:

```markdown
### Phase 2: Validation Engine
**Feature:** [FEAT-002](../features/02-validate-skill-command.md) | [#2](https://github.com/lwndev/ai-skills-manager/issues/2)
**Status:** ✅ Complete

#### Deliverables
- [x] `src/validators/file-exists.ts` - File/directory existence validation
- [x] `src/validators/required-fields.ts` - Required fields validation
- [x] `src/generators/validate.ts` - Validation orchestration
- [x] `tests/unit/validators/file-exists.test.ts` - File existence tests
- [x] `tests/unit/validators/required-fields.test.ts` - Required fields tests
- [x] `tests/unit/generators/validate.test.ts` - Orchestrator tests
```

Deliverable lines were flipped to `- [x]` during Step 7 via `check-deliverable.sh` as each file was completed.

### 11. Update GitHub Issue

Post completion comment:

```bash
gh issue comment 2 --body "✅ Completed Phase 2: Validation Engine

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

**Status:** ✅ Complete"
```

## Common Patterns

### Reusing Existing Validators

Phase 2 notes existing validators to reuse:

```markdown
#### Rationale
- **Leverages existing code**: Reuses `validateName`, `validateDescription`,
  and `validateFrontmatterKeys` from scaffold implementation
```

Import and integrate rather than rewriting:

```typescript
import { validateName } from './name';
import { validateDescription } from './description';
import { validateFrontmatterKeys } from './frontmatter';
```

### Following Code Organization

The plan's **Code Organization** section shows file structure:

```
src/
├── generators/
│   └── validate.ts           # Phase 2: Validation orchestration
├── validators/
│   ├── file-exists.ts        # Phase 2: File existence check
│   └── required-fields.ts    # Phase 2: Required fields check
```

Follow this exactly for consistency.

### Handling Test Fixtures

Create test fixtures in the specified location:

```
tests/
└── fixtures/
    └── skills/
        ├── valid-skill/
        ├── missing-name/
        ├── invalid-yaml/
        └── ...
```

## Result

Phase 2 is complete when:
- All 6 deliverables created
- Tests pass with >80% coverage
- Build succeeds
- Changes committed and pushed to remote (mandatory — always commit and push without prompting)
- Plan status updated to "✅ Complete"
- All deliverable checkboxes marked `[x]`
- GitHub issue updated with completion comment

## Final Phase Completion

If Phase 2 were the final phase of the implementation, close the GitHub issue:

```bash
gh issue close 2 --comment "✅ All phases complete

**Feature Summary:**
- Phase 1: YAML Parsing Infrastructure ✅
- Phase 2: Validation Engine ✅

All deliverables implemented, tested, and verified.

FEAT-002 validate command implementation complete."
```
