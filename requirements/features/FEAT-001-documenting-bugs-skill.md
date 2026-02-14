# Feature Requirements: Documenting Bugs Skill

## Overview

Add a `documenting-bugs` skill that creates structured bug report documents for tracking defects and issues, with root cause analysis and traceability between root causes and acceptance criteria.

## Feature ID

`FEAT-001`

## GitHub Issue

[#8](https://github.com/lwndev/lwndev-agent-skills/issues/8)

## Priority

High - Fills a gap in the existing skill chain (features and chores are covered, but bugs are not)

## User Story

As a developer, I want to create structured bug report documents so that I can systematically track defects with reproduction steps, severity, root cause analysis, and traceable acceptance criteria before implementing fixes.

## Functional Requirements

### FR-1: Skill Structure

Create a new skill directory following the established pattern:

```
src/skills/documenting-bugs/
├── SKILL.md
├── assets/
│   └── bug-document.md
└── references/
    └── categories.md
```

### FR-2: SKILL.md

The skill instruction file must:

- Use YAML frontmatter with `name: documenting-bugs` and a description matching the issue spec
- Follow the same structure and tone as `documenting-chores/SKILL.md`
- Define "When to Use This Skill" covering: reported bugs, unexpected behavior, regressions, UI/UX defects, performance issues, security vulnerabilities
- Specify file location as `requirements/bugs/` with naming format `BUG-XXX-{2-4-word-description}.md`
- Document the Bug ID assignment process (check existing files, find highest number, increment by 1, start at `BUG-001` if none exist)
- Include a verification checklist enforcing root cause-to-acceptance-criteria traceability
- Include a "Relationship to Other Skills" table that references `documenting-features`, `documenting-chores`, this skill, and direct implementation
- Reference `executing-bug-fixes` as the follow-up skill

### FR-3: Bug Document Template (`assets/bug-document.md`)

The template must include these sections with HTML guidance comments (matching `chore-document.md` style):

| Section | Description |
|---------|-------------|
| **Bug ID** | `BUG-XXX` format |
| **GitHub Issue** | Optional link to GitHub issue |
| **Category** | One of the 6 defined categories |
| **Severity** | `critical`, `high`, `medium`, or `low` |
| **Description** | 1-2 sentences describing the defect |
| **Steps to Reproduce** | Numbered steps to trigger the bug |
| **Expected Behavior** | What should happen |
| **Actual Behavior** | What actually happens |
| **Root Cause(s)** | Numbered list of identified root causes with file references |
| **Affected Files** | List of files likely involved |
| **Acceptance Criteria** | Testable criteria with `(RC-N)` tags referencing root causes |
| **Completion** | Status (`Pending`/`In Progress`/`Completed`), date, PR link |
| **Notes** | Optional context (environment, workarounds) |

### FR-4: Root Cause Section

The Root Cause(s) section is required and must:

- Instruct the agent to investigate the codebase (read files, trace call paths) before finalizing the document
- Use numbered entries for cross-referencing with acceptance criteria
- Include file path references where applicable (e.g., `src/middleware/auth.ts:42`)
- Distinguish between symptoms and underlying causes

### FR-5: Acceptance Criteria Traceability

Each acceptance criterion in the bug document must:

- Reference one or more root causes using `(RC-N)` tags
- Ensure every root cause has at least one corresponding acceptance criterion
- Ensure every acceptance criterion references at least one root cause

### FR-6: Bug Categories (`references/categories.md`)

Define 6 bug categories with the same structure as the chore categories reference (heading, description, common use cases, typical affected files, suggested acceptance criteria, notes):

| Category | Use For |
|----------|---------|
| `runtime-error` | Crashes, unhandled exceptions, fatal errors |
| `logic-error` | Incorrect behavior, wrong calculations, bad state |
| `ui-defect` | Visual glitches, layout issues, rendering problems |
| `performance` | Slowness, memory leaks, resource exhaustion |
| `security` | Vulnerabilities, auth bypasses, data exposure |
| `regression` | Previously working functionality that broke |

### FR-7: Severity Levels

Document severity levels in the template with clear definitions:

| Severity | Definition |
|----------|------------|
| `critical` | Application unusable, data loss, security breach |
| `high` | Major feature broken, no workaround |
| `medium` | Feature impaired, workaround exists |
| `low` | Minor issue, cosmetic, edge case |

## Non-Functional Requirements

### NFR-1: Consistency

- SKILL.md must follow the same structure and tone as `documenting-chores/SKILL.md`
- Bug document template must use HTML comments for guidance (matching chore template style)
- Categories reference must follow the identical structure as chore `references/categories.md`

### NFR-2: Build and Test Compatibility

- The new skill must build successfully with `npm run build`
- All existing tests must continue to pass with `npm test`
- The skill must validate correctly via the `ai-skills-manager` `validate()` API

## Dependencies

- Existing `documenting-chores` skill as the structural reference
- `ai-skills-manager` for build and validation
- Future `executing-bug-fixes` skill (referenced but not implemented in this feature)

## Edge Cases

1. **No existing bugs directory**: The documenting agent should create `requirements/bugs/` if it doesn't exist
2. **Root cause not identifiable**: The agent should still document what is known and note that further investigation is needed
3. **Multiple root causes across different subsystems**: Each should be numbered separately for granular traceability
4. **Bug overlaps with chore**: The SKILL.md relationship table should help users choose the right skill

## Testing Requirements

### Build Validation

- `npm run build` succeeds with the new skill included
- Skill package is generated in `dist/`

### Existing Test Suite

- All existing tests pass (`npm test`)
- No regressions introduced

### Automated Tests

New tests must be added to the existing test suite (`scripts/__tests__/`) to verify the documenting-bugs skill. These tests follow the established patterns in `build.test.ts` and `skill-utils.test.ts`.

#### Build Integration Tests (in `build.test.ts`)

| Test | Description |
|------|-------------|
| **Skill package exists** | `dist/documenting-bugs.skill` is present after `npm run build` |
| **Package is valid archive** | `unzip -t` succeeds on `documenting-bugs.skill` |
| **Package contains SKILL.md** | `unzip -l` shows `SKILL.md` inside the package |

#### Source Skill Discovery Tests (in `skill-utils.test.ts`)

| Test | Description |
|------|-------------|
| **Skill is discoverable** | `getSourceSkills()` returns an entry with `name: 'documenting-bugs'` |
| **Description is present** | The discovered skill has a non-empty `description` |
| **Path is correct** | The discovered skill's `path` contains `src/skills/documenting-bugs` |

#### Skill Content Validation Tests (new `documenting-bugs.test.ts`)

Create a dedicated test file `scripts/__tests__/documenting-bugs.test.ts` with the following tests:

| Test | Description |
|------|-------------|
| **SKILL.md frontmatter** | Contains `name: documenting-bugs` and a non-empty `description` field |
| **SKILL.md required sections** | Contains "When to Use This Skill", "Verification Checklist", and "Relationship to Other Skills" sections |
| **SKILL.md follow-up reference** | References `executing-bug-fixes` as the follow-up skill |
| **SKILL.md file location** | Specifies `requirements/bugs/` as the document directory |
| **SKILL.md naming format** | Specifies `BUG-XXX` naming format |
| **Template exists** | `assets/bug-document.md` file exists |
| **Template required sections** | Template contains all sections from FR-3: Bug ID, GitHub Issue, Category, Severity, Description, Steps to Reproduce, Expected Behavior, Actual Behavior, Root Cause(s), Affected Files, Acceptance Criteria, Completion, Notes |
| **Template HTML comments** | Template uses HTML comments (`<!-- ... -->`) for guidance |
| **Template severity levels** | Template documents all 4 severity levels: `critical`, `high`, `medium`, `low` |
| **Template RC-N pattern** | Template contains `(RC-N)` or `(RC-1)` tagging convention in the acceptance criteria section |
| **Template root cause numbering** | Root Cause(s) section uses numbered entries |
| **Categories file exists** | `references/categories.md` file exists |
| **Categories coverage** | Categories file contains all 6 categories: `runtime-error`, `logic-error`, `ui-defect`, `performance`, `security`, `regression` |
| **Category detail sections** | Each category includes: common use cases, typical affected files, suggested acceptance criteria, and notes |

#### Validation API Test

| Test | Description |
|------|-------------|
| **Skill validates** | `validate()` from `ai-skills-manager` passes for the `documenting-bugs` skill directory |

### Manual Verification

- SKILL.md renders correctly and follows the documenting-chores pattern
- Bug document template includes all required sections with guidance comments
- Categories reference covers all 6 categories with complete detail
- Verification checklist includes root cause traceability checks

## Acceptance Criteria

- [ ] `SKILL.md` follows the same structure and tone as `documenting-chores/SKILL.md`
- [ ] Bug document template includes all required sections listed in FR-3
- [ ] Template includes Root Cause(s) section with numbered entries and guidance comments
- [ ] Template includes `(RC-N)` tagging convention in acceptance criteria with guidance comments
- [ ] SKILL.md verification checklist enforces root cause-to-acceptance criteria traceability
- [ ] `references/categories.md` has detailed guidance for all 6 bug categories
- [ ] Each category includes: common use cases, typical affected files, suggested acceptance criteria, and notes
- [ ] Severity levels are documented in the template with clear definitions
- [ ] File naming convention uses `BUG-XXX` format consistently
- [ ] Documents are stored in `requirements/bugs/`
- [ ] Skill correctly references `executing-bug-fixes` as the follow-up skill
- [ ] Template includes HTML comments with guidance (matching chore template style)
- [ ] All existing tests pass after adding the new skill
- [ ] Build succeeds with the new skill included
- [ ] `build.test.ts` updated to check for `documenting-bugs.skill` in dist
- [ ] `skill-utils.test.ts` updated to verify `documenting-bugs` is discoverable
- [ ] New `documenting-bugs.test.ts` validates SKILL.md frontmatter, required sections, and follow-up reference
- [ ] New `documenting-bugs.test.ts` validates template sections, HTML comments, severity levels, and RC-N pattern
- [ ] New `documenting-bugs.test.ts` validates categories file covers all 6 categories with full detail
- [ ] Validation API test confirms skill passes `validate()`
