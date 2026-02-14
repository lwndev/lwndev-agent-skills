# Implementation Plan: Executing Bug Fixes Skill

## Overview

Add an `executing-bug-fixes` skill to the lwndev-agent-skills project that executes bug fix workflows from branch creation through pull request. This skill mirrors the existing `executing-chores` skill but is tailored for bug fixes: `fix/` branch prefixes, `fix()` commit conventions, root cause driven execution that systematically addresses each root cause from the bug document, and a PR template with root cause traceability. It completes the `documenting-bugs` → `executing-bug-fixes` skill chain, paralleling the existing `documenting-chores` → `executing-chores` chain.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-002 | [#9](https://github.com/lwndev/lwndev-agent-skills/issues/9) | [FEAT-002-executing-bug-fixes-skill.md](../features/FEAT-002-executing-bug-fixes-skill.md) | High | Medium | Pending |

## Recommended Build Sequence

### Phase 1: Skill Structure and SKILL.md
**Feature:** [FEAT-002](../features/FEAT-002-executing-bug-fixes-skill.md) | [#9](https://github.com/lwndev/lwndev-agent-skills/issues/9)
**Status:** ✅ Complete

#### Rationale
- **Foundation first**: The SKILL.md is the entry point — it defines the workflow, trigger phrases, and root cause driven execution model that all other files support
- **Establishes patterns**: Sets up the directory structure (`src/skills/executing-bug-fixes/`) mirroring `executing-chores`
- **Enables validation**: Once SKILL.md exists with correct frontmatter, the skill becomes discoverable by `ai-skills-manager` and basic build/validation can be tested early

#### Implementation Steps
1. Create the skill directory structure:
   ```
   src/skills/executing-bug-fixes/
   ├── SKILL.md
   ├── assets/       (empty, populated in Phase 2)
   └── references/   (empty, populated in Phase 3)
   ```
2. Write `SKILL.md` using `executing-chores/SKILL.md` as the structural reference
3. Add YAML frontmatter with `name: executing-bug-fixes` and description covering trigger phrases ("execute bug fix", "fix this bug", "run the bug fix workflow") and references to `requirements/bugs/`
4. Add "When to Use This Skill" section covering: executing documented bug fixes, referencing bug documents, implementing fixes, and continuing previously started work
5. Document the Quick Start workflow (13 steps per FR-3): locate bug doc → extract info → redeclare root causes → note GitHub issue → post start comment → create branch → address root causes → commit → verify per-RC → verify reproduction → run tests → create PR → update bug doc
6. Document the Root Cause Driven Execution workflow (per FR-4): redeclare root causes at start, address systematically, verify per RC, confirm full coverage, handle new root cause discovery
7. Specify branch naming format: `fix/BUG-XXX-{2-4-word-description}` using Bug ID
8. Specify commit format: `fix(category): brief description` with categories table (`runtime-error`, `logic-error`, `ui-defect`, `performance`, `security`, `regression`)
9. Add verification checklist (per FR-8): all root causes addressed, each `(RC-N)` criterion met, reproduction steps verified, tests pass, build succeeds, scope matches, no regressions
10. Add "Relationship to Other Skills" table referencing `documenting-bugs` as the prerequisite skill
11. Document that PR body must include `Closes #N` when bug document has a GitHub Issue link
12. Add references section linking to `workflow-details.md`, `github-templates.md`, and `pr-template.md`
13. Verify SKILL.md follows the same structure and tone as `executing-chores/SKILL.md`

#### Deliverables
- [x] `src/skills/executing-bug-fixes/SKILL.md` with complete instructions
- [x] `src/skills/executing-bug-fixes/assets/` directory created
- [x] `src/skills/executing-bug-fixes/references/` directory created
- [x] Root cause driven execution workflow documented
- [x] Verification checklist included

---

### Phase 2: PR Template
**Feature:** [FEAT-002](../features/FEAT-002-executing-bug-fixes-skill.md) | [#9](https://github.com/lwndev/lwndev-agent-skills/issues/9)
**Status:** Pending

#### Rationale
- **Core output artifact**: The PR template defines the structure of every bug fix pull request — it must exist before the workflow details reference it
- **Depends on Phase 1**: The SKILL.md references this template; alignment requires SKILL.md to be in place first
- **Key differentiator**: The Root Cause(s) section and "How Each Root Cause Was Addressed" traceability table are the central differences from the chore PR template

#### Implementation Steps
1. Create `assets/pr-template.md` using `executing-chores/assets/pr-template.md` as the structural reference
2. Add all required sections (per FR-5):
   - **Bug** — Link to bug document (`BUG-XXX`)
   - **Summary** — Brief description of the fix (1-2 sentences)
   - **Root Cause(s)** — Redeclared numbered root causes from the bug document
   - **How Each Root Cause Was Addressed** — Traceability table mapping `RC-N` to fix applied and files changed
   - **Changes** — Bullet list of changes
   - **Testing** — Checklist with per-root-cause verification items, reproduction verification, tests pass, build succeeds, no regressions
   - **Related** — `Closes #N` (required if bug document has GitHub Issue link)
   - **Footer** — Claude Code attribution
3. Add a filled example showing a realistic bug fix (e.g., BUG-001 with two root causes)
4. Add `gh pr create` CLI usage example with the full body
5. Add section guidelines with detailed instructions for each section
6. Include critical note: "Use `Closes #N` to auto-close linked issue on merge" — required if bug document has GitHub Issue link

#### Deliverables
- [ ] `src/skills/executing-bug-fixes/assets/pr-template.md` with all required sections
- [ ] Root Cause(s) section with numbered entries
- [ ] "How Each Root Cause Was Addressed" traceability table
- [ ] Per-root-cause verification in testing checklist
- [ ] `Closes #N` placeholder in Related section
- [ ] Filled example and section guidelines

---

### Phase 3: Reference Documents
**Feature:** [FEAT-002](../features/FEAT-002-executing-bug-fixes-skill.md) | [#9](https://github.com/lwndev/lwndev-agent-skills/issues/9)
**Status:** Pending

#### Rationale
- **Completes skill content**: The workflow details and GitHub templates are the last content files, rounding out the skill's reference documentation
- **Depends on Phases 1-2**: Both reference files reference the PR template structure and align with the SKILL.md workflow
- **Mirrors chore pattern**: Must follow the identical structure as `executing-chores/references/` files

#### Implementation Steps

**Workflow Details (`references/workflow-details.md`)**:
1. Create `references/workflow-details.md` using `executing-chores/references/workflow-details.md` as the structural reference
2. Document Phase 1 (Initialization) per FR-6: locate bug doc, extract Bug ID/severity/category/reproduction steps/root causes, redeclare root causes as work items, check GitHub issue and post starting comment with root causes, create branch `fix/BUG-XXX-description`
3. Document Phase 2 (Execution) per FR-6: load acceptance criteria grouped by root cause, for each RC investigate/implement/verify `(RC-N)` criteria/mark as addressed, verify reproduction steps no longer trigger bug, commit with `fix(category): message` format
4. Document Phase 3 (Completion) per FR-6: confirm all root causes addressed, run tests/build, create PR with `Closes #N` and traceability table, update bug document completion section
5. Add Error Recovery section: same patterns as chore workflow (dirty working directory, branch already exists, tests failing, PR already exists, GitHub CLI unavailability) plus bug-specific recovery (new root cause discovered, root cause cannot be fully addressed)
6. Add Common Git Commands section

**GitHub Templates (`references/github-templates.md`)**:
7. Create `references/github-templates.md` using `executing-chores/references/github-templates.md` as the structural reference
8. Add Starting Work comment template per FR-7: includes bug document link, severity, root causes to address, acceptance criteria checklist, branch name, status
9. Add Work Complete comment template per FR-7: includes PR number, per-RC resolution status with checkmarks, verification summary (all root causes addressed, reproduction steps verified, tests passing, build successful)
10. Add Commit Message section: format `fix(category): description`, categories table with examples (`runtime-error`, `logic-error`, `ui-defect`, `performance`, `security`, `regression`)
11. Add Pull Request section: title format, full body template with root cause traceability, critical `Closes #N` note
12. Add Creating New Issues section (mirroring chore template)

#### Deliverables
- [ ] `src/skills/executing-bug-fixes/references/workflow-details.md` with all 3 phases
- [ ] Root cause redeclaration in Phase 1
- [ ] Per-root-cause execution loop in Phase 2
- [ ] Reproduction verification step
- [ ] Error recovery including bug-specific scenarios
- [ ] `src/skills/executing-bug-fixes/references/github-templates.md`
- [ ] Starting work comment template with root causes
- [ ] Work complete comment template with per-RC resolution status
- [ ] Commit message categories table with examples

---

### Phase 4: Automated Tests
**Feature:** [FEAT-002](../features/FEAT-002-executing-bug-fixes-skill.md) | [#9](https://github.com/lwndev/lwndev-agent-skills/issues/9)
**Status:** Pending

#### Rationale
- **Depends on Phases 1-3**: All skill content must exist before tests can validate it
- **Validates requirements**: Tests encode the acceptance criteria from the feature spec, ensuring all requirements are met
- **Follows established patterns**: Extends existing test files (`build.test.ts`, `skill-utils.test.ts`) and creates a new dedicated test file following `documenting-bugs.test.ts` patterns

#### Implementation Steps
1. Update `scripts/__tests__/build.test.ts`:
   - Add `executing-bug-fixes.skill` to the expected skill files list
2. Update `scripts/__tests__/skill-utils.test.ts`:
   - Add `'executing-bug-fixes'` to the known skills list in the "should include known skills" test
   - Add test: `executing-bug-fixes` discovered with correct metadata (non-empty description, path contains `src/skills/executing-bug-fixes`)
3. Create `scripts/__tests__/executing-bug-fixes.test.ts` with content validation tests:

   **SKILL.md tests:**
   - Frontmatter contains `name: executing-bug-fixes` and non-empty `description`
   - Required sections: "When to Use This Skill", "Quick Start", "Verification Checklist", "Relationship to Other Skills"
   - Prerequisite reference: references `documenting-bugs` as prerequisite skill
   - Branch format: specifies `fix/BUG-XXX` branch naming format
   - Commit format: specifies `fix(category):` commit message format
   - Root cause workflow: documents root cause driven execution (redeclare, address systematically, verify per RC)
   - Closes #N enforcement: documents that PR body must include `Closes #N` when GitHub issue exists

   **PR template tests:**
   - PR template exists: `assets/pr-template.md` file exists
   - Root cause section: contains "Root Cause(s)" section
   - Traceability table: contains "How Each Root Cause Was Addressed" table
   - Per-RC testing: testing checklist includes per-root-cause verification items
   - Closes #N: includes `Closes #N` placeholder

   **Workflow details tests:**
   - File exists: `references/workflow-details.md` exists
   - Three phases: contains Phase 1 (Initialization), Phase 2 (Execution), Phase 3 (Completion)
   - Root cause redeclaration: Phase 1 includes redeclaring root causes from bug document
   - Reproduction verification: Phase 2 or 3 includes verifying reproduction steps no longer trigger the bug

   **GitHub templates tests:**
   - File exists: `references/github-templates.md` exists
   - Start comment: contains starting work comment template with root causes listed
   - Completion comment: contains completion comment template with per-RC resolution status

   **Validation API test:**
   - `validate()` from `ai-skills-manager` passes for the `executing-bug-fixes` skill directory

4. Run `npm test` to verify all tests pass
5. Run `npm run build` to verify build succeeds with the new skill

#### Deliverables
- [ ] `scripts/__tests__/build.test.ts` updated with `executing-bug-fixes.skill` in expected list
- [ ] `scripts/__tests__/skill-utils.test.ts` updated with `executing-bug-fixes` discovery tests
- [ ] `scripts/__tests__/executing-bug-fixes.test.ts` created with all content validation tests
- [ ] Validation API test for `executing-bug-fixes` skill
- [ ] All existing tests continue to pass
- [ ] Build succeeds with new skill included

---

## Shared Infrastructure

No new shared infrastructure is needed. This feature adds content files (SKILL.md, PR template, workflow details, GitHub templates) and tests, all following established patterns from `executing-chores`.

## Testing Strategy

### Automated Tests
- **Build integration** (`build.test.ts`): Verify `executing-bug-fixes.skill` package is generated in `dist/`
- **Skill discovery** (`skill-utils.test.ts`): Verify skill is found by `getSourceSkills()` with correct metadata
- **Content validation** (`executing-bug-fixes.test.ts`): Verify SKILL.md structure, root cause workflow, PR template sections, workflow phases, and GitHub templates
- **Validation API**: Confirm `validate()` passes for the skill directory

### Manual Verification
- SKILL.md renders correctly and follows the `executing-chores` pattern
- PR template includes root cause traceability table with clear examples
- Workflow details cover all 3 phases with root cause driven adaptations
- GitHub templates include root causes in both start and completion comments
- Verification checklist includes all 7 items from FR-8

## Dependencies and Prerequisites

| Dependency | Type | Status |
|------------|------|--------|
| `executing-chores` skill | Structural reference | Available |
| `documenting-bugs` skill (FEAT-001) | Prerequisite skill (reads from `requirements/bugs/`) | Available |
| `ai-skills-manager` | Build and validation | Available |

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Skill structure diverges from `executing-chores` pattern | Medium | Low | Side-by-side comparison during implementation; tests enforce structure |
| Root cause traceability table format unclear | Medium | Low | Include filled example in PR template with realistic multi-RC bug fix |
| Missing test coverage for required content | Low | Low | Feature spec provides exhaustive test table; follow it precisely |
| `ai-skills-manager` validation rejects new skill | Medium | Low | Run `validate()` early in Phase 1 to catch issues before writing all content |

## Success Criteria

### Feature Success
- All acceptance criteria from the feature requirements document are met
- `npm run build` succeeds with the new skill packaged in `dist/`
- `npm test` passes with all new and existing tests
- Skill validates via `ai-skills-manager` `validate()` API

### Quality Metrics
- SKILL.md follows identical structure and tone to `executing-chores/SKILL.md`
- PR template clearly shows root cause traceability (RC-N → fix → files)
- Workflow details mirror chore workflow structure with bug-specific adaptations
- GitHub templates include root causes in both issue comments

## Code Organization

```
src/skills/executing-bug-fixes/
├── SKILL.md                    # Skill instructions (Phase 1)
├── assets/
│   └── pr-template.md          # PR template for bug fixes (Phase 2)
└── references/
    ├── workflow-details.md     # Step-by-step workflow (Phase 3)
    └── github-templates.md    # GitHub interaction templates (Phase 3)

scripts/__tests__/
├── build.test.ts               # Updated: executing-bug-fixes build tests (Phase 4)
├── skill-utils.test.ts         # Updated: executing-bug-fixes discovery tests (Phase 4)
└── executing-bug-fixes.test.ts # New: content validation tests (Phase 4)
```
