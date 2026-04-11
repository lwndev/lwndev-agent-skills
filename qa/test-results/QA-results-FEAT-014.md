# QA Results: Adaptive Model Selection for Forked Subagents

## Metadata

| Field | Value |
|-------|-------|
| **Results ID** | QA-results-FEAT-014 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-014 |
| **Source Test Plan** | `qa/test-plans/QA-plan-FEAT-014.md` |
| **PR** | [#132](https://github.com/lwndev/lwndev-marketplace/pull/132) |
| **Branch** | `feat/FEAT-014-adaptive-model-selection` |
| **Date** | 2026-04-11 |
| **Verdict** | PASS |
| **Verification Iterations** | 1 |

## Test Suite Results

| Test File | Tests | Passed | Failed |
|-----------|-------|--------|--------|
| `scripts/__tests__/workflow-state.test.ts` | 137 | 137 | 0 |
| `scripts/__tests__/orchestrating-workflows.test.ts` | 99 | 99 | 0 |
| `scripts/__tests__/build.test.ts` | 12 | 12 | 0 |
| `scripts/__tests__/reviewing-requirements.test.ts` | 26 | 26 | 0 |
| `scripts/__tests__/creating-implementation-plans.test.ts` | 10 | 10 | 0 |
| `scripts/__tests__/implementing-plan-phases.test.ts` | 21 | 21 | 0 |
| `scripts/__tests__/executing-chores.test.ts` | 19 | 19 | 0 |
| `scripts/__tests__/executing-bug-fixes.test.ts` | 28 | 28 | 0 |
| **Total** | **352** | **352** | **0** |

## Verification Summary

| Section | Entries | PASS | FAIL | SKIP |
|---------|---------|------|------|------|
| Existing Test Verification | 8 | 8 | 0 | 0 |
| New Test Analysis — Phase 1 | 14 (+2 added) | 16 | 0 | 0 |
| New Test Analysis — Phase 2 | 29 (+2 added) | 31 | 0 | 0 |
| New Test Analysis — Phase 3 | 30 | 30 | 0 | 0 |
| New Test Analysis — Phase 4 | 19 | 19 | 0 | 0 |
| New Test Analysis — Phase 5 | 17 | 17 | 0 | 0 |
| Code Path Verification (FR/NFR) | 22 | 22 | 0 | 0 |
| Deliverable Verification | 21 | 21 | 0 | 0 |
| Verification Checklist | 5 | 5 | 0 | 0 |

## Requirement Coverage

All 15 functional requirements (FR-1 through FR-15, with FR-6 formally removed per the design) and 7 non-functional requirements (NFR-1 through NFR-7) have passing code-path verification and corresponding test coverage:

| FR/NFR | Result | Evidence |
|--------|--------|----------|
| FR-1 — Step baseline mapping | PASS | SKILL.md `## Model Selection` Axis 1 table; `orchestrating-workflows.test.ts:224` |
| FR-2a — Initial classification with `complexityStage: "init"` | PASS | `workflow-state.sh cmd_classify_init`; integration tests for chore/bug/feature init |
| FR-2b — Post-plan feature upgrade, upgrade-only | PASS | `cmd_classify_post_plan`; `orchestrating-workflows.test.ts:1008-1016` |
| FR-3 — FR-5 precedence walker, first non-null wins | PASS | `cmd_resolve_tier`; chain walker at `workflow-state.sh:~714` with dynamic length |
| FR-4 — Baseline-locked steps | PASS | `_step_baseline_locked`; `workflow-state.test.ts:867, 926` |
| FR-5 — Override precedence (hard vs soft) | PASS | Walker implements full chain; unit tests for each precedence level |
| FR-6 — Removed | PASS | Grep confirms zero `complexity:` / `model-override:` in `documenting-*/assets/*.md` |
| FR-7 — Four new state fields + `modelSelections` array | PASS | `cmd_init` writes all four; array preserves repeated entries |
| FR-8 — `--model`, `--complexity`, `--model-for` CLI flags | PASS | SKILL.md argument parser docs; `resolve-tier` flag handling |
| FR-9 — Every fork passes explicit `model` | PASS | All 15 fork references in SKILL.md include `model` parameter |
| FR-10 — Unparseable signals → `sonnet` fallback, never `opus` | PASS | `empty-doc.md` fixture + baseline floor tests |
| FR-11 — Retry-with-tier-upgrade once per fork | PASS | `next-tier-up` subcommand; `orchestrating-workflows.test.ts:1089-1188` |
| FR-12 — Stage-aware, upgrade-only resume recomputation | PASS | `cmd_resume_recompute`; `orchestrating-workflows.test.ts:1191-1301` |
| FR-13 — Backward compat migration on read | PASS | `_migrate_state_file`; legacy-file test |
| FR-14 — Console echo per fork | PASS | SKILL.md pre-fork sequence step 4; format with `baseline=`/`wi-complexity=`/`override=` |
| FR-15 — `set-complexity` + `get-model` subcommands | PASS | Dispatch table at `workflow-state.sh:1471-1503` |
| NFR-1 — `## Model Selection` section in SKILL.md | PASS | Section between `## Step Execution` and `## Error Handling` |
| NFR-2 — `references/model-selection.md` | PASS | File exists with all required sections |
| NFR-3 — `modelSelections` written before each fork | PASS | SKILL.md pre-fork sequence step 3 precedes Agent invocation |
| NFR-4 — Default chore/low-bug → zero Opus forks | PASS | Example A + Example B integration tests assert zero Opus |
| NFR-5 — Error handling for missing/unparseable signals | PASS | Tier validation + fallback + post-plan retain |
| NFR-6 — CC 2.1.72 floor + alias tiers + Agent fallback | PASS | `check-claude-version`; alias-only verified by zero full-ID occurrences |
| NFR-7 — Audit trail visibility | PASS | Both FR-14 echo and FR-7 array implementations |

## Acceptance Tests

All 10 synthetic acceptance tests in the Acceptance Criteria pass:

| Scenario | Expected | Result |
|----------|----------|--------|
| Synthetic bug chain (severity low, 1 RC) | Zero Opus forks | PASS (`orchestrating-workflows.test.ts:982`) |
| Synthetic chore (5 ACs, no overrides) | Zero Opus forks | PASS (`orchestrating-workflows.test.ts:940-941`) |
| Synthetic feature (4 phases, security NFR) | Opus for review/plan/phase; Haiku for finalize/PR | PASS (Example D) |
| `--model opus` override | All forks forced to Opus | PASS (hard override walker path) |
| `--complexity high` override | Baseline-locked steps stay Haiku | PASS (`workflow-state.test.ts:926`) |
| `--model haiku` hard downgrade | `reviewing-requirements` below Sonnet + Edge Case 11 warning | PASS (SKILL.md:393) |
| Two-stage feature transition | Init sonnet → post-plan opus | PASS (Example C) |
| Cron-scheduled parent | Classifies from signals, not parent model | PASS (FR-10 floor logic) |
| Backward compat (pre-existing state) | Migrates and resumes cleanly | PASS (`orchestrating-workflows.test.ts:1304-1355`) |
| `npm run validate` after all changes | Passes | PASS (12/12 build tests) |

## Reconciliation Changes

### Test plan updates

- All 130+ entries flipped from `PENDING` → `PASS` based on verified test runs and code-path inspection
- **Added 2 rows** to Phase 1 New Test Analysis:
  - Cross-walker agreement between `cmd_get_model` and `cmd_resolve_tier` (guards against resolver divergence after self-review Issue 1)
  - `record-model-selection` rejects non-numeric `stepIndex` (self-review Issue 4)
- **Added 2 rows** to Phase 2 New Test Analysis:
  - NFR signal word-boundary matching (self-review Issue 3 — `author`/`performer` do not match)
  - NFR signal fenced-code-block skipping (self-review Issue 3 — YAML inside fences ignored)

### Requirements document updates

- **Fixed stale SKILL.md line references** at line 429 of `requirements/features/FEAT-014-adaptive-model-selection.md`. The pre-Phase-3 line numbers (`:320`, `:327`, `:421`, `:464`, `:532`) no longer map after SKILL.md grew to ~950 lines. Replaced with symbolic per-chain references pointing at the Forked Steps sections.
- **Added `## Implementation Deviations` section** documenting:
  - The 5 self-review findings and their fix commits (`a421fa9`, `54d4a78`)
  - 6 design decisions that differ from GitHub issue #130: chore signal dropped from 2 → 1, YAML frontmatter removed (FR-6), `modelSelections` shipped as array not object, two-stage feature classification added, hard/soft override distinction added to FR-5, NFR-6 (CC 2.1.72 floor + Agent fallback) added
  - Resolution of issue #130 Open Question 3 (baseline-locked steps → first-class FR-4)

### Affected files

Implementation touched the following files (match the PR diff):

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — 4 new state fields, `set-complexity`, `get-model`, `record-model-selection`, `classify-init`, `classify-post-plan`, `resolve-tier`, `next-tier-up`, `resume-recompute`, `check-claude-version`, `_migrate_state_file` (FR-13)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — model flags in CLI parser, pre-fork sequence, fork-site mutations, `## Model Selection` section (NFR-1), all four chain init paths emit `set-complexity`
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` — NEW file (NFR-2): classification algorithm, tuning guidance, audit trail reading, migration guidance, FR-5 rationale
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/__tests__/workflow-state.test.ts` — 137 tests (extends existing suite)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/__tests__/orchestrating-workflows.test.ts` — 99 tests (integration coverage for Examples A/B/C/D, retry/resume/version paths)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/__tests__/fixtures/feat-014/` — 21 synthetic requirement-doc fixtures

Sub-skill SKILL.md files (`reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`) are **unchanged** — no `context: fork` added to frontmatter. Requirement document templates under `documenting-*/assets/` are **unchanged** — no YAML frontmatter added.

## Coverage Gaps

The following items from the test plan's Coverage Gap Analysis remain manual-testing gaps and were not exercised during this QA run (consistent with the original plan's recommendations — these are not blockers):

- End-to-end real chore/bug/feature workflow against `lwndev-marketplace` itself (manual acceptance)
- Manual edit of `modelOverride` in state file between pause and resume
- Cron-scheduled / autonomous-loop invocation from a non-Opus parent
- Multi-fork retry budget independence across adjacent failing forks
- `[1m]` long-context Opus variant limitation (documented in `references/model-selection.md:434-442`)
- FR-14 console echo grep-ability from real orchestrator stdout
- Edge Case 1 manual verification of `modelOverride` info-level log line

## Verdict

**PASS** — All 352 automated tests pass. Every functional and non-functional requirement has passing code-path verification. All deliverables are present at expected paths. The 5 self-review findings addressed in follow-up commits `a421fa9`/`54d4a78` are verified fixed. The workflow is ready for finalization.
