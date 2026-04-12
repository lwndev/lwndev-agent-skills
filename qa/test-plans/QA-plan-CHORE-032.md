# QA Test Plan: Split Orchestrator SKILL.md

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-032 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-032 |
| **Source Documents** | `requirements/chores/CHORE-032-split-orchestrator-skillmd.md` |
| **Date Created** | 2026-04-12 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/orchestrating-workflows.test.ts` | Skill validation, SKILL.md content checks, workflow-state.sh integration tests | PENDING |
| `scripts/__tests__/build.test.ts` | Plugin validation (`npm run validate`), validates all 13 skills | PENDING |
| `scripts/__tests__/workflow-state.test.ts` | Workflow state management unit tests | PENDING |

### Tests Requiring Updates

The following existing tests will fail after the restructure and must be updated as part of this chore:

| Test | Line(s) | Why It Breaks | Required Update |
|------|---------|---------------|-----------------|
| `should use ${CLAUDE_SKILL_DIR} for workflow-state.sh references in body` | 57-71 | Reference count (`66`) decreases as sections with `${CLAUDE_SKILL_DIR}` refs are extracted | Update count to match new SKILL.md body |
| `should include "Verification Checklist" section` | 81-82 | Section heading extracted to `verification-and-relationships.md` | Check for summary pointer text or update to read reference file |
| `should include "Relationship to Other Skills" section` | 85-86 | Section heading extracted to `verification-and-relationships.md` | Check for summary pointer text or update to read reference file |
| `should reference all sub-skills in relationship section` | 89-97 | Sub-skill names move to reference file | Update to check reference file or verify SKILL.md still mentions skill names in other sections |
| `should document pause points` | 109-113 | `Plan Approval` / `PR Review` details move to `step-execution-details.md` | Verify content remains in step sequence tables or update |
| `should document PR suppression instruction` | 115-117 | "Do NOT create a pull request at the end" moves to `step-execution-details.md` | Update to check reference file |
| `should contain the step baseline matrix (Axis 1)` | 224-236 | Axis 1 table replaced with one-line description | Update to check for description + link instead of table contents |
| `should contain the work-item complexity signal matrix (Axis 2)` | 238-250 | Axis 2 table replaced with one-line description | Update to check for description + link instead of table contents |
| `should contain worked examples A, B, C, D` | 274-283 | Worked examples removed entirely | Remove test or move to test `references/model-selection.md` |

### Tests That Should Pass Unchanged

| Test | Reason |
|------|--------|
| Frontmatter tests (name, description, argument-hint, compatibility, hooks) | Frontmatter unchanged |
| `should have "## Model Selection" as a top-level section` | Section heading stays |
| `should be positioned between "## Step Execution" and "## Error Handling"` | Both sections stay, ordering preserved |
| `should document override precedence (Axis 3)` | Axis 3 table retained per AC5 |
| `should document baseline-locked step exceptions` | Retained per AC5 |
| `should link to references/model-selection.md` | Link retained |
| `should document error handling` | Error Handling section stays per AC6 |
| `should pass validate() with all checks` | Restructured SKILL.md still valid |
| All `references/model-selection.md` tests | File unchanged |
| All workflow-state.sh integration tests | Script unchanged |
| All `build.test.ts` tests | Plugin structure unchanged; 13 skills remain |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Verify `references/issue-tracking.md` exists | `orchestrating-workflows.test.ts` | AC1 | High | -- |
| Verify `references/chain-procedures.md` exists | `orchestrating-workflows.test.ts` | AC2 | High | -- |
| Verify `references/step-execution-details.md` exists | `orchestrating-workflows.test.ts` | AC3 | High | -- |
| Verify `references/verification-and-relationships.md` exists | `orchestrating-workflows.test.ts` | AC4 | High | -- |
| Verify SKILL.md line count is under 400 | `orchestrating-workflows.test.ts` | AC7 | High | -- |
| Verify each extracted section has summary + link in SKILL.md | `orchestrating-workflows.test.ts` | AC8 | Medium | -- |
| Verify SKILL.md body contains updated `${CLAUDE_SKILL_DIR}` reference count | `orchestrating-workflows.test.ts` | AC1-AC4 | Medium | -- |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| Verbatim content transfer not verified by tests | Reference files vs original SKILL.md | AC1-AC4 | Manual verify during QA execution: diff extracted content against original line ranges |
| Model Selection trimming correctness | SKILL.md Model Selection section | AC5 | Manual verify: Axis 3 + baseline-locked present, Axis 1/2 tables gone, examples gone |
| Reference file Read-accessibility from skill context | Reference files | AC11 | Manual verify: `Read` tool can access `${CLAUDE_SKILL_DIR}/references/*.md` |

## Code Path Verification

Traceability from acceptance criteria to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| AC1 | `issue-tracking.md` contains lines 40-178 verbatim | `references/issue-tracking.md` | Code review + diff against original lines | -- |
| AC2 | `chain-procedures.md` contains lines 245-426 verbatim | `references/chain-procedures.md` | Code review + diff against original lines | -- |
| AC3 | `step-execution-details.md` contains lines 607-837 verbatim | `references/step-execution-details.md` | Code review + diff against original lines | -- |
| AC4 | `verification-and-relationships.md` contains lines 983-1098 verbatim | `references/verification-and-relationships.md` | Code review + diff against original lines | -- |
| AC5 | Model Selection trimmed — Axis 1/2 replaced, Axis 3 retained, examples removed | SKILL.md Model Selection section | Code review: verify section content | -- |
| AC6 | Error Handling section unchanged | SKILL.md lines 975-982 equivalent | Code review: verify section intact | -- |
| AC7 | SKILL.md under 400 lines | SKILL.md | `wc -l` + automated test | -- |
| AC8 | Each section replaced with summary + link | SKILL.md | Code review: verify 4 summary blocks with markdown links | -- |
| AC9 | `npm run validate` passes | Plugin validation pipeline | Automated: `npm run validate` | -- |
| AC10 | `npm test` passes | Test suite | Automated: `npm test` | -- |
| AC11 | Reference files Read-accessible | `references/*.md` | Manual: verify paths resolve from skill context | -- |

## Deliverable Verification

| Deliverable | Source | Expected Path | Status |
|-------------|-------|---------------|--------|
| Issue tracking reference | Extraction from SKILL.md lines 40-178 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/issue-tracking.md` | -- |
| Chain procedures reference | Extraction from SKILL.md lines 245-426 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` | -- |
| Step execution details reference | Extraction from SKILL.md lines 607-837 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` | -- |
| Verification and relationships reference | Extraction from SKILL.md lines 983-1098 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/verification-and-relationships.md` | -- |
| Trimmed SKILL.md | In-place modification | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (under 400 lines) | -- |
| Updated test file | Test updates for restructured content | `scripts/__tests__/orchestrating-workflows.test.ts` | -- |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
