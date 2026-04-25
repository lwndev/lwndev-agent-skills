---
id: FEAT-029
version: 2
timestamp: 2026-04-25T17:08:00Z
persona: qa
---

## User Summary

FEAT-029 collapses the deterministic prose inside `creating-implementation-plans` into five new shell scripts (plan-skeleton rendering, DAG validation, per-phase complexity scoring, advisory split suggestion, phase-size enforcement). It also redesigns `implementing-plan-phases` model selection so each phase fork resolves its own tier from the scored phase block — mechanical phases run on Haiku, schema/migration or multi-skill phases run on Sonnet/Opus on demand. Splitting a phase for clarity should now distribute work across cheaper forks instead of upgrading the workflow's complexity, replacing the prior `1→low / 2–3→medium / 4+→high` raw-phase-count anti-pattern with a `max`-of-per-phase-tiers post-plan classifier.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs

- [P0] `render-plan-scaffold.sh` with empty FEAT-IDs string `""` exits `2` (not `0`, not crash) | mode: test-framework | expected: bats case asserting exit `2` and no plan file written
- [P0] `render-plan-scaffold.sh` with malformed ID `feat-029` (lowercase) exits `2` with diagnostic on stderr | mode: test-framework | expected: bats case asserting exit `2` and stderr matches the documented format
- [P0] `render-plan-scaffold.sh FEAT-` (prefix only, no number) exits `2` | mode: test-framework | expected: bats case asserting exit `2`
- [P1] `render-plan-scaffold.sh FEAT-029,,FEAT-030` (empty token between commas) exits `2` not silently skipped | mode: test-framework | expected: bats assertion that empty post-split tokens cause exit `2`
- [P1] `render-plan-scaffold.sh "FEAT-029, FEAT-030 ,FEAT-031"` (mixed whitespace around commas) parses identically to `FEAT-029,FEAT-030,FEAT-031` | mode: test-framework | expected: bats assertion identical rendered output
- [P1] `render-plan-scaffold.sh` with 50 comma-separated FEAT-IDs (oversized list) renders without truncation or arg-list-too-long | mode: test-framework | expected: bats assertion that all 50 phase blocks emitted
- [P0] `validate-plan-dag.sh` self-cycle (`Phase 2 Depends on Phase 2`) detected as cycle, exit `1` with stderr listing Phase 2 | mode: test-framework | expected: bats case for single-node cycle
- [P1] `validate-plan-dag.sh` with two `**Depends on:**` lines in same phase block — first one parsed, second silently ignored OR both merged (decide and document) | mode: test-framework | expected: bats case asserting documented behavior
- [P1] `validate-plan-dag.sh` with `**Depends on:** none` (literal "none") treated as no dependencies | mode: test-framework | expected: bats case
- [P1] `validate-plan-dag.sh` with `**Depends on:** Phase  1` (double space) parses Phase 1 | mode: test-framework | expected: bats case
- [P0] `phase-complexity-budget.sh --phase 0` (out-of-range low) exits `2` with diagnostic | mode: test-framework | expected: bats case
- [P0] `phase-complexity-budget.sh --phase 99` on a 3-phase plan (out-of-range high) exits `1` with phase-not-found diagnostic | mode: test-framework | expected: bats case
- [P0] `phase-complexity-budget.sh --phase abc` exits `2` (per spec line 150) | mode: test-framework | expected: bats case
- [P1] `phase-complexity-budget.sh --phase 1.5` exits `2` (non-integer) | mode: test-framework | expected: bats case
- [P0] `phase-complexity-budget.sh --phase -1` exits `2` (negative) | mode: test-framework | expected: bats case
- [P0] Boundary at exactly `STEPS_LOW_MAX=3` returns `haiku`; at exactly `4` returns `sonnet`; at exactly `STEPS_MED_MAX=7` returns `sonnet`; at exactly `8` returns `opus` | mode: test-framework | expected: bats parametric assertions for all four off-by-one boundaries on each axis (steps, deliverables, files)
- [P0] `**ComplexityOverride:** invalid_tier` rejected — exits `2` with diagnostic OR ignored with `[warn]` (decide and document; silent ignore would let typos go unnoticed and is the wrong default) | mode: test-framework | expected: bats case asserting non-zero exit or `[warn]` line
- [P1] `**ComplexityOverride:** HAIKU` (uppercase) — case sensitivity enforced or normalized? (lowercase-only per the budget script's allowed values) | mode: test-framework | expected: bats case asserting documented behavior
- [P1] `**ComplexityOverride:**` with no value (empty after colon) treated as ignored or rejected | mode: test-framework | expected: bats case
- [P1] Two `**ComplexityOverride:**` lines in the same phase block — first wins or last wins (must be deterministic) | mode: test-framework | expected: bats case
- [P0] `**ComplexityOverride:** sonnet` inside a fenced `` ``` `` block ignored; outside fence honored | mode: test-framework | expected: bats case explicitly asserting fence-awareness for override line
- [P0] Heuristic flag substring match is case-insensitive per spec — verify `Schema`, `SCHEMA`, `schema` all match `LOW_FLAGS=("schema" ...)` | mode: test-framework | expected: bats case
- [P1] Heuristic flag substring matches inside fenced code block — should NOT match (fence-aware required) | mode: test-framework | expected: bats case for fenced false-positive avoidance
- [P0] `split-phase-suggest.sh` on a 7-step phase with `Depends on Step 7` annotation on Step 1 (impossible constraint) — exits with diagnostic, not silent infinite loop | mode: test-framework | expected: bats case asserting bounded behavior
- [P1] `split-phase-suggest.sh` on a 100-step phase (very large) — completes in bounded time, returns 3-way split | mode: test-framework | expected: bats timing-bounded assertion
- [P0] `split-phase-suggest.sh` with malformed `Depends on Step <N>` annotations (e.g., `depends on step 4` lowercase, `Depends on step 4`) — does it match? (decide regex case sensitivity) | mode: test-framework | expected: bats case for parser robustness
- [P1] `validate-phase-sizes.sh` on a plan with both an over-budget phase AND its `**ComplexityOverride:** high` clamp on the same phase — clamp wins, exit `0` | mode: test-framework | expected: bats case
- [P0] `validate-phase-sizes.sh` propagates exit `1` from `phase-complexity-budget.sh` (chained-script failure path) | mode: test-framework | expected: bats case asserting exit `1` and stderr surfaces upstream error
- [P0] `resolve-tier ... --phase 1` (no `--plan-file`) exits `2` per the partial-supply rule | mode: test-framework | expected: vitest case in `scripts/__tests__/workflow-state.test.ts`
- [P0] `resolve-tier ... --plan-file <path>` (no `--phase`) exits `2` per the partial-supply rule | mode: test-framework | expected: vitest case
- [P0] `resolve-tier ... --phase 1 --plan-file /nonexistent.md` emits `[warn] resolve-tier: phase-complexity-budget failed for phase 1; falling back to workflow complexity <tier>.` and resolves at workflow `complexity` | mode: test-framework | expected: vitest case asserting stderr line and resolved tier
- [P0] `resolve-tier ... reviewing-requirements --phase 1 --plan-file <path>` (non-phase skill) emits the documented `[info] resolve-tier: --phase ignored for non-phase skill reviewing-requirements` line and resolves at workflow `complexity` | mode: test-framework | expected: vitest case
- [P1] `prepare-fork.sh --phase 1` (no `--plan-file`) exits `2` (mirrors resolve-tier rule) | mode: test-framework | expected: bats case in `prepare-fork.bats`
- [P1] `prepare-fork.sh --phase 1 --plan-file <path>` on a non-`implementing-plan-phases` skill exits `2` per the cross-skill validation rule | mode: test-framework | expected: bats case
- [P0] `classify-post-plan` invoked twice on same workflow — second invocation a no-op (idempotent, does not re-emit upgrade audit line) | mode: test-framework | expected: vitest case asserting persisted state and audit trail unchanged on second call

### State transitions

- [P0] `render-plan-scaffold.sh` target file already exists — exits `2`, refuses to overwrite (preserves prior plan) | mode: test-framework | expected: bats case asserting exit `2` and original file untouched
- [P1] `render-plan-scaffold.sh` killed (SIGTERM) mid-write — leaves a partial file at target path? Atomic-write to temp + rename pattern required to avoid partial rendering being mistaken for a real plan | mode: exploratory | expected: kill -9 mid-execution and verify either no file exists or full rendered plan exists; never partial
- [P0] Two `implementing-plan-phases` forks for phases 1 and 2 of same workflow racing on `record-model-selection` write — both per-phase entries persist, neither lost (silent in-place migration with concurrent writers) | mode: test-framework | expected: vitest case forking two writes in parallel and asserting final JSON has both `[step-N][phase-1]` and `[step-N][phase-2]` keys
- [P0] `classify-post-plan` upgrade-only invariant: init `complexity: high`, plan with all-`haiku` phases — persisted `complexity` stays `high`, NO upgrade audit line emitted | mode: test-framework | expected: vitest case explicitly asserting no audit line when `max < persisted`
- [P0] `classify-post-plan` happy upgrade: init `complexity: low`, plan with one `opus`-scoring phase — persists `high`/`opus`, audit line emitted | mode: test-framework | expected: vitest case asserting upgrade audit line content
- [P1] Plan file modified between `validate-plan-dag.sh` and `phase-complexity-budget.sh` runs (e.g., model edits during planning loop) — both scripts re-read on every invocation, no caching pitfall | mode: exploratory | expected: manual mid-loop edit and re-run, confirm fresh data
- [P0] Mid-flight workflow state with the lowered-baseline transition — workflow paused with `modelSelections` recorded against old `sonnet` baseline, resumed after the lower baseline ships → next phase fork resolves at new `haiku` baseline. Audit trail must show the transition; resume must not crash | mode: exploratory | expected: paused workflow + version bump + resume; assert audit trail integrity
- [P1] `record-model-selection` persists per-phase keying for the first call AND legacy non-phase calls (e.g., reviewing-requirements) coexist in the same `modelSelections[step-N]` object without collision | mode: test-framework | expected: vitest case asserting both shapes coexist
- [P1] `--enforce-phase-budget` flag during Phase 1 (warn-only) emits `[warn] --enforce-phase-budget will activate ...` once; Phase 3 removes the placeholder line entirely (no double-emission, no zombie warn) | mode: test-framework | expected: bats case in Phase 3's render-plan-scaffold.bats extension asserting absence of placeholder

### Environment

- [P0] `jq` not on PATH — `phase-complexity-budget.sh` and `split-phase-suggest.sh` fall back to pure-bash JSON emission per FEAT-027 / FEAT-021 fallback pattern. Output schema identical to jq path | mode: test-framework | expected: bats case stubbing PATH to exclude jq, asserting JSON output structure unchanged
- [P0] Bash 3.2 (macOS default) — every new script runs without `local -n`, `declare -A`, `mapfile`, `${var^^}`, or other Bash 4+ syntax. Scripts fail-fast on Bash <3.2 should they encounter older shells | mode: exploratory | expected: shellcheck `--shell=bash --severity=warning` plus targeted bats run under `bash -3.2` mode (or actual `/bin/bash` on macOS untouched)
- [P1] `$CLAUDE_PLUGIN_ROOT` unset — scripts that reference it fail with clear diagnostic, not silent path errors | mode: test-framework | expected: bats case unsetting the variable, asserting documented error
- [P1] `$CLAUDE_PLUGIN_ROOT` contains spaces (`/Users/me/My Plugins/...`) — every script invocation uses proper quoting; `phase-complexity-budget.sh` invocation from `validate-phase-sizes.sh` and `resolve-tier` survives | mode: test-framework | expected: bats fixture rooted in a path containing spaces
- [P1] Plan file path with spaces (`requirements/implementation/FEAT-029 (draft).md`) — `validate-plan-dag.sh` and friends handle the quoting | mode: test-framework | expected: bats fixture
- [P1] Plan file with CRLF line endings (Windows checkout) — heading scanner and fence tracker still recognize `### Phase 1: ...\r\n` and ```` ```\r\n ```` | mode: test-framework | expected: bats case with explicit CRLF fixture
- [P2] Plan file with UTF-8 BOM marker — first heading still recognized | mode: test-framework | expected: bats case
- [P2] Plan file with non-ASCII characters in phase name (`Phase 2: Sürf`) — heading scanner does not break, name extraction preserves bytes | mode: test-framework | expected: bats case
- [P1] Read-only filesystem when `render-plan-scaffold.sh` writes target — exits `1` with I/O error, no partial file | mode: exploratory | expected: chmod the target dir read-only and run; verify exit `1` and clean state
- [P2] Plan file > 1MB — `phase-complexity-budget.sh` completes within reasonable bound, no quadratic blowup in fence-tracker | mode: exploratory | expected: synthetic 1MB plan, time the run, assert under 10s on dev hardware
- [P1] Working directory permission-denied for `qa/test-plans/` parent — `documenting-qa` skill graceful failure (out of scope for FEAT-029 scripts but verify nothing in FEAT-029 cascades the failure) | mode: exploratory | expected: manual run with chmod 555
- [P2] Locale-sensitive sort (`LC_ALL=tr_TR.UTF-8`) — `unique` of tiers (`haiku`, `sonnet`, `opus`) and `max`-ordering not affected by Turkish dotless-I or other locale-quirky sorts | mode: exploratory | expected: re-run `classify-post-plan` under `LC_ALL=tr_TR.UTF-8`

### Dependency failure

- [P0] `phase-complexity-budget.sh` non-zero exit during `resolve-tier` (Edge Case 9) — `[warn] resolve-tier: phase-complexity-budget failed for phase <N>; falling back to workflow complexity <tier>.` line emitted; fork still runs at workflow tier | mode: test-framework | expected: vitest case stubbing the script to exit `1`
- [P0] `phase-complexity-budget.sh` non-zero exit during `classify-post-plan` (Edge Case 9 symmetric) — `[warn] classify-post-plan: phase-complexity-budget failed; preserving init-stage complexity <tier>.` emitted; persisted complexity unchanged; exit `0` | mode: test-framework | expected: vitest case
- [P0] `phase-complexity-budget.sh` outputs malformed JSON (e.g., truncated mid-array) — `resolve-tier` and `classify-post-plan` callers detect and fall back gracefully, do NOT crash with `jq: parse error` propagated as exit `1` | mode: test-framework | expected: bats/vitest case stubbing the script to emit truncated JSON
- [P0] `resolve-requirement-doc.sh` non-zero exit (e.g., FEAT-029 references a non-existent FEAT-XXX in multi-feature mode) — `render-plan-scaffold.sh` exits `1` with upstream stderr surfaced verbatim | mode: test-framework | expected: bats case
- [P1] `prepare-fork.sh` forwarding loses flag value due to quoting bug — phase 1 fork resolves with empty `--phase` argv, fall back path triggered. Verify the `${var:+--flag "$var"}` quoting is correct | mode: test-framework | expected: bats case asserting exact argv passed to internal `resolve-tier` call (e.g., via wrapper stub)
- [P1] `validate-phase-sizes.sh` invokes `phase-complexity-budget.sh` which crashes — exit `1` propagates with upstream stderr; orchestrator's `--enforce-phase-budget` gate halts plan rendering correctly | mode: test-framework | expected: bats case
- [P1] `classify-post-plan` parses `phase-complexity-budget.sh` JSON via `jq -r '[.[].tier] | unique'` — fallback when jq missing must produce identical sort/dedupe semantics | mode: test-framework | expected: bats case under no-jq environment
- [P1] Backwards compat: pre-existing state file (no per-phase keying under `modelSelections`) loaded by the new `record-model-selection` — write succeeds without crashing on missing nested object; existing entries untouched | mode: test-framework | expected: vitest case fixturing an old-shape state file then writing a per-phase entry
- [P1] Backwards compat: pre-existing plan file (no `**ComplexityOverride:**` lines, no `**Depends on:**` lines on every phase) — `validate-plan-dag.sh` returns `ok`; `phase-complexity-budget.sh` scores all phases without crashing on missing override | mode: test-framework | expected: bats case using a real older plan from `requirements/implementation/`
- [P2] `gh` CLI absent or unauthenticated — `documenting-qa` PR-first path fails; falls back to User Story (out of scope for FEAT-029 directly but adjacent: verify FEAT-029 scripts do not introduce new `gh` dependencies) | mode: exploratory | expected: manual `unset GH_TOKEN; PATH-stub gh` run

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] **Concurrency: per-phase `record-model-selection` writers race** — three phase forks spawned in parallel (phases 1, 2, 3) each write `modelSelections[step-N][phase-K]`. Final state must contain all three entries; no lost-write. (jq-based read-modify-write without flock is the obvious bug surface.) | mode: test-framework | expected: vitest case forking 3 parallel writes; assert all keys present
- [P0] **Audit-trail completeness**: every fork (including post-lowered-baseline Haiku forks) appears in `modelSelections` with non-null `tier` and `complexityStage`. No silent skip on the lower baseline | mode: test-framework | expected: vitest case asserting `modelSelections.length == expected fork count` after a synthetic workflow
- [P0] **`max`-of-per-phase semantics**: plan with `[haiku, haiku, opus]` → workflow post-plan `complexity = high`. Plan with `[haiku, haiku, haiku]` after init `low` → workflow stays `low` (no spurious upgrade). Plan with `[sonnet]` (single phase) → workflow `medium` (no longer auto-promoted to `low` by raw count) | mode: test-framework | expected: vitest cases for each combination
- [P0] **Edge Case 8 fix verification**: a 3-phase plan that splits Phase 2 into two separate phases (now 4 phases) — under raw-count mapping the workflow would jump `medium → high`; under FEAT-029 `max` semantics the workflow tier must NOT change because per-phase tiers are unchanged | mode: test-framework | expected: vitest case constructing 3-phase plan, scoring it, then constructing the equivalent 4-phase plan with same per-phase tiers, asserting `classify-post-plan` returns identical workflow `complexity`
- [P1] **`**ComplexityOverride:** opus` on every phase**: `max` returns `opus` → workflow forced to `high` even when signals score `haiku`. Verify the override clamp survives the post-plan `max` aggregation | mode: test-framework | expected: vitest case
- [P1] **Plan with 0 phases** (rendered scaffold before any phase content): `phase-complexity-budget.sh` exits `1` per spec; `classify-post-plan` triggers Edge Case 9 fallback, preserves init complexity. Validate the fallback path here, not just on script failure | mode: test-framework | expected: vitest case
- [P1] **Plan with 1 phase that scores `opus`**: under raw mapping this was `low` (1 phase = low). Under FEAT-029 it correctly resolves to `high`. Confirm the migration produces the documented behavior change | mode: test-framework | expected: vitest case
- [P0] **Baseline-downgrade safety**: workflows in flight before the lower baseline ships have `modelSelections[step-implementing-plan-phases].tier = sonnet`. After the lower baseline ships, the same workflow's next phase fork resolves at `haiku`. Audit trail must show both tiers — no silent overwrite of historical entries | mode: test-framework | expected: vitest case asserting append-only audit semantics
- [P0] **Hard `--model opus` override on a workflow with the lowered baseline**: hard override still wins per the override-chain (Axis 3) — every phase fork resolves to `opus` regardless of per-phase tier. Verify per-phase resolution does not accidentally bypass the override chain | mode: test-framework | expected: vitest case asserting `--model opus` beats per-phase `haiku`
- [P0] **Soft `--complexity high` (CLI) on a workflow whose per-phase classifier returns `haiku` for every phase**: `--complexity` is upgrade-only on workflow complexity but per-phase resolution uses the per-phase tier as the Axis 2 input. Confirm the CLI soft-floor is honored as the Axis-2 floor for each per-phase resolution (or document if it only applies to non-phase forks) | mode: test-framework | expected: vitest case asserting documented behavior
- [P1] **Permissions: `.sdlc/workflows/{ID}.json` written with overly-permissive mode** — verify `record-model-selection` does not chmod 0666; preserves whatever the file's existing mode was (no information disclosure regression) | mode: exploratory | expected: stat the file before/after a per-phase write
- [P2] **i18n: phase name with non-ASCII** (`### Phase 1: 日本語のフェーズ`) renders correctly in `render-plan-scaffold.sh` and is preserved in subsequent fixtures | mode: test-framework | expected: bats case
- [P2] **Plan with deeply-nested fenced blocks** (` ``` ` inside `~~~`, or vice-versa) — fence tracker correctly identifies "outside fence" vs "inside fence" for `**Depends on:**` and `**ComplexityOverride:**` extraction. Documented behavior is "first fence opens, matching close required"; verify | mode: test-framework | expected: bats case for nested fence scenarios

## Non-applicable dimensions

- a11y (visual / screen reader): FEAT-029 ships shell scripts and JSON output consumed by other shell scripts and the orchestrator. There is no UI surface, no rendered HTML, no terminal cursor positioning beyond plain `printf`. Standard a11y dimensions (keyboard nav, focus trap, contrast) do not apply. The orchestrator's downstream prose output is governed by its own a11y posture, not FEAT-029.
- Authn / authz: FEAT-029 scripts read local files in the consumer repo and write to local state files. No network, no credential handling, no session lifecycle. Permission concerns reduce to standard filesystem permissions, covered under Cross-cutting.
- Network failure modes (offline / slow / flaky / 5xx): FEAT-029 scripts are pure-local. The only external dependency surface is `gh` for the `documenting-qa` PR-first path, which is upstream of FEAT-029 and not in scope.
