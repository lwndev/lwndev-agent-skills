# Implementation Plan: Documenting Bugs Skill

## Overview

Add a `documenting-bugs` skill to the lwndev-agent-skills project that creates structured bug report documents for tracking defects and issues. This skill mirrors the existing `documenting-chores` skill but adds bug-specific workflows: reproduction steps, severity classification, root cause analysis, and traceability between root causes and acceptance criteria. It fills the gap in the existing skill chain by introducing a `documenting-bugs` → `executing-bug-fixes` workflow alongside the existing features and chores chains.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-001 | [#8](https://github.com/lwndev/lwndev-agent-skills/issues/8) | [FEAT-001-documenting-bugs-skill.md](../features/FEAT-001-documenting-bugs-skill.md) | High | Medium | Pending |

## Recommended Build Sequence

### Phase 1: Skill Structure and SKILL.md
**Feature:** [FEAT-001](../features/FEAT-001-documenting-bugs-skill.md) | [#8](https://github.com/lwndev/lwndev-agent-skills/issues/8)
**Status:** ✅ Complete

#### Rationale
- **Foundation first**: The SKILL.md is the entry point for the skill — it defines when and how the skill is used, and must exist before the template and references it points to
- **Establishes patterns**: Sets up the directory structure (`src/skills/documenting-bugs/`) and mirrors the `documenting-chores` skill organization
- **Enables validation**: Once SKILL.md exists with correct frontmatter, the skill becomes discoverable by `ai-skills-manager` and basic build/validation can be tested early

#### Implementation Steps
1. Create the skill directory structure:
   ```
   src/skills/documenting-bugs/
   ├── SKILL.md
   ├── assets/       (empty, populated in Phase 2)
   └── references/   (empty, populated in Phase 3)
   ```
2. Write `SKILL.md` with YAML frontmatter (`name: documenting-bugs`, `description` matching the issue spec)
3. Add "When to Use This Skill" section covering: reported bugs, unexpected behavior, regressions, UI/UX defects, performance issues, security vulnerabilities
4. Specify file location as `requirements/bugs/` with naming format `BUG-XXX-{2-4-word-description}.md`
5. Document the Bug ID assignment process (check existing files, find highest number, increment by 1, start at `BUG-001` if none exist)
6. Add bug categories overview referencing `references/categories.md` (6 categories: runtime-error, logic-error, ui-defect, performance, security, regression)
7. Add severity levels section (critical, high, medium, low) with clear definitions
8. Include a verification checklist enforcing root cause-to-acceptance-criteria traceability
9. Include "Relationship to Other Skills" table referencing `documenting-features`, `documenting-chores`, this skill, and direct implementation
10. Reference `executing-bug-fixes` as the follow-up skill
11. Verify SKILL.md follows the same structure and tone as `documenting-chores/SKILL.md`

#### Deliverables
- [x] `src/skills/documenting-bugs/SKILL.md` with complete instructions
- [x] `src/skills/documenting-bugs/assets/` directory created
- [x] `src/skills/documenting-bugs/references/` directory created

---

### Phase 2: Bug Document Template
**Feature:** [FEAT-001](../features/FEAT-001-documenting-bugs-skill.md) | [#8](https://github.com/lwndev/lwndev-agent-skills/issues/8)
**Status:** Pending

#### Rationale
- **Core deliverable**: The bug document template is what users actually produce when using the skill — it must include all required sections from FR-3
- **Depends on Phase 1**: The SKILL.md references this template; having SKILL.md in place ensures the template aligns with the documented instructions
- **Enables testing**: With the template in place, content validation tests can verify sections, HTML comments, severity levels, and the RC-N pattern

#### Implementation Steps
1. Create `assets/bug-document.md` using `documenting-chores/assets/chore-document.md` as the structural reference
2. Add all required sections with HTML guidance comments:
   - Bug ID (`BUG-XXX` placeholder)
   - GitHub Issue (optional link)
   - Category (one of 6 categories)
   - Severity (critical/high/medium/low with definitions)
   - Description (1-2 sentences)
   - Steps to Reproduce (numbered steps)
   - Expected Behavior
   - Actual Behavior
   - Root Cause(s) — numbered entries with file path references and guidance on investigation
   - Affected Files
   - Acceptance Criteria — with `(RC-N)` tagging convention and guidance comments
   - Completion (Status/Date/PR)
   - Notes (optional)
3. Include severity level definitions in the template with HTML comment guidance
4. Include example-style guidance in Root Cause(s) section showing numbered entries with file references
5. Include example-style guidance in Acceptance Criteria section showing `(RC-N)` tagging
6. Verify HTML comment style matches `chore-document.md` conventions

#### Deliverables
- [ ] `src/skills/documenting-bugs/assets/bug-document.md` with all required sections
- [ ] HTML guidance comments throughout the template
- [ ] Severity level definitions documented
- [ ] Root cause numbering pattern with file references
- [ ] `(RC-N)` tagging convention in acceptance criteria

---

### Phase 3: Bug Categories Reference
**Feature:** [FEAT-001](../features/FEAT-001-documenting-bugs-skill.md) | [#8](https://github.com/lwndev/lwndev-agent-skills/issues/8)
**Status:** Pending

#### Rationale
- **Completes the skill content**: The categories reference is the last content file, rounding out the skill's reference documentation
- **Mirrors chore pattern**: Must follow the identical structure as `documenting-chores/references/categories.md`
- **Enables full build**: With all three files in place, the skill can be built and packaged

#### Implementation Steps
1. Create `references/categories.md` using `documenting-chores/references/categories.md` as the structural reference
2. Define all 6 bug categories, each with:
   - Heading and description
   - Common use cases
   - Typical affected files
   - Suggested acceptance criteria
   - Notes
3. Categories to document:
   - `runtime-error` — Crashes, unhandled exceptions, fatal errors
   - `logic-error` — Incorrect behavior, wrong calculations, bad state
   - `ui-defect` — Visual glitches, layout issues, rendering problems
   - `performance` — Slowness, memory leaks, resource exhaustion
   - `security` — Vulnerabilities, auth bypasses, data exposure
   - `regression` — Previously working functionality that broke
4. Verify structure matches chore categories format exactly

#### Deliverables
- [ ] `src/skills/documenting-bugs/references/categories.md` with all 6 categories
- [ ] Each category has: common use cases, typical affected files, suggested acceptance criteria, notes

---

### Phase 4: Automated Tests
**Feature:** [FEAT-001](../features/FEAT-001-documenting-bugs-skill.md) | [#8](https://github.com/lwndev/lwndev-agent-skills/issues/8)
**Status:** Pending

#### Rationale
- **Depends on Phases 1-3**: All skill content must exist before tests can validate it
- **Validates requirements**: Tests encode the acceptance criteria from the feature spec, ensuring all requirements are met
- **Follows established patterns**: Extends existing test files (`build.test.ts`, `skill-utils.test.ts`) and creates a new dedicated test file

#### Implementation Steps
1. Update `scripts/__tests__/build.test.ts`:
   - Add test: `documenting-bugs.skill` exists in `dist/` after build
   - Add test: Package is a valid ZIP archive (`unzip -t`)
   - Add test: Package contains `SKILL.md`
2. Update `scripts/__tests__/skill-utils.test.ts`:
   - Add test: `getSourceSkills()` returns entry with `name: 'documenting-bugs'`
   - Add test: Discovered skill has non-empty `description`
   - Add test: Discovered skill's `path` contains `src/skills/documenting-bugs`
3. Create `scripts/__tests__/documenting-bugs.test.ts` with content validation tests:
   - SKILL.md frontmatter: contains `name: documenting-bugs` and non-empty `description`
   - SKILL.md required sections: "When to Use This Skill", "Verification Checklist", "Relationship to Other Skills"
   - SKILL.md follow-up reference: references `executing-bug-fixes`
   - SKILL.md file location: specifies `requirements/bugs/`
   - SKILL.md naming format: specifies `BUG-XXX`
   - Template exists: `assets/bug-document.md` file exists
   - Template required sections: all 13 sections from FR-3
   - Template HTML comments: uses `<!-- ... -->` guidance comments
   - Template severity levels: documents all 4 levels (critical, high, medium, low)
   - Template RC-N pattern: contains `(RC-N)` or `(RC-1)` in acceptance criteria section
   - Template root cause numbering: numbered entries in Root Cause(s) section
   - Categories file exists: `references/categories.md` exists
   - Categories coverage: all 6 categories present
   - Category detail sections: each has common use cases, typical affected files, suggested acceptance criteria, notes
4. Add validation API test: `validate()` from `ai-skills-manager` passes for the skill directory
5. Run `npm test` to verify all tests pass
6. Run `npm run build` to verify build succeeds with the new skill

#### Deliverables
- [ ] `scripts/__tests__/build.test.ts` updated with documenting-bugs build tests
- [ ] `scripts/__tests__/skill-utils.test.ts` updated with documenting-bugs discovery tests
- [ ] `scripts/__tests__/documenting-bugs.test.ts` created with all content validation tests
- [ ] Validation API test for `documenting-bugs` skill
- [ ] All existing tests continue to pass
- [ ] Build succeeds with new skill included

---

## Shared Infrastructure

No new shared infrastructure is needed. This feature adds content files (SKILL.md, template, categories) and tests, all following established patterns.

## Testing Strategy

### Automated Tests
- **Build integration** (`build.test.ts`): Verify skill package is generated, is a valid archive, and contains SKILL.md
- **Skill discovery** (`skill-utils.test.ts`): Verify skill is found by `getSourceSkills()` with correct metadata
- **Content validation** (`documenting-bugs.test.ts`): Verify SKILL.md structure, template sections, HTML comments, severity levels, RC-N pattern, and categories coverage
- **Validation API**: Confirm `validate()` passes for the skill directory

### Manual Verification
- SKILL.md renders correctly and follows the documenting-chores pattern
- Bug document template includes all required sections with guidance comments
- Categories reference covers all 6 categories with complete detail
- Verification checklist includes root cause traceability checks

## Dependencies and Prerequisites

| Dependency | Type | Status |
|------------|------|--------|
| `documenting-chores` skill | Structural reference | Available |
| `ai-skills-manager` | Build and validation | Available |
| `executing-bug-fixes` skill | Referenced follow-up (not yet implemented) | Not required for this feature |

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Template structure diverges from chore pattern | Medium | Low | Side-by-side comparison during implementation; tests enforce structure |
| Missing test coverage for edge cases | Low | Low | Feature spec provides exhaustive test table; follow it precisely |
| `ai-skills-manager` validation rejects new skill | Medium | Low | Run `validate()` early in Phase 1 to catch issues before writing all content |
| Root cause traceability concept unclear to users | Medium | Medium | Include clear examples and guidance comments in template |

## Success Criteria

### Feature Success
- All 27 acceptance criteria from the feature requirements document are met
- `npm run build` succeeds with the new skill packaged in `dist/`
- `npm test` passes with all new and existing tests
- Skill validates via `ai-skills-manager` `validate()` API

### Quality Metrics
- SKILL.md follows identical structure and tone to `documenting-chores/SKILL.md`
- Template HTML comment style matches chore template conventions
- Categories reference follows identical structure to chore categories

## Code Organization

```
src/skills/documenting-bugs/
├── SKILL.md                    # Skill instructions (Phase 1)
├── assets/
│   └── bug-document.md         # Bug report template (Phase 2)
└── references/
    └── categories.md           # Bug category guidance (Phase 3)

scripts/__tests__/
├── build.test.ts               # Updated: documenting-bugs build tests (Phase 4)
├── skill-utils.test.ts         # Updated: documenting-bugs discovery tests (Phase 4)
└── documenting-bugs.test.ts    # New: content validation tests (Phase 4)
```
