# QA Test Plan: Fix Findings-Handling Spiral on Bug/Chore Chains

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-FEAT-015 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-015 |
| **Source Documents** | `requirements/features/FEAT-015-findings-handling-spiral-fix.md`, `requirements/implementation/FEAT-015-findings-handling-spiral-fix.md` |
| **Date Created** | 2026-04-12 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/orchestrating-workflows.test.ts` | Validates SKILL.md frontmatter, structure, and workflow-state.sh subcommands | PASS |
| `scripts/__tests__/reviewing-requirements.test.ts` | Validates reviewing-requirements SKILL.md structure | PASS |
| `scripts/__tests__/build.test.ts` | Plugin validation pipeline | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Verify Decision Flow contains chain-type/complexity gate with `jq` reads | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | FR-1, FR-2 | High | PASS |
| Verify Decision Flow warnings-only branch has bug/chore auto-advance path | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | FR-1 | High | PASS |
| Verify Decision Flow preserves feature-chain interactive prompt | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | NFR-1 | High | PASS |
| Verify `[info]` log line format matches FR-4 specification | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | FR-4 | Medium | PASS |
| Verify Applying Auto-Fixes step 4 lists all three re-run outcomes | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | FR-3 | High | PASS |
| Verify no-edits-after-re-run rule is the dominant statement | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | FR-3 | High | PASS |
| Verify null-coalescing in jq expression (`.complexity // "medium"`) | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | EC-1 | Medium | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| Behavioral testing of orchestrator findings handling | `orchestrating-workflows` SKILL.md prose | FR-1, FR-3 | Manual verification — prose changes are LLM instructions, not executable code |
| End-to-end workflow run with warnings-only findings | Orchestrator runtime behavior | AC-1, AC-2 | Manual testing per Testing Requirements in FEAT-015 |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| FR-1 | Auto-advance on warnings-only for bug/chore at complexity <= medium | SKILL.md Decision Flow item 2: gate reads `.type` and `.complexity // "medium"`, auto-advances for bug/chore + low/medium | Code review of SKILL.md edit | PASS |
| FR-2 | Chain-type awareness in Decision Flow | SKILL.md Decision Flow item 2: `type=$(jq -r '.type' ".sdlc/workflows/{ID}.json")` | Code review of SKILL.md edit | PASS |
| FR-3 | No edits after re-run | SKILL.md Applying Auto-Fixes step 4: dominant statement "do not apply any further edits regardless...", three explicit outcomes | Code review of SKILL.md edit | PASS |
| FR-4 | Informational logging for auto-advanced findings | SKILL.md Decision Flow item 2 auto-advance path: `[info] {N} warnings, {N} info from reviewing-requirements ({mode}) — auto-advancing (chain={type}, complexity={complexity})` | Code review of SKILL.md edit | PASS |
| NFR-1 | No feature-chain regression | SKILL.md Decision Flow item 2 prompt branch: "any feature chain" retains existing prompt behavior | Code review of SKILL.md edit | PASS |
| NFR-2 | Scope limited to SKILL.md Decision Flow + Applying Auto-Fixes | No other files modified; no workflow-state.sh, reviewing-requirements, or schema changes | Git diff review | PASS |
| NFR-3 | Deterministic behavior | Gate is keyed on literal string values from state file (`.type`, `.complexity`); no LLM judgment | Code review of SKILL.md edit | PASS |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| Updated Decision Flow subsection | Phase 1 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (lines ~262-291) | PASS |
| Updated Applying Auto-Fixes subsection | Phase 1 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (lines ~293-307) | PASS |

## Verification Checklist

- [x] Bug/chore chains with `complexity <= medium` auto-advance on warnings-only findings from `reviewing-requirements` standard mode (AC-1)
- [x] Bug/chore chains with `complexity <= medium` auto-advance on warnings-only findings from `reviewing-requirements` test-plan and code-review modes (AC-2)
- [x] The "no edits after re-run" rule is unambiguous — the re-run is terminal regardless of findings (AC-3)
- [x] Feature-chain behavior is unchanged at all complexities (AC-4)
- [x] `complexity == high` bug/chore chains still prompt the user on warnings-only findings (AC-5)
- [x] Auto-advanced findings are logged with the `[info]` format from FR-4 (AC-6)
- [x] Null complexity treated as `medium` via `jq -r '.complexity // "medium"'` (EC-1)
- [x] Re-run that returns errors pauses without further edits (EC-2)
- [x] Re-run that returns warnings advances without further edits (EC-3)
- [x] High-complexity chore/bug retains interactive prompt (EC-4)
- [x] Mixed findings (errors + warnings) on initial run takes the "Errors present" branch (EC-5)
- [x] No changes to `reviewing-requirements` skill (NFR-2)
- [x] No changes to `workflow-state.sh` script (NFR-2)
- [x] No changes to state file schema (NFR-2)
- [x] All existing tests pass (regression baseline)

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
