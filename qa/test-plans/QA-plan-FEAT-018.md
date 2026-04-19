# QA Test Plan: QA Redesign — Executable Oracle + Adversarial Persona + Independent Planning

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-FEAT-018 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-018 |
| **Source Documents** | `requirements/features/FEAT-018-qa-executable-oracle-redesign.md`, `requirements/implementation/FEAT-018-qa-executable-oracle-redesign.md` |
| **Date Created** | 2026-04-19 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/orchestrating-workflows.test.ts` | Chain-table step sequences, main-context steps, findings-handling step-index mapping, model-selection fixtures | PASS |
| `scripts/__tests__/workflow-state.test.ts` | State-file init, `advance`/`pause`/`resume`, `record-findings`/`record-model-selection`, step generators | PASS |
| `scripts/__tests__/reviewing-requirements.test.ts` | Standalone `reviewing-requirements` skill (standard / test-plan / code-review modes) — **MUST remain unchanged per FR-11 preservation clause** | PASS |
| `scripts/__tests__/executing-qa.test.ts` | `executing-qa` stop-hook behavior (will be rewritten in Phases 3, 5 — old phrase-match tests replaced by new artifact-structure tests) | PASS |
| `scripts/__tests__/documenting-qa.test.ts` | `documenting-qa` Ralph-loop behavior (will be rewritten in Phases 3, 4 — old completeness tests replaced by new plan-artifact tests) | PASS |
| `scripts/__tests__/qa-verifier.test.ts` | `qa-verifier` agent invocations (will be rewritten in Phase 6 — old file-read verification replaced by adversarial coverage checks) | PASS |
| `scripts/__tests__/build.test.ts` | Plugin validation pipeline | PASS |
| `scripts/__tests__/creating-implementation-plans.test.ts` | Implementation plan generation | PASS |
| `scripts/__tests__/implementing-plan-phases.test.ts` | Phase execution | PASS |
| `scripts/__tests__/executing-chores.test.ts` | Chore execution | PASS |
| `scripts/__tests__/executing-bug-fixes.test.ts` | Bug-fix execution | PASS |
| `scripts/__tests__/managing-work-items.test.ts` | Issue-tracker integration | PASS |
| `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | Must have zero diff vs `main` after the full feature (FR-11 preservation, NFR-3) | PASS |
| `qa/test-results/QA-results-*.md` (34 existing v1 artifacts) | Must have zero diff vs `main` — preserved as historical record (FR-10, NFR-3) | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| `capability-discovery.sh` detects vitest when `package.json` has it in dependencies | `scripts/__tests__/capability-discovery.test.ts` (new) | FR-1, Phase 1 | High | PENDING |
| `capability-discovery.sh` detects vitest when `vitest.config.ts` exists | `scripts/__tests__/capability-discovery.test.ts` | FR-1, Phase 1 | High | PENDING |
| `capability-discovery.sh` detects jest by `package.json` dep and by config file | `scripts/__tests__/capability-discovery.test.ts` | FR-1, Phase 1 | High | PENDING |
| `capability-discovery.sh` detects pytest by `pyproject.toml`, `pytest.ini`, and `tests/test_*.py` signals | `scripts/__tests__/capability-discovery.test.ts` | FR-1, Phase 1 | High | PENDING |
| `capability-discovery.sh` detects go test by `go.mod` + `*_test.go` presence | `scripts/__tests__/capability-discovery.test.ts` | FR-1, Phase 1 | High | PENDING |
| `capability-discovery.sh` detects package-manager via `package-lock.json`/`yarn.lock`/`pnpm-lock.yaml` first-match wins | `scripts/__tests__/capability-discovery.test.ts` | FR-1, Phase 1 | Medium | PENDING |
| Multi-framework detection (vitest + jest): first match wins, warning note appended to `notes` array (edge case 1) | `scripts/__tests__/capability-discovery.test.ts` | FR-1, EC1, Phase 1 | High | PENDING |
| Framework detected but no `test` script: falls back to default runner command (edge case 2) | `scripts/__tests__/capability-discovery.test.ts` | FR-1, EC2, Phase 1 | High | PENDING |
| No supported framework detected: report emits `mode: "exploratory-only"`, `framework: null` (FR-3) | `scripts/__tests__/capability-discovery.test.ts` | FR-1, FR-3, Phase 1 | High | PENDING |
| Framework detected but no test directory: default directory is chosen, logged as note (edge case 6) | `scripts/__tests__/capability-discovery.test.ts` | FR-1, EC6, Phase 1 | Medium | PENDING |
| Large repo (>10k files): capability discovery completes quickly — uses manifest-file + bounded glob reads only (edge case 10) | `scripts/__tests__/capability-discovery.test.ts` | EC10, Phase 1 | Medium | PENDING |
| Capability report JSON schema: has `id`, `timestamp`, `mode`, `framework`, `packageManager`, `testCommand`, `language`, `notes[]` | `scripts/__tests__/capability-discovery.test.ts` | FR-1, Phase 1 | High | PENDING |
| `persona-loader.sh` loads `qa.md` successfully when file present | `scripts/__tests__/persona-loader.test.ts` (new) | FR-6, FR-7, Phase 2 | High | PENDING |
| `persona-loader.sh` exports content covering 5 dimensions: Inputs, State transitions, Environment, Dependency failure, Cross-cutting | `scripts/__tests__/persona-loader.test.ts` | FR-6, Phase 2 | High | PENDING |
| `persona-loader.sh` fails with clear error when persona file missing (edge case 8) | `scripts/__tests__/persona-loader.test.ts` | FR-7, NFR-2, EC8, Phase 2 | High | PENDING |
| `persona-loader.sh` fails with clear error when persona file malformed frontmatter | `scripts/__tests__/persona-loader.test.ts` | FR-7, NFR-2, Phase 2 | High | PENDING |
| `persona-loader.sh` finds new persona file under `personas/{name}.md` without code changes | `scripts/__tests__/persona-loader.test.ts` | FR-7, Phase 2 | High | PENDING |
| `qa.md` persona file includes explicit "empty findings is suspicious" directive | `plugins/lwndev-sdlc/skills/documenting-qa/personas/qa.md` (content check) | FR-6, FR-8, Phase 2 | High | PENDING |
| Plan artifact stop-hook validates presence of `---` frontmatter with `version: 2`, `id`, `timestamp`, `persona` | `scripts/__tests__/documenting-qa.test.ts` (rewritten) | FR-8, FR-9, Phase 3 | High | PENDING |
| Plan artifact stop-hook validates `## User Summary`, `## Capability Report`, `## Scenarios (by dimension)` sections | `scripts/__tests__/documenting-qa.test.ts` | FR-8, FR-9, Phase 3 | High | PENDING |
| Plan artifact stop-hook fails when requirements-doc references are detected in `## Scenarios` section (FR-4 no-spec enforcement) | `scripts/__tests__/documenting-qa.test.ts` | FR-4, FR-8, Phase 3 | High | PENDING |
| Plan artifact stop-hook fails when a covered dimension has zero scenarios and no non-applicable justification | `scripts/__tests__/documenting-qa.test.ts` | FR-6, FR-8, EC9, Phase 3 | High | PENDING |
| Plan artifact stop-hook fails when malformed frontmatter (missing version field) | `scripts/__tests__/documenting-qa.test.ts` | FR-8, FR-9, Phase 3 | Medium | PENDING |
| Plan artifact stop-hook succeeds for well-formed version-2 plan | `scripts/__tests__/documenting-qa.test.ts` | FR-8, FR-9, Phase 3 | High | PENDING |
| Plan artifact stop-hook rejects version-1 artifact (legacy format) | `scripts/__tests__/documenting-qa.test.ts` | FR-9, FR-10, Phase 3 | Medium | PENDING |
| Plan artifact stop-hook validates each scenario has priority (P0/P1/P2) and execution mode | `scripts/__tests__/documenting-qa.test.ts` | FR-4, FR-8, Phase 3 | High | PENDING |
| Results artifact stop-hook validates `## Verdict` section contains one of PASS/ISSUES-FOUND/ERROR/EXPLORATORY-ONLY | `scripts/__tests__/executing-qa.test.ts` (rewritten) | FR-8, FR-9, Phase 3 | High | PENDING |
| Results artifact stop-hook validates `## Capability Report`, `## Execution Results`, `## Scenarios Run`, `## Findings`, `## Reconciliation Delta` sections | `scripts/__tests__/executing-qa.test.ts` | FR-8, FR-9, Phase 3 | High | PENDING |
| Results artifact stop-hook: PASS verdict requires `Execution Results` with non-zero `total` + `Exit code: 0` | `scripts/__tests__/executing-qa.test.ts` | FR-2, FR-8, Phase 3 | High | PENDING |
| Results artifact stop-hook: ISSUES-FOUND verdict requires `failed > 0` in Execution Results | `scripts/__tests__/executing-qa.test.ts` | FR-2, FR-8, Phase 3 | High | PENDING |
| Results artifact stop-hook: ERROR verdict requires non-zero exit code with stack traces in artifact | `scripts/__tests__/executing-qa.test.ts` | FR-2, FR-8, Phase 3 | High | PENDING |
| Results artifact stop-hook: EXPLORATORY-ONLY verdict requires `## Exploratory Mode` section with `Reason:` line | `scripts/__tests__/executing-qa.test.ts` | FR-3, FR-8, Phase 3 | High | PENDING |
| Results artifact stop-hook: EXPLORATORY-ONLY verdict requires per-dimension coverage or justification (empty-findings fails) | `scripts/__tests__/executing-qa.test.ts` | FR-3, FR-6, FR-8, EC9, Phase 3 | High | PENDING |
| Results artifact stop-hook rejects "verdict: pass" message with no artifact file | `scripts/__tests__/executing-qa.test.ts` | FR-8, Phase 3 | High | PENDING |
| Results artifact stop-hook detects verdict/counts inconsistency (e.g. PASS with `failed > 0`) | `scripts/__tests__/executing-qa.test.ts` | FR-8, Phase 3 | High | PENDING |
| Results artifact stop-hook rejects malformed frontmatter | `scripts/__tests__/executing-qa.test.ts` | FR-8, FR-9, Phase 3 | Medium | PENDING |
| Results artifact stop-hook still respects `stop_hook_active` bypass (existing convention) | `scripts/__tests__/executing-qa.test.ts` | FR-8, Phase 3, Risk mitigation | Medium | PENDING |
| `documenting-qa/SKILL.md` rewrite: planning prompt explicitly forbids reading `requirements/features/FEAT-*.md`, `requirements/chores/CHORE-*.md`, `requirements/bugs/BUG-*.md` | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` content check | FR-4, Phase 4 | High | PENDING |
| `documenting-qa/SKILL.md` rewrite: prompt derives user summary from PR title/body or User Story section only | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` content check | FR-4, Phase 4 | High | PENDING |
| `documenting-qa/SKILL.md` rewrite: Ralph-loop instruction block removed | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` content check | FR-4, Phase 4 | High | PENDING |
| `documenting-qa/SKILL.md` composes persona overlay by name (`qa` default) via `persona-loader.sh` | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` content check | FR-6, FR-7, Phase 4 | High | PENDING |
| `documenting-qa/SKILL.md` emits version-2 plan artifact at `qa/test-plans/QA-plan-{ID}.md` | `scripts/__tests__/documenting-qa.test.ts` | FR-9, Phase 4 | High | PENDING |
| `documenting-qa/SKILL.md` invokes `capability-discovery.sh` at start of run | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` content check | FR-1, Phase 4 | High | PENDING |
| `executing-qa/SKILL.md` rewrite: write-and-run loop emits tests in detected framework's conventions | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` content check | FR-2, Phase 5 | High | PENDING |
| `executing-qa/SKILL.md` rewrite: ralph/doc-editing reconciliation loop removed | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` content check | FR-2, FR-5, Phase 5 | High | PENDING |
| `executing-qa/SKILL.md` rewrite: reconciliation delta section populated from FR-5 logic | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` content check | FR-5, Phase 5 | High | PENDING |
| `executing-qa/SKILL.md` emits version-2 results artifact at `qa/test-results/QA-results-{ID}.md` | `scripts/__tests__/executing-qa.test.ts` | FR-9, Phase 5 | High | PENDING |
| `executing-qa` runs capability discovery before planning/execution | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` content check | FR-1, Phase 5 | High | PENDING |
| `executing-qa` falls back to `EXPLORATORY-ONLY` when capability report says no framework (FR-3) | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` content check | FR-3, Phase 5 | High | PENDING |
| `executing-qa` surfaces clean branch detection (no diff relative to main) as `ERROR` verdict with reason (edge case 5) | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` content check; `executing-qa.test.ts` | FR-2, EC5, Phase 5 | High | PENDING |
| `executing-qa` test file compilation failure produces `ERROR` verdict with traces, no retry (edge case 3) | `scripts/__tests__/executing-qa.test.ts` | FR-2, NFR-2, EC3, Phase 5 | High | PENDING |
| `executing-qa` handles missing PR gracefully: uses `git diff main...HEAD` + User Story (edge case 4) | `scripts/__tests__/executing-qa.test.ts` | FR-4, EC4, Phase 5 | High | PENDING |
| `executing-qa` handles missing requirements doc: skips reconciliation delta with note (edge case 7) | `scripts/__tests__/executing-qa.test.ts` | FR-5, EC7, Phase 5 | Medium | PENDING |
| `qa-verifier.md` rewrite: checks adversarial dimension coverage (inputs/state/env/deps/cross-cutting), not file-read consistency | `plugins/lwndev-sdlc/agents/qa-verifier.md` content check; `qa-verifier.test.ts` | FR-6, Phase 6 | High | PENDING |
| `qa-reconciliation-agent.md` new: produces bidirectional delta (coverage-surplus / coverage-gap) | `plugins/lwndev-sdlc/agents/qa-reconciliation-agent.md` content check | FR-5, Phase 6 | High | PENDING |
| `qa-verifier.test.ts` updated: fails tests that expect phrase-match PASS verdicts (legacy regime) | `scripts/__tests__/qa-verifier.test.ts` | FR-6, FR-8, Phase 6 | High | PENDING |
| Feature chain table in orchestrating-workflows/SKILL.md has `5+N+4` steps (down from `6+N+4`) | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-11, FR-12, Phase 7 | High | PENDING |
| Chore chain table has 7 steps (down from 8); step 4 "Reconcile test plan" removed | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-11, FR-12, Phase 7 | High | PENDING |
| Bug chain table has 7 steps (down from 8); step 4 "Reconcile test plan" removed | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-11, FR-12, Phase 7 | High | PENDING |
| Main-context-steps label updated: `(Steps 1, 5, 6+N+3)` → `(Steps 1, 4, 5+N+3)` for feature; chore/bug `(Steps 1, 3, 7)` → `(Steps 1, 3, 6)` | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-12, Phase 7 | High | PENDING |
| Fork Step-Name Map: `reviewing-requirements` mode list drops `test-plan` from orchestrator-invoked sites | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-12, Phase 7 | Medium | PENDING |
| Findings Handling scope: updated from `feature steps 2/6; chore/bug steps 2/4` to `feature steps 2; chore/bug steps 2` | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-12, Phase 7 | High | PENDING |
| `workflow-state.sh` step generators (`generate_feature_steps`, `generate_chore_steps`, `generate_bug_steps`) drop `Reconcile test plan` entry | `scripts/__tests__/workflow-state.test.ts` | FR-12, Phase 7 | High | PENDING |
| `populate-phases` indexed-step assertions renumbered: total step count reduced by 1 | `scripts/__tests__/workflow-state.test.ts` | FR-12, Phase 7 | High | PENDING |
| `CLAUDE.md` workflow-chain descriptions drop `reviewing-requirements (test-plan reconciliation)` from all three chains | `CLAUDE.md` content check | FR-12, Phase 7 | High | PENDING |
| Orchestrator main-context calling pattern for `documenting-qa` and `executing-qa` unchanged (NFR-6) | `orchestrating-workflows/SKILL.md` content check (main-context step blocks) | NFR-6, Phase 7 | High | PENDING |
| Fixture integration: `qa-fixture/` repo exists with `vitest` config and `src/add.ts` containing deliberate bug | `scripts/__tests__/fixtures/qa-fixture/` | Phase 8 | High | PENDING |
| Fixture integration: capability discovery detects vitest; test-write simulation produces failing test; exit code non-zero | `scripts/__tests__/qa-integration.test.ts` (new) | FR-1, FR-2, Phase 8 | High | PENDING |
| Fixture integration: empty fixture with no framework produces `mode: "exploratory-only"` | `scripts/__tests__/qa-integration.test.ts` | FR-1, FR-3, Phase 8 | High | PENDING |
| NFR-5 smoke run: real feature branch produces non-PASS verdict; artifact committed as evidence | `qa/test-results/QA-results-{smoke-target-ID}.md` (new, version 2) | NFR-5, Phase 8 | High | PENDING |
| Full `npm test` green after all phases | All test files | Phase 8 | High | PENDING |
| Full `npm run validate` green | All plugin skills | Phase 8, Risk mitigation | High | PENDING |
| Full `npm run lint` green on new/modified scripts | All new/modified `.ts` and `.sh` files | Phase 8, Risk mitigation | Medium | PENDING |
| Final grep-sweep: no `verdict.*pass`, `verification.*complete`, `reconciliation.*complete` as load-bearing patterns in new stop hooks | `plugins/lwndev-sdlc/skills/{documenting-qa,executing-qa}/scripts/stop-hook.sh` | FR-8, Phase 8 | High | PENDING |
| PR description includes links to the requirements doc (`FEAT-018-qa-executable-oracle-redesign.md`), issue #170, #163 (closed), and #169 (bookkeeping, independent) | PR body (manual verification) | AC "PR description references this requirements doc, #170, #163 (closed), and #169" | Low | PENDING |

## Coverage Gap Analysis

Code paths and functionality that lack automated test coverage and require manual or smoke-run verification:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| End-to-end orchestrator invocation with the new skills (main-context vs fork boundaries) | `orchestrating-workflows/SKILL.md` + rewritten `documenting-qa`/`executing-qa` SKILL.mds | NFR-6, Phase 7 | Manual invocation of `/orchestrating-workflows FEAT-{recent}` after all phases complete; verify the feature chain produces artifacts in the right order and pauses correctly. |
| Adversarial persona quality — whether the `qa.md` persona actually surfaces real issues, not just empty adversarial-sounding prose | `plugins/lwndev-sdlc/skills/{documenting-qa,executing-qa}/personas/qa.md` | FR-6 | NFR-5 smoke run is the primary check. If PASS is emitted where ISSUES-FOUND was expected, revise the persona. |
| The stop hook's FR-4 no-spec enforcement (grep for `FR-\d+` in scenarios) may produce false positives if a scenario legitimately mentions FR numbers for traceability in metadata | `documenting-qa/scripts/stop-hook.sh` | FR-4, FR-8, Phase 3 risk | Manual review of fixture test output; add a false-positive regression test case once identified. |
| Backward-compat read of the 34 existing v1 artifacts by a hypothetical future consumer | `qa/test-results/QA-results-*.md` | FR-10, NFR-3 | No consumer today; documented in the Risk Assessment. No automated test gate until a consumer is built. |
| Integration with in-flight workflows pre-dating the FEAT-018 change (existing `.sdlc/workflows/*.json` state files) | `workflow-state.sh` step-generator output vs stored state shape | FR-12, Phase 7 | Manual verification: resume one paused workflow from `.sdlc/workflows/` after Phase 7 merges and confirm it continues without corrupting state. If test-plan reconciliation was the next step, document the edge case. |
| Performance of capability discovery on very large monorepos (>100k files) beyond the 10k floor | `capability-discovery.sh` | EC10, NFR-1 | Spot test on a known large repo; tune `find` depth if >5s observed. |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| FR-1 | Capability discovery scan at start of every `documenting-qa`/`executing-qa` run | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/capability-discovery.sh`; invoked from both SKILL.mds | Unit tests (`capability-discovery.test.ts`), integration test (`qa-integration.test.ts`), smoke run | PENDING |
| FR-2 | Executable oracle writes tests in detected framework; graded on results | `executing-qa/SKILL.md` write-and-run loop; `executing-qa/scripts/stop-hook.sh` artifact validator | Stop-hook unit tests, fixture integration test, smoke run | PENDING |
| FR-3 | `EXPLORATORY-ONLY` fallback for unsupported frameworks | `capability-discovery.sh` (`mode: "exploratory-only"` branch); `executing-qa/SKILL.md` fallback block; stop-hook's `## Exploratory Mode` section check | `no-framework` capability test, `executing-qa` exploratory-mode stop-hook tests, empty-fixture integration test | PENDING |
| FR-4 | No-spec-during-planning — planning prompt forbids reading requirements doc | `documenting-qa/SKILL.md` rewritten planning section; stop-hook grep for `FR-\d+` in Scenarios | SKILL.md content check; stop-hook unit test | PENDING |
| FR-5 | Reconciliation delta (coverage-surplus + coverage-gap) after every `executing-qa` run | `executing-qa/SKILL.md` delta-computation step; `qa-reconciliation-agent.md` if extracted | SKILL.md content check; stop-hook validates `## Reconciliation Delta` section populated; smoke-run artifact check | PENDING |
| FR-6 | Adversarial tester persona covering 5 dimensions | `documenting-qa/personas/qa.md`, `executing-qa/personas/qa.md`; `persona-loader.sh` | Persona-loader unit tests; `qa.md` content check for all 5 dimensions | PENDING |
| FR-7 | Persona-module composition slot (`personas/{name}.md`) | Directory structure; `persona-loader.sh` lookup logic | Persona-loader unit test with new persona file; directory exists check | PENDING |
| FR-8 | Stop-hook rewrite validates artifact structure, not PASS-phrase regex | `documenting-qa/scripts/stop-hook.sh`, `executing-qa/scripts/stop-hook.sh` | 20+ stop-hook unit tests (every verdict shape + malformed variants); Phase 8 grep-sweep | PENDING |
| FR-9 | Structured version-2 artifact format for plan and results | `documenting-qa/assets/test-plan-template-v2.md`, `executing-qa/assets/test-results-template-v2.md`; stop-hook frontmatter validation | Template files committed; stop-hook unit tests for frontmatter schema | PENDING |
| FR-10 | Version-1 artifacts preserved unmodified; version-2 distinguishable via frontmatter | 34 existing `qa/test-results/QA-results-*.md` files | `git diff --stat qa/test-results/` shows zero changes to existing files through all phases until the smoke-run artifact is added in Phase 8 | PENDING |
| FR-11 | Test-plan reconciliation mode decision (Option B: remove from orchestrator, retain standalone) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` unchanged; `orchestrating-workflows/SKILL.md` chain tables updated | Phase 0 decision in plan document; `git diff --stat` shows zero changes to `reviewing-requirements/SKILL.md`; chain-length tests in `orchestrating-workflows.test.ts` | PENDING |
| FR-12 | Orchestrator chain-table update reflecting FR-11 Option B | `orchestrating-workflows/SKILL.md`, its references, step generators, tests, CLAUDE.md | Chain-length assertions; `populate-phases` test; grep-sweep for stale step numbers | PENDING |
| NFR-1 | Portability — no assumption of framework/server/network/UI | `capability-discovery.sh` (discovery-driven); `executing-qa` fallback to exploratory | Unit tests cover no-framework path; no hard-coded framework references outside `capability-discovery.sh` | PENDING |
| NFR-2 | Graceful degradation — every failure produces an artifact | `documenting-qa`/`executing-qa` SKILL.mds failure handling; stop hooks | Unit tests: detection failure → `EXPLORATORY-ONLY`; planning failure → fail state; execution failure → ERROR verdict; missing persona → clear abort | PENDING |
| NFR-3 | Backward compatibility of existing v1 artifacts | 34 existing `qa/test-results/QA-results-*.md` files | `git diff --stat` check (see FR-10) | PENDING |
| NFR-4 | Test coverage: capability, hook, integration round-trip | `scripts/__tests__/` new + updated files | Full `npm test` green; new test file count verifiable (`capability-discovery.test.ts`, `persona-loader.test.ts`, `qa-integration.test.ts`) | PENDING |
| NFR-5 | Smoke-run demonstration of non-PASS verdict | `qa/test-results/QA-results-{smoke-target}.md` (new, version 2) | Committed smoke-run artifact with non-PASS verdict; Phase 8 explicit gate | PENDING |
| NFR-6 | Orchestrator main-context calling pattern unchanged | `orchestrating-workflows/SKILL.md` step 4 (feature `documenting-qa`) and step `5+N+3` (feature `executing-qa`) | SKILL.md content check — main-context step blocks retain same invocation pattern after Phase 7 renumbering | PENDING |

## Deliverable Verification

Phase deliverables from the implementation plan:

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| Plan document with FR-11 Option B decision locked | Phase 0 | `requirements/implementation/FEAT-018-qa-executable-oracle-redesign.md` | PENDING |
| `capability-discovery.sh` | Phase 1 | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/capability-discovery.sh` | PENDING |
| `capability-discovery.test.ts` | Phase 1 | `scripts/__tests__/capability-discovery.test.ts` | PENDING |
| `persona-loader.sh` (documenting-qa) | Phase 2 | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/persona-loader.sh` | PENDING |
| `persona-loader.sh` (executing-qa) | Phase 2 | `plugins/lwndev-sdlc/skills/executing-qa/scripts/persona-loader.sh` | PENDING |
| `qa.md` persona (documenting-qa) | Phase 2 | `plugins/lwndev-sdlc/skills/documenting-qa/personas/qa.md` | PENDING |
| `qa.md` persona (executing-qa) | Phase 2 | `plugins/lwndev-sdlc/skills/executing-qa/personas/qa.md` | PENDING |
| `persona-loader.test.ts` | Phase 2 | `scripts/__tests__/persona-loader.test.ts` | PENDING |
| `test-plan-template-v2.md` | Phase 3 | `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template-v2.md` | PENDING |
| `test-results-template-v2.md` | Phase 3 | `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template-v2.md` | PENDING |
| Rewritten `documenting-qa/scripts/stop-hook.sh` | Phase 3 | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | PENDING |
| Rewritten `executing-qa/scripts/stop-hook.sh` | Phase 3 | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` | PENDING |
| Updated `documenting-qa.test.ts` | Phase 3 | `scripts/__tests__/documenting-qa.test.ts` | PENDING |
| Updated `executing-qa.test.ts` | Phase 3 | `scripts/__tests__/executing-qa.test.ts` | PENDING |
| Rewritten `documenting-qa/SKILL.md` | Phase 4 | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` | PENDING |
| `documenting-qa.test.ts` additional updates for no-spec enforcement | Phase 4 | `scripts/__tests__/documenting-qa.test.ts` | PENDING |
| Rewritten `executing-qa/SKILL.md` | Phase 5 | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | PENDING |
| `executing-qa.test.ts` additional updates for write-and-run + delta | Phase 5 | `scripts/__tests__/executing-qa.test.ts` | PENDING |
| Rewritten `qa-verifier.md` | Phase 6 | `plugins/lwndev-sdlc/agents/qa-verifier.md` | PENDING |
| New `qa-reconciliation-agent.md` | Phase 6 | `plugins/lwndev-sdlc/agents/qa-reconciliation-agent.md` | PENDING |
| Updated `qa-verifier.test.ts` | Phase 6 | `scripts/__tests__/qa-verifier.test.ts` | PENDING |
| Orchestrator chain tables updated | Phase 7 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | PENDING |
| `step-execution-details.md` fork blocks deleted | Phase 7 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` | PENDING |
| `verification-and-relationships.md` updated | Phase 7 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/verification-and-relationships.md` | PENDING |
| `chain-procedures.md` grep-swept | Phase 7 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` | PENDING |
| `workflow-state.sh` step generators updated | Phase 7 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` | PENDING |
| `CLAUDE.md` workflow-chain descriptions updated | Phase 7 | `CLAUDE.md` | PENDING |
| `orchestrating-workflows.test.ts` chain updates | Phase 7 | `scripts/__tests__/orchestrating-workflows.test.ts` | PENDING |
| `workflow-state.test.ts` step-fixture updates | Phase 7 | `scripts/__tests__/workflow-state.test.ts` | PENDING |
| `reviewing-requirements/SKILL.md` unchanged (preservation check) | Phase 7 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | PENDING |
| `qa-fixture/` minimal vitest fixture repo | Phase 8 | `scripts/__tests__/fixtures/qa-fixture/` | PENDING |
| `qa-integration.test.ts` fixture-based integration tests | Phase 8 | `scripts/__tests__/qa-integration.test.ts` | PENDING |
| Full `npm test` green | Phase 8 | — | PENDING |
| Full `npm run validate` green | Phase 8 | — | PENDING |
| Full `npm run lint` green | Phase 8 | — | PENDING |
| Smoke-run evidence artifact (version 2, non-PASS) | Phase 8 | `qa/test-results/QA-results-{smoke-target-ID}.md` | PENDING |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline) — 12 test files + 2 preservation checks captured
- [x] All FR-N / NFR-N / AC entries have corresponding test plan entries — 12 FRs + 6 NFRs + 26 ACs (via Code Path Verification + New Test Analysis)
- [x] Coverage gaps are identified with recommendations — 6 gaps documented with mitigation
- [x] Code paths trace from requirements to implementation — 18 Code Path Verification entries (12 FR + 6 NFR)
- [x] Phase deliverables are accounted for — 36 deliverables from 9 phases tracked in Deliverable Verification
- [x] New test recommendations are actionable and prioritized — priorities assigned; test file + target + ref populated
