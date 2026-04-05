# QA Test Plan: Managing Work Items Skill

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-FEAT-012 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-012 |
| **Source Documents** | `requirements/features/FEAT-012-managing-work-items-skill.md`, `requirements/implementation/FEAT-012-managing-work-items-skill.md` |
| **Date Created** | 2026-04-04 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/implementing-plan-phases.test.ts` | Validates implementing-plan-phases skill structure, SKILL.md, and references | PASS |
| `scripts/__tests__/executing-chores.test.ts` | Validates executing-chores skill structure, SKILL.md, and references | PASS |
| `scripts/__tests__/executing-bug-fixes.test.ts` | Validates executing-bug-fixes skill structure, SKILL.md, and references | PASS |
| `scripts/__tests__/documenting-features.test.ts` | Validates documenting-features skill structure and SKILL.md | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` | Validates orchestrating-workflows skill structure and SKILL.md | PASS |
| `scripts/__tests__/build.test.ts` | Validates all plugins pass `npm run validate` | PASS |
| `scripts/__tests__/skill-utils.test.ts` | Validates skill discovery and plugin utilities | PASS |
| `scripts/__tests__/workflow-state.test.ts` | Validates workflow state management scripts | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Skill directory exists with expected structure (`SKILL.md`, `references/github-templates.md`, `references/jira-templates.md`) | `plugins/lwndev-sdlc/skills/managing-work-items/` | FR-1, FR-2, FR-3 | High | PASS |
| SKILL.md passes `validate()` from `ai-skills-manager` | `managing-work-items/SKILL.md` | AC: skill exists with SKILL.md | High | PASS |
| SKILL.md frontmatter contains `name: managing-work-items`, `allowed-tools`, `argument-hint` | `managing-work-items/SKILL.md` | AC: skill exists | High | PASS |
| SKILL.md documents backend detection (`#N` → GitHub, `PROJ-123` → Jira) | `managing-work-items/SKILL.md` | FR-1 | High | PASS |
| SKILL.md documents GitHub fetch and comment operations | `managing-work-items/SKILL.md` | FR-2 | High | PASS |
| SKILL.md documents Jira tiered fallback (Rovo MCP → acli → skip) | `managing-work-items/SKILL.md` | FR-3 | High | PASS |
| SKILL.md documents all six comment types (phase-start, phase-completion, work-start, work-complete, bug-start, bug-complete) | `managing-work-items/SKILL.md` | FR-5 | High | PASS |
| SKILL.md documents PR body issue link generation (`Closes #N`, `PROJ-123`) | `managing-work-items/SKILL.md` | FR-6 | Medium | PASS |
| SKILL.md documents issue reference extraction from `## GitHub Issue` section | `managing-work-items/SKILL.md` | FR-7 | Medium | PASS |
| SKILL.md documents graceful degradation behavior | `managing-work-items/SKILL.md` | NFR-1 | Medium | PASS |
| SKILL.md documents MCP-specific error handling (fallthrough to acli) | `managing-work-items/SKILL.md` | NFR-2 | Medium | PASS |
| `references/github-templates.md` contains all six comment type templates | `managing-work-items/references/github-templates.md` | FR-5, NFR-4 | High | PASS |
| `references/github-templates.md` consolidates templates from three source skills | `managing-work-items/references/github-templates.md` | AC: consolidated | High | PASS |
| `references/jira-templates.md` contains all six comment type templates in ADF JSON format | `managing-work-items/references/jira-templates.md` | FR-8, NFR-4 | High | PASS |
| Jira ADF templates are valid ADF (contain `"version": 1`, `"type": "doc"`, `"content"` array) | `managing-work-items/references/jira-templates.md` | FR-8 | High | PASS |
| Jira templates include work item ID traceability (FEAT-XXX, CHORE-XXX, BUG-XXX) | `managing-work-items/references/jira-templates.md` | NFR-4 | Medium | PASS |
| Bug-related Jira templates preserve RC-N tagging | `managing-work-items/references/jira-templates.md` | NFR-4 | Medium | PASS |
| `implementing-plan-phases/SKILL.md` no longer contains inline `gh issue` operations | `implementing-plan-phases/SKILL.md` | AC: refactored | High | PASS |
| `implementing-plan-phases/references/github-templates.md` deleted | `implementing-plan-phases/references/` | AC: refactored | High | PASS |
| `executing-chores/SKILL.md` no longer contains inline `gh issue` operations | `executing-chores/SKILL.md` | AC: refactored | High | PASS |
| `executing-chores/references/github-templates.md` deleted | `executing-chores/references/` | AC: refactored | High | PASS |
| `executing-bug-fixes/SKILL.md` no longer contains inline `gh issue` operations | `executing-bug-fixes/SKILL.md` | AC: refactored | High | PASS |
| `executing-bug-fixes/references/github-templates.md` deleted | `executing-bug-fixes/references/` | AC: refactored | High | PASS |
| `documenting-features/SKILL.md` references `managing-work-items` for issue fetch delegation | `documenting-features/SKILL.md` | AC: delegation | Medium | PASS |
| `orchestrating-workflows/SKILL.md` contains `managing-work-items` invocation points for all three chain types | `orchestrating-workflows/SKILL.md` | AC: orchestrator updated | High | PASS |
| All skills pass `npm run validate` | All skill directories | AC: validation | High | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| Rovo MCP tool invocation (no local MCP server to test against) | `managing-work-items/SKILL.md` Jira Rovo MCP path | FR-3 Tier 1 | Manual verify if Jira environment available; otherwise verify documentation accuracy only |
| `acli` CLI invocation (optional dependency, may not be installed) | `managing-work-items/SKILL.md` Jira acli path | FR-3 Tier 2 | Manual verify if acli installed; otherwise verify documentation accuracy only |
| Actual GitHub issue comment posting (requires live `gh` auth) | `managing-work-items/SKILL.md` GitHub comment path | FR-2 | Manual testing with live GitHub issue during feature chain execution |
| ADF template validation against Jira REST API (requires Jira instance) | `managing-work-items/references/jira-templates.md` | FR-8 | Validate ADF structure locally (JSON schema); full API validation deferred to Jira integration |
| End-to-end orchestrated workflow with `managing-work-items` invocations | `orchestrating-workflows/SKILL.md` | AC: workflows function | Manual testing of full feature/chore/bug chains post-implementation |
| Alphanumeric Jira project keys (e.g., `PROJ2-123`) | `managing-work-items/SKILL.md` backend detection regex | Edge case 5 | Verify regex pattern in SKILL.md handles this format |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| FR-1 | Backend detection from issue reference format | `managing-work-items/SKILL.md` — detection logic section | Automated test: SKILL.md contains `#N` and `PROJ-123` detection docs | PASS |
| FR-2 | GitHub Issues backend (fetch, comment) | `managing-work-items/SKILL.md` — GitHub operations section | Automated test: SKILL.md contains `gh issue view` and `gh issue comment` | PASS |
| FR-3 | Jira tiered fallback (Rovo MCP → acli → skip) | `managing-work-items/SKILL.md` — Jira backend section | Automated test: SKILL.md contains tiered fallback docs | PASS |
| FR-4 | Fetch operation returns structured data | `managing-work-items/SKILL.md` — fetch operation docs | Code review: verify output fields match spec (title, body, labels, state, assignees) | PASS |
| FR-5 | Comment operations with six type-specific templates | `managing-work-items/SKILL.md` + `references/github-templates.md` + `references/jira-templates.md` | Automated test: all six comment types present in both template files | PASS |
| FR-6 | PR body issue link generation | `managing-work-items/SKILL.md` — PR link section | Automated test: SKILL.md contains `Closes #N` and `PROJ-123` link docs | PASS |
| FR-7 | Issue reference extraction from documents | `managing-work-items/SKILL.md` — extraction section | Automated test: SKILL.md contains `## GitHub Issue` section parsing docs | PASS |
| FR-8 | ADF format for Jira comments | `managing-work-items/references/jira-templates.md` | Automated test: templates contain valid ADF JSON structure | PASS |
| NFR-1 | Graceful degradation (never block workflow) | `managing-work-items/SKILL.md` — degradation section | Code review: verify skip-and-continue behavior documented for all failure modes | PASS |
| NFR-2 | Error handling (command failures, auth errors, MCP failures) | `managing-work-items/SKILL.md` — error handling section | Code review: verify all error categories have remediation messages | PASS |
| NFR-3 | Idempotency (comments safe to retry) | `managing-work-items/SKILL.md` — idempotency section | Code review: verify retry-safety documented | PASS |
| NFR-4 | Template consistency (work item IDs, RC-N tags, equivalent info) | `references/github-templates.md`, `references/jira-templates.md` | Automated test: templates contain traceability markers; manual compare for equivalence | PASS |
| AC: implementing-plan-phases refactored | No inline `gh issue` operations | `implementing-plan-phases/SKILL.md`, `references/step-details.md` | Automated test: no `gh issue comment` in SKILL.md; `github-templates.md` deleted | PASS |
| AC: executing-chores refactored | No inline `gh issue` operations | `executing-chores/SKILL.md`, `references/workflow-details.md` | Automated test: no `gh issue comment` in SKILL.md; `github-templates.md` deleted | PASS |
| AC: executing-bug-fixes refactored | No inline `gh issue` operations | `executing-bug-fixes/SKILL.md`, `references/workflow-details.md` | Automated test: no `gh issue comment` in SKILL.md; `github-templates.md` deleted | PASS |
| AC: documenting-features delegates | Issue fetch delegated to managing-work-items | `documenting-features/SKILL.md` | Automated test: SKILL.md references `managing-work-items` | PASS |
| AC: orchestrator updated | managing-work-items invocation points | `orchestrating-workflows/SKILL.md` | Automated test: SKILL.md references `managing-work-items` for all three chains | PASS |
| AC: all skills validate | `npm run validate` passes | All skill directories | Automated: `npm run validate` | PASS |
| AC: issue reference extraction | Works for both `#N` and `PROJ-123` formats | `managing-work-items/SKILL.md` | Code review: verify both formats documented in extraction section | PASS |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| `managing-work-items` SKILL.md | Phase 1 | `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` | PASS |
| Consolidated GitHub templates | Phase 1 | `plugins/lwndev-sdlc/skills/managing-work-items/references/github-templates.md` | PASS |
| Jira ADF templates (placeholder) | Phase 1 | `plugins/lwndev-sdlc/skills/managing-work-items/references/jira-templates.md` | PASS |
| New test file | Phase 1 | `scripts/__tests__/managing-work-items.test.ts` | PASS |
| Jira ADF templates (complete) | Phase 2 | `plugins/lwndev-sdlc/skills/managing-work-items/references/jira-templates.md` | PASS |
| Updated `managing-work-items/SKILL.md` with Jira backend | Phase 2 | `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` | PASS |
| Updated `managing-work-items.test.ts` with Jira tests | Phase 2 | `scripts/__tests__/managing-work-items.test.ts` | PASS |
| Updated implementing-plan-phases SKILL.md | Phase 3 | `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` | PASS |
| Updated implementing-plan-phases step-details.md | Phase 3 | `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` | PASS |
| Deleted implementing-plan-phases github-templates.md | Phase 3 | `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/github-templates.md` (should NOT exist) | PASS |
| Updated executing-chores SKILL.md | Phase 3 | `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` | PASS |
| Updated executing-chores workflow-details.md | Phase 3 | `plugins/lwndev-sdlc/skills/executing-chores/references/workflow-details.md` | PASS |
| Deleted executing-chores github-templates.md | Phase 3 | `plugins/lwndev-sdlc/skills/executing-chores/references/github-templates.md` (should NOT exist) | PASS |
| Updated executing-bug-fixes SKILL.md | Phase 3 | `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` | PASS |
| Updated executing-bug-fixes workflow-details.md | Phase 3 | `plugins/lwndev-sdlc/skills/executing-bug-fixes/references/workflow-details.md` | PASS |
| Deleted executing-bug-fixes github-templates.md | Phase 3 | `plugins/lwndev-sdlc/skills/executing-bug-fixes/references/github-templates.md` (should NOT exist) | PASS |
| Updated documenting-features SKILL.md | Phase 4 | `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` | PASS |
| Updated documenting-features test | Phase 4 | `scripts/__tests__/documenting-features.test.ts` | PASS |
| Updated orchestrating-workflows SKILL.md | Phase 5 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | PASS |
| Updated orchestrating-workflows test | Phase 5 | `scripts/__tests__/orchestrating-workflows.test.ts` | PASS |
| Updated implementing-plan-phases test | Phase 3 | `scripts/__tests__/implementing-plan-phases.test.ts` | PASS |
| Updated executing-chores test | Phase 3 | `scripts/__tests__/executing-chores.test.ts` | PASS |
| Updated executing-bug-fixes test | Phase 3 | `scripts/__tests__/executing-bug-fixes.test.ts` | PASS |

## Verification Checklist

- [x] All FR-N entries have corresponding Code Path Verification entries (FR-1 through FR-8)
- [x] All NFR-N entries have corresponding Code Path Verification entries (NFR-1 through NFR-4)
- [x] All acceptance criteria mapped to verification entries
- [x] All phase deliverables (Phases 1-5) mapped to Deliverable Verification entries
- [x] Coverage gaps identified with recommendations for items that cannot be automated
- [x] Existing regression test baseline documented (8 test files)
- [x] New test recommendations are actionable and prioritized

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
