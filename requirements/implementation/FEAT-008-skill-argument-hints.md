# Implementation Plan: Skill Argument-Hint Support

## Overview

Add `argument-hint` frontmatter and argument-handling instructions to 10 skills in the `lwndev-sdlc` plugin, enabling users to pass context directly when invoking skills (e.g., `/executing-chores CHORE-007`). The `finalizing-workflow` skill is intentionally excluded.

All changes are to SKILL.md files — no application code changes. The work is phased by argument-handling pattern since each category of skill resolves arguments differently.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-008 | [#14](https://github.com/lwndev/lwndev-marketplace/issues/14) | [FEAT-008-skill-argument-hints.md](../features/FEAT-008-skill-argument-hints.md) | Medium | Low | Pending |

## Recommended Build Sequence

### Phase 1: Execution Skills — Frontmatter and Argument Handling
**Feature:** [FEAT-008](../features/FEAT-008-skill-argument-hints.md) | [#14](https://github.com/lwndev/lwndev-marketplace/issues/14)
**Status:** ✅ Complete

#### Rationale
- Execution skills have the most complex argument resolution pattern (ID prefix matching against `requirements/` subdirectories)
- Establishes the argument-handling instruction pattern that later phases will follow
- These skills benefit most from argument support — they currently scan directories and prompt for selection

#### Skills
| Skill | `argument-hint` | Resolution Pattern |
|-------|-----------------|-------------------|
| `executing-chores` | `<chore-id>` | Prefix match in `requirements/chores/` |
| `executing-bug-fixes` | `<bug-id>` | Prefix match in `requirements/bugs/` |
| `implementing-plan-phases` | `<plan-file> [phase-number]` | Prefix match in `requirements/implementation/`, parse optional phase number |
| `executing-qa` | `<requirement-id>` | Prefix match across `requirements/` subdirectories |

#### Implementation Steps
1. Add `argument-hint` field to YAML frontmatter in each skill's SKILL.md
   - Values with leading `[` must be quoted; `<angle-bracket>` values do not need quoting
2. Add an argument-handling section after the "Quick Start" section in each SKILL.md body with:
   - **When argument is provided**: Match argument against files in the relevant `requirements/` subdirectory by ID prefix (e.g., `CHORE-007` matches `CHORE-007-migrate-config.md`). If no match, inform user and fall back to interactive selection. If multiple matches, present options.
   - **When no argument is provided**: Fall back to current behavior (scan directory, prompt user to select)
3. For `implementing-plan-phases`: document parsing of multi-part argument (`FEAT-001 3` = plan file + phase number). Include edge case for out-of-range phase numbers.
4. Validate all four skills pass `asm validate`

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` — frontmatter + argument handling
- [x] `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` — frontmatter + argument handling
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` — frontmatter + argument handling
- [x] `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — frontmatter + argument handling

---

### Phase 2: Documentation and Planning Skills — Frontmatter and Argument Handling
**Feature:** [FEAT-008](../features/FEAT-008-skill-argument-hints.md) | [#14](https://github.com/lwndev/lwndev-marketplace/issues/14)
**Status:** ✅ Complete
**Depends on:** Phase 1 (follows the argument-handling instruction pattern established there)

#### Rationale
- Documentation skills use a simpler pattern: argument pre-fills a name/title rather than resolving a file
- Planning/review skills resolve requirements files similarly to execution skills but target different directories
- Grouping these together keeps the plan to three phases without sacrificing clarity

#### Skills — Documentation
| Skill | `argument-hint` | Resolution Pattern |
|-------|-----------------|-------------------|
| `documenting-features` | `"[feature-name or #issue-number]"` | Pre-fill name; `#N` fetches GitHub issue |
| `documenting-chores` | `"[chore-title]"` | Pre-fill chore title |
| `documenting-bugs` | `"[bug-title]"` | Pre-fill bug title |
| `documenting-qa` | `<requirement-id>` | Prefix match across `requirements/` subdirectories |

#### Skills — Planning/Review
| Skill | `argument-hint` | Resolution Pattern |
|-------|-----------------|-------------------|
| `creating-implementation-plans` | `<requirements-file>` | Prefix match in `requirements/features/` |
| `reviewing-requirements` | `<requirements-file>` | Prefix match in `requirements/features/`, `requirements/chores/`, `requirements/bugs/` |

#### Implementation Steps
1. Add `argument-hint` field to YAML frontmatter in each skill's SKILL.md
   - Quote values starting with `[`: `argument-hint: "[feature-name or #issue-number]"`
2. Add argument-handling section after "Quick Start" in each documentation skill's SKILL.md:
   - **When argument is provided**: Use as pre-filled name/title for the document being created. For `documenting-features` with `#N` syntax, fetch the GitHub issue and use its content to pre-fill the template. If GitHub API fails, warn and continue with manual input.
   - **When no argument is provided**: Fall back to current behavior (prompt user interactively)
3. Add argument-handling section in each planning/review skill's SKILL.md:
   - **When argument is provided**: Match argument against files in the relevant `requirements/` subdirectory by ID prefix. If no match, inform user and fall back.
   - **When no argument is provided**: Fall back to current behavior (scan directories, prompt user)
4. Validate all six skills pass `asm validate`

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` — frontmatter + argument handling
- [x] `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md` — frontmatter + argument handling
- [x] `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md` — frontmatter + argument handling
- [x] `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` — frontmatter + argument handling
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md` — frontmatter + argument handling
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — frontmatter + argument handling

---

### Phase 3: Tests and Validation
**Feature:** [FEAT-008](../features/FEAT-008-skill-argument-hints.md) | [#14](https://github.com/lwndev/lwndev-marketplace/issues/14)
**Status:** 🔄 In Progress
**Depends on:** Phase 1, Phase 2

#### Rationale
- Tests run after all SKILL.md changes are complete to validate the full set
- Full plugin validation confirms no regressions across all 11 skills
- Automated tests ensure the argument-hint infrastructure won't silently regress

#### Implementation Steps
1. Create `scripts/__tests__/argument-hint.test.ts` with:
   - Verify `argument-hint` is present in frontmatter for all 10 target skills
   - Verify `finalizing-workflow` does not have `argument-hint`
   - Validate all hint values are ≤ 200 characters
   - Validate YAML quoting: values starting with `[` must parse as strings, not arrays
   - Verify each target skill's SKILL.md body contains argument-handling guidance (grep for "When argument is provided" and "When no argument is provided")
2. Use `validate()` API from `ai-skills-manager` to run `argumentHintFormat` check against a temp skill with representative hint values
3. Run `npm run validate` to confirm full plugin passes
4. Run `npm test` to confirm no regressions

#### Deliverables
- [x] `scripts/__tests__/argument-hint.test.ts` — unit tests for argument-hint frontmatter and instructions
- [x] Full plugin validation passing (`npm run validate`)
- [x] Full test suite passing (`npm test`)

---

## Shared Infrastructure

No shared infrastructure changes required. All changes are to SKILL.md files (frontmatter and markdown body). The `ai-skills-manager` ^1.8.1 already supports `argument-hint` validation. Arguments are delivered via the existing `ARGUMENTS:` appended mechanism.

## Testing Strategy

### Unit Testing
- **Framework:** Vitest (existing)
- **Test file:** `scripts/__tests__/argument-hint.test.ts`
- **Focus areas:**
  - Frontmatter presence and format validation
  - YAML quoting correctness for bracket values
  - `finalizing-workflow` exclusion (negative test)
  - Argument-handling instruction presence in SKILL.md body

### Integration Testing
- Full plugin validation via `npm run validate` (runs `ai-skills-manager` `validate()` on all 11 skills)
- Build script processes all updated SKILL.md files without errors

### Manual Testing
- Invoke each skill with an argument and verify resolution
- Invoke each skill without an argument and verify pre-FEAT-008 behavior is preserved
- Test edge cases: no match, multiple matches, empty argument, out-of-range phase number

## Dependencies and Prerequisites

### Already Available
- `ai-skills-manager` ^1.8.1 with `argumentHintFormat` validation
- `gray-matter` for YAML frontmatter parsing in tests
- All 11 skill SKILL.md files in `plugins/lwndev-sdlc/skills/`
- Existing test infrastructure (Vitest, test patterns in `scripts/__tests__/`)

### No New Dependencies Required

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| YAML parsing of bracket values | Medium | Low | Verified during manual testing — quoting rules documented in NFR-3 |
| Argument-handling instructions alter skill behavior | Medium | Low | Instructions use conditional language ("if provided... otherwise fall back"); backward compatibility tested manually |
| `npm run validate` rejects new frontmatter | Low | Very Low | `argument-hint` already supported by `ai-skills-manager` ^1.8.1; validated with test skills |

## Success Criteria

- All 10 target skills have `argument-hint` in frontmatter
- All 10 target skills include argument-handling sections with "When argument is provided" / "When no argument is provided" guidance
- `finalizing-workflow` has no `argument-hint`
- `npm run validate` passes for all 11 skills
- `npm test` passes with new argument-hint tests
- Skills invoked without arguments behave identically to pre-FEAT-008

## Code Organization

All changes are within the existing directory structure:

```
plugins/lwndev-sdlc/skills/
├── creating-implementation-plans/SKILL.md  # Phase 2: + argument-hint, + handling section
├── documenting-bugs/SKILL.md               # Phase 2: + argument-hint, + handling section
├── documenting-chores/SKILL.md             # Phase 2: + argument-hint, + handling section
├── documenting-features/SKILL.md           # Phase 2: + argument-hint, + handling section
├── documenting-qa/SKILL.md                 # Phase 2: + argument-hint, + handling section
├── executing-bug-fixes/SKILL.md            # Phase 1: + argument-hint, + handling section
├── executing-chores/SKILL.md               # Phase 1: + argument-hint, + handling section
├── executing-qa/SKILL.md                   # Phase 1: + argument-hint, + handling section
├── finalizing-workflow/SKILL.md            # No changes (intentionally excluded)
├── implementing-plan-phases/SKILL.md       # Phase 1: + argument-hint, + handling section
└── reviewing-requirements/SKILL.md         # Phase 2: + argument-hint, + handling section

scripts/__tests__/
└── argument-hint.test.ts                   # Phase 3: new test file
```
