# Implementation Plan: Skill Allowed-Tools Declarations

## Overview

Add `allowed-tools` frontmatter to all 7 skill SKILL.md files so Claude Code auto-allows the tools each skill needs, eliminating repetitive permission prompts. This is a single-feature change touching SKILL.md frontmatter and skill tests — no new code paths or infrastructure required.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-003   | [#19](https://github.com/lwndev/lwndev-agent-skills/issues/19) | [FEAT-003-skill-allowed-tools.md](../features/FEAT-003-skill-allowed-tools.md) | High | Low | Pending |

## Recommended Build Sequence

### Phase 1: Add allowed-tools to Documenting Skills
**Feature:** [FEAT-003](../features/FEAT-003-skill-allowed-tools.md) | [#19](https://github.com/lwndev/lwndev-agent-skills/issues/19)
**Status:** ✅ Complete

#### Rationale
- Start with the 4 documenting/planning skills since they share identical tool lists and are lower risk (read/write only, no Bash or Agent)
- Establishes the pattern for the execution skills in Phase 2
- Lets us validate the `asm validate` integration before tackling the more permissive execution skills

#### Implementation Steps
1. Add `allowed-tools` to `src/skills/documenting-features/SKILL.md` frontmatter:
   ```yaml
   allowed-tools:
     - Read
     - Write
     - Edit
     - Glob
     - Grep
   ```
2. Add identical `allowed-tools` to `src/skills/documenting-chores/SKILL.md`
3. Add identical `allowed-tools` to `src/skills/documenting-bugs/SKILL.md`
4. Add identical `allowed-tools` to `src/skills/creating-implementation-plans/SKILL.md`
5. Add `allowed-tools` tests to `scripts/__tests__/documenting-bugs.test.ts` — verify field is present with expected tools and does NOT include `Bash` or `Agent`
6. Create `scripts/__tests__/documenting-features.test.ts` with frontmatter and `allowed-tools` tests
7. Create `scripts/__tests__/documenting-chores.test.ts` with frontmatter and `allowed-tools` tests
8. Create `scripts/__tests__/creating-implementation-plans.test.ts` with frontmatter and `allowed-tools` tests
9. Run `npm test` to verify all tests pass and `asm validate` succeeds (covered by build.test.ts)

#### Deliverables
- [x] `src/skills/documenting-features/SKILL.md` — `allowed-tools` added
- [x] `src/skills/documenting-chores/SKILL.md` — `allowed-tools` added
- [x] `src/skills/documenting-bugs/SKILL.md` — `allowed-tools` added
- [x] `src/skills/creating-implementation-plans/SKILL.md` — `allowed-tools` added
- [x] `scripts/__tests__/documenting-features.test.ts` — new test file
- [x] `scripts/__tests__/documenting-chores.test.ts` — new test file
- [x] `scripts/__tests__/creating-implementation-plans.test.ts` — new test file
- [x] `scripts/__tests__/documenting-bugs.test.ts` — updated with `allowed-tools` tests
- [x] All tests pass, `asm validate` succeeds

---

### Phase 2: Add allowed-tools to Execution Skills
**Feature:** [FEAT-003](../features/FEAT-003-skill-allowed-tools.md) | [#19](https://github.com/lwndev/lwndev-agent-skills/issues/19)
**Status:** ✅ Complete

#### Rationale
- Execution skills need `Bash` and `Agent` in addition to the base tools — kept separate to clearly distinguish the two permission tiers
- Builds on the pattern established in Phase 1
- Tests verify execution skills include `Bash` and `Agent` while documenting skills do not

#### Implementation Steps
1. Add `allowed-tools` to `src/skills/executing-chores/SKILL.md` frontmatter:
   ```yaml
   allowed-tools:
     - Read
     - Write
     - Edit
     - Bash
     - Glob
     - Grep
     - Agent
   ```
2. Add identical `allowed-tools` to `src/skills/executing-bug-fixes/SKILL.md`
3. Add identical `allowed-tools` to `src/skills/implementing-plan-phases/SKILL.md`
4. Add `allowed-tools` tests to `scripts/__tests__/executing-bug-fixes.test.ts` — verify field is present with expected tools and DOES include `Bash` and `Agent`
5. Create `scripts/__tests__/executing-chores.test.ts` with frontmatter and `allowed-tools` tests
6. Create `scripts/__tests__/implementing-plan-phases.test.ts` with frontmatter and `allowed-tools` tests
7. Run `npm test` to verify all tests pass
8. Run `npm run build` to verify `.skill` packages build correctly with updated frontmatter

#### Deliverables
- [x] `src/skills/executing-chores/SKILL.md` — `allowed-tools` added
- [x] `src/skills/executing-bug-fixes/SKILL.md` — `allowed-tools` added
- [x] `src/skills/implementing-plan-phases/SKILL.md` — `allowed-tools` added
- [x] `scripts/__tests__/executing-chores.test.ts` — new test file
- [x] `scripts/__tests__/implementing-plan-phases.test.ts` — new test file
- [x] `scripts/__tests__/executing-bug-fixes.test.ts` — updated with `allowed-tools` tests
- [x] All tests pass, build succeeds

## Shared Infrastructure

No new shared infrastructure required. Existing test patterns in `documenting-bugs.test.ts` and `executing-bug-fixes.test.ts` provide the template for new test files. The `ai-skills-manager` v1.8.0+ `validate()` API already supports `allowedToolsFormat` checking.

## Testing Strategy

**Unit Tests (per skill):**
- Verify `allowed-tools` field is present in SKILL.md frontmatter
- Verify the tool list contains the expected entries
- Documenting skills: assert `Bash` and `Agent` are NOT in `allowed-tools`
- Execution skills: assert `Bash` and `Agent` ARE in `allowed-tools`

**Integration Tests (existing):**
- `build.test.ts` already validates all skills via `asm validate` and packages them — no changes needed
- Build test confirms `.skill` packages contain valid SKILL.md with frontmatter

## Dependencies and Prerequisites

| Dependency | Version | Status |
|------------|---------|--------|
| `ai-skills-manager` | v1.8.0+ | Installed (v1.8.1) — provides `allowed-tools` frontmatter validation |

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| `asm validate` rejects `allowed-tools` format | Med | Low | v1.8.1 already installed and supports the field; test early in Phase 1 |
| Typo in tool name causes Claude Code to ignore it | Low | Low | Tests verify exact tool list contents; Claude Code falls back to prompting |
| New test files have different patterns than existing | Low | Low | Follow established patterns in `documenting-bugs.test.ts` |

## Success Criteria

- All 7 SKILL.md files have `allowed-tools` in frontmatter
- Documenting skills declare exactly: Read, Write, Edit, Glob, Grep
- Execution skills declare exactly: Read, Write, Edit, Bash, Glob, Grep, Agent
- All skills pass `asm validate`
- Each skill has tests verifying `allowed-tools` presence and correct tool lists
- No existing tests broken
- `npm run build` produces valid `.skill` packages

## Code Organization
```
src/skills/
├── documenting-features/SKILL.md      # Phase 1 — add allowed-tools
├── documenting-chores/SKILL.md        # Phase 1 — add allowed-tools
├── documenting-bugs/SKILL.md          # Phase 1 — add allowed-tools
├── creating-implementation-plans/SKILL.md  # Phase 1 — add allowed-tools
├── executing-chores/SKILL.md          # Phase 2 — add allowed-tools
├── executing-bug-fixes/SKILL.md       # Phase 2 — add allowed-tools
└── implementing-plan-phases/SKILL.md  # Phase 2 — add allowed-tools

scripts/__tests__/
├── documenting-features.test.ts       # Phase 1 — new
├── documenting-chores.test.ts         # Phase 1 — new
├── documenting-bugs.test.ts           # Phase 1 — update
├── creating-implementation-plans.test.ts  # Phase 1 — new
├── executing-chores.test.ts           # Phase 2 — new
├── executing-bug-fixes.test.ts        # Phase 2 — update
└── implementing-plan-phases.test.ts   # Phase 2 — new
```
