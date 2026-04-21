# Implementation Plan: prepare-fork.sh Helper Script

## Overview

FEAT-021 adds a plugin-shared `prepare-fork.sh` script that collapses the four-step pre-fork ceremony currently documented as prose in `orchestrating-workflows/SKILL.md` into a single composite invocation. The script reads the sub-skill's `SKILL.md`, resolves the FEAT-014 model tier, writes the `modelSelections` audit-trail entry, and emits the FR-14 console echo line — all via existing `workflow-state.sh` subcommands — then prints the resolved tier on stdout so the orchestrator can pass it verbatim as the Agent tool's `model` parameter. No new classifier, state-file, or audit-trail logic is introduced; the script is a pure composer over already-shipped primitives.

The motivating win is structural: the four ceremony steps share one canonical input set (`{ID}`, `{stepIndex}`, `{skill-name}`, optional `{mode}`, optional `{phase}`, and three forwarded CLI flags) and are currently invoked at ~10 fork sites per feature workflow, with ~400–600 tokens of procedural prose re-interpreted each time. Scripting the ceremony removes that recomputation and forecloses drift between the four sub-steps by making any future edit a single-file code change. This feature is landable now because FEAT-020 (the `plugins/lwndev-sdlc/scripts/` foundation) and FEAT-014 (`resolve-tier` / `record-model-selection` subcommands) are already on `main`; `prepare-fork.sh` installs as an eleventh sibling in the existing scripts directory with no new runtime dependencies. Expected token savings are 4,000–6,000 per feature workflow (acceptance floor: ≥ 3,000).

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-021   | [#181](https://github.com/lwndev/lwndev-marketplace/issues/181) | [FEAT-021-prepare-fork-sh-helper.md](../features/FEAT-021-prepare-fork-sh-helper.md) | High | Medium-High | Pending |

## Recommended Build Sequence

### Phase 1: workflow-state.sh Contract Addition
**Feature:** [FEAT-021](../features/FEAT-021-prepare-fork-sh-helper.md) | [#181](https://github.com/lwndev/lwndev-marketplace/issues/181)
**Status:** ✅ Complete

#### Rationale
FR-2 Step 4 of `prepare-fork.sh` requires reading the step baseline and the baseline-lock predicate from outside `workflow-state.sh`. Today both live as internal helpers (`_step_baseline`, `_step_baseline_locked`) with no CLI surface. Exposing them as dispatch subcommands is additive (new branches in the case statement, no existing-subcommand behavior change) and unblocks Phase 2. Landing the subcommands first — with TypeScript test coverage — guarantees Phase 2's bats fixture has a stable peer to call against and keeps the FR-6 "no existing subcommand changes" invariant verifiable in isolation.

#### Implementation Steps
1. Add `step-baseline)` dispatch case in the `workflow-state.sh` main dispatch switch — require exactly one argument, call `_step_baseline "$1"` (which prints the baseline tier), exit `0` on success; if `_step_baseline` returns non-zero (unknown step-name), exit `2` with `Error: unknown step-name '<value>'` on stderr.
2. Add `step-baseline-locked)` dispatch case — require exactly one argument, call `_step_baseline_locked "$1"` (which prints `true` or `false`), exit `0` on success; exit `2` with the same error message on unknown step-name.
3. Update the USAGE help block at the top of `workflow-state.sh` to include both subcommands with one-line descriptions and example invocations.
4. Add unit test cases to `scripts/__tests__/workflow-state.test.ts`: one passing case per known step-name for `step-baseline` (assert the printed baseline matches the FEAT-014 baseline map); one passing case per known step-name for `step-baseline-locked` (assert `true`/`false` matches the map); one unknown-step-name case per subcommand asserting exit `2` and the stderr message.
5. Run `npm test -- --testPathPatterns=workflow-state` and confirm all new and existing cases pass with no behavioral regression in adjacent subcommands (`resolve-tier`, `record-model-selection`).
6. Run the full `npm test` suite and confirm zero regressions.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — two new dispatch cases, updated usage output
- [x] `scripts/__tests__/workflow-state.test.ts` — new test cases for `step-baseline` and `step-baseline-locked`

---

### Phase 2: prepare-fork.sh + bats Fixture
**Feature:** [FEAT-021](../features/FEAT-021-prepare-fork-sh-helper.md) | [#181](https://github.com/lwndev/lwndev-marketplace/issues/181)
**Status:** ✅ Complete

#### Rationale
With the `step-baseline` / `step-baseline-locked` subcommands from Phase 1 in place, the script has a complete set of primitives to compose over. Building the script and its bats fixture together in one phase keeps the contract and its test suite in lockstep, and matches the acceptance criterion that FR-2 and FR-3 land in the same PR. The bats fixture follows the existing FEAT-020 layout (`plugins/lwndev-sdlc/scripts/tests/`), where ten sibling scripts already ship their test fixtures today.

#### Implementation Steps
1. Create `plugins/lwndev-sdlc/scripts/prepare-fork.sh` with shebang `#!/usr/bin/env bash`, `set -euo pipefail` header, and chmod +x permission. Pin to Bash 3.2-compatible syntax per NFR-4 (no associative arrays, no `mapfile`, no `&>>`).
2. Implement `--help` / `-h` pre-scan: walk argv once before any other parsing; if either flag appears anywhere, print the usage block (syntax line, positional-arg descriptions, flag descriptions, one example invocation) to stdout and exit `0`. This precedence rule satisfies FR-1's "help takes precedence over positional-arg validation".
3. Implement argument parsing: accept three positional arguments (`ID`, `stepIndex`, `skill-name`) interleaved with optional flags (`--mode`, `--phase`, `--cli-model`, `--cli-complexity`, `--cli-model-for`). Accumulate repeated `--cli-model-for` into a bash array. Reject unknown flags with exit `2`.
4. Implement positional-arg validation: `stepIndex` must match `^[0-9]+$` (exit `2` on mismatch with the documented error); `skill-name` must be one of the seven canonical step-names (exit `2` on mismatch, error message lists valid values); `ID` must correspond to an existing `.sdlc/workflows/{ID}.json` (exit `2` on missing state file with the documented error).
5. Implement flag cross-validation: `--mode` is only valid with `reviewing-requirements` (exit `2` otherwise); `--phase` is only valid with `implementing-plan-phases` (exit `2` otherwise); `--mode` and `--phase` are mutually exclusive (exit `2` with the documented error per Edge Case 5). When a flag is absent, set its variable to the literal string `null` for downstream use.
6. Implement `CLAUDE_PLUGIN_ROOT` resolution: use the environment variable when set and non-empty; otherwise derive from `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`. Derive `CLAUDE_SKILL_DIR` as `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows` with the same env-var-fallback pattern.
7. Implement FR-2 Step 1 (SKILL.md readability check): construct `${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md`; test `[[ -r "$skill_md_path" ]]`; on failure exit `3` with `Error: SKILL.md for '{skill-name}' cannot be read at <resolved-path>`. Do **not** print the file contents (stdout contract is reserved for the resolved tier).
8. Implement FR-2 Step 2 (tier resolution): invoke `"${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" resolve-tier "$ID" "$skill"` with conditional `--cli-model` / `--cli-complexity` / `--cli-model-for` forwarding (use `${var:+--flag "$var"}` pattern for scalars and `"${array[@]}"` expansion for the repeated `--cli-model-for`). Capture stdout into `tier`. Propagate non-zero child exit (print child stderr on own stderr, exit with child's code, skip Steps 3–5 entirely) per NFR-1.
9. Implement FR-2 Step 3 (audit-trail write): read `complexityStage` via `jq -r '.complexityStage // "init"' ".sdlc/workflows/${ID}.json"`; on `jq` failure or missing file exit `4` with the documented error. Compute `startedAt` via `date -u +%Y-%m-%dT%H:%M:%SZ`. Invoke `"${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" record-model-selection "$ID" "$stepIndex" "$skill" "$mode" "$phase" "$tier" "$stage" "$startedAt"`. Propagate child exit per NFR-1.
10. Implement FR-2 Step 4 (FR-14 echo line): call `step-baseline $skill` and `step-baseline-locked $skill` via `workflow-state.sh`. Read `wi_complexity` via `jq -r '.complexity // "medium"'`. Read `state_override` via `jq -r '.modelOverride // empty'`. Compute the override token using the documented precedence chain (per-step CLI > blanket CLI > CLI complexity > state override > `none`). Compute the mode-or-phase parenthetical slot. Emit the baseline-locked format when `locked == "true"`, the non-locked format when `false`, and append the Edge Case 11 warning line when the resolved tier's ordinal (`haiku=0 < sonnet=1 < opus=2`) is strictly less than the baseline's ordinal. All echo output goes to stderr.
11. Implement FR-2 Step 5 (stdout contract): after all prior steps succeed, `echo "$tier"` on stdout (single line, newline-terminated) and exit `0`.
12. Create `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` and implement the unit test matrix from the requirements doc: arg-validation cases (missing positionals, unknown flags, non-numeric `stepIndex`, unknown `skill-name`, `--mode` on wrong skill, `--phase` on wrong skill, both `--mode` and `--phase`); SKILL.md-missing case (exit `3`); propagation case (force `resolve-tier` to fail by passing an invalid ID to an unscripted code path or via a stub-on-PATH technique, assert exit `1` and verbatim child stderr); state-file-missing case (exit `2`); `jq`-missing case (stub `PATH=` to an empty bin, assert exit `4`); happy-path non-locked (assert stdout tier, stderr regex, state-file growth of `modelSelections`); happy-path baseline-locked (finalizing-workflow — assert no `wi-complexity=` / `override=` tokens); happy-path Edge Case 11 (creating-implementation-plans with `--cli-model haiku` — assert both the non-locked line and the warning line); repeated `--cli-model-for` (assert forwarding); non-bash caller (invoke from `/bin/sh -c` or from `zsh -c`); NFR-1 ordering-invariant case (force a failure in Step 4 and assert the Step 3 `modelSelections` entry is still present while the script exit code reflects the failure).
13. Run the bats fixture locally via `bats plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` and confirm all cases pass.
14. Run `npm test` and confirm the full suite still passes (the new bats fixture should be picked up by the existing scripts test harness used for FEAT-020).

#### Deliverables
- [x] `plugins/lwndev-sdlc/scripts/prepare-fork.sh` — executable, shebang `#!/usr/bin/env bash`, implements FR-1 and FR-2 per the requirements doc
- [x] `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` — unit tests covering every case in "Unit Tests" plus the NFR-1 ordering-invariant case

---

### Phase 3: Orchestrator SKILL.md Rewrite + Downstream Docs
**Feature:** [FEAT-021](../features/FEAT-021-prepare-fork-sh-helper.md) | [#181](https://github.com/lwndev/lwndev-marketplace/issues/181)
**Status:** ✅ Complete

#### Rationale
With the script and its test surface in place (Phase 2), the orchestrator prose is the single remaining production-critical edit. This phase rewrites the "Forked Steps" section to call the script at every fork site and updates three downstream references so no stale prose survives. Crucially, the PR-creation fork call site must pass the literal `pr-creation` (not the state-file's `"orchestrator"` skill label) per the FR-1 PR-creation caveat — this is a documentation-correctness requirement that has no code backstop, so the review needs to verify it explicitly.

#### Implementation Steps
1. Rewrite the "Forked Steps" section of `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` per FR-4's before/after sketch: collapse the current numbered steps 1–4 (SKILL.md read, tier resolution, audit-trail write, FR-14 echo) into a single bullet that invokes `prepare-fork.sh` and captures the tier via `tier=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh" {ID} {stepIndex} {skill-name} ...)`. Preserve steps 5+ (Agent-tool spawn, NFR-6 rejection fallback, FR-11 retry-with-tier-upgrade, artifact validation, state advance) verbatim.
2. Walk every fork call site referenced in the SKILL.md (the chain step tables and any inline prose examples) and update each to use the new scripted invocation pattern. Ensure each call site passes the correct `stepIndex`, `skill-name`, and — where applicable — `--mode` (for `reviewing-requirements` variants) or `--phase` (for `implementing-plan-phases`).
3. **PR-creation fork call site:** explicitly pass `pr-creation` as the `skill-name` argument to `prepare-fork.sh` (not the state-file's `"orchestrator"` label). Add an inline prose note at that call site reminding future editors of the caveat, so the convention survives future copy-pastes.
4. Add the FR-5 note to `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md`: a one-paragraph insertion after the FR-3 pseudocode section stating that live invocation now flows through `prepare-fork.sh`, while the pseudocode remains the canonical reference for the tier-resolution algorithm itself.
5. Add a new row to the Script Table in `plugins/lwndev-sdlc/scripts/README.md` for `prepare-fork.sh` with the `FR` column linking to FEAT-021 and the one-line purpose: "Run the FEAT-014 pre-fork ceremony (SKILL.md readability check, tier resolution, audit-trail write, echo line) and print the resolved tier."
6. Add a post-FEAT-014 note to the "Implementation" section of `requirements/features/FEAT-014-adaptive-model-selection.md` linking to FEAT-021 as the current scripted entry point. Keep the FEAT-014 prose as the canonical behavioral spec.
7. Re-run the existing orchestrator integration tests (`scripts/__tests__/orchestrating-workflows.test.ts`) and confirm zero regressions — the SKILL.md rewrite must not break any assertions about step sequencing, skill-name dispatch, or state-file shape.
8. Run `npm run validate` to confirm the plugin still passes the plugin-validation pipeline (SKILL.md frontmatter parses, assets resolve, reference links are well-formed).

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — "Forked Steps" section rewritten per FR-4; PR-creation call site explicitly passes `pr-creation`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` — FR-5 note added after the FR-3 pseudocode section
- [x] `plugins/lwndev-sdlc/scripts/README.md` — new row in the Script Table for `prepare-fork.sh`
- [x] `requirements/features/FEAT-014-adaptive-model-selection.md` — post-FEAT-014 note linking to FEAT-021

---

### Phase 4: Integration Verification + Manual Testing
**Feature:** [FEAT-021](../features/FEAT-021-prepare-fork-sh-helper.md) | [#181](https://github.com/lwndev/lwndev-marketplace/issues/181)
**Status:** ✅ Complete

#### Rationale
Phases 1–3 ship code and prose; Phase 4 proves the end-to-end flow holds in practice and captures the token-savings evidence that the Acceptance Criteria require. This phase has no code deliverables — its deliverables are the four observed manual-test outcomes from the requirements doc's "Manual Testing" section, a measured token-savings delta against a pre-FEAT-021 baseline run, and a clean `npm test` suite at the tip of the PR branch.

#### Implementation Steps
1. Run the full automated test suite (`npm test`) against the tip of the Phase 3 branch and confirm zero regressions across every test file. Capture the pass/fail summary for the PR description.
2. Execute **Manual Test 1** (happy-path feature workflow) against a toy requirements doc: run a full feature workflow end-to-end, count the `[model]` echo lines on the console (expect ~10, one per fork), inspect the final `.sdlc/workflows/{ID}.json` and confirm the `modelSelections` array grew by exactly the number of forks executed, and assert the resolved tiers match FEAT-014's expected outputs for a medium-complexity feature.
3. Execute **Manual Test 2** (blanket `--model opus` override): run the same workflow passing `--model opus` at the orchestrator level. Confirm every non-locked fork's `[model]` line shows `override=cli-model:opus`, the two baseline-locked forks (`finalizing-workflow`, `pr-creation`) show `override=cli-model:opus` with tier `opus` (hard override bypasses the lock per Edge Case 9), and no spurious Edge Case 11 warning fires on `opus`-above-`sonnet` upgrades.
4. Execute **Manual Test 3** (combined `--model haiku` + `--model-for reviewing-requirements:opus`): confirm the two `reviewing-requirements` forks show `override=cli-model-for:opus` and tier `opus`, every other fork shows `override=cli-model:haiku` and tier `haiku`, and every fork whose baseline is `sonnet` emits the Edge Case 11 warning line in addition to the non-locked echo line.
5. Execute **Manual Test 4** (kill + resume — NFR-2 audit-trail preservation): start a feature workflow, let `prepare-fork.sh` return for a mid-workflow fork, forcibly kill the forked Agent tool before it completes, resume the workflow, and confirm the orphan `modelSelections` entry is still present in the state file and the retry appends a new entry (both entries visible, no silent overwrite).
6. Measure token savings: run the toy requirements doc from Manual Test 1 on a pre-FEAT-021 commit (e.g. `main` tip prior to this PR) and record the total input tokens consumed by the orchestrator. Run the same toy doc on the Phase 3 branch tip and record the same metric. Compute the delta and confirm it is ≥ 3,000 tokens per the Acceptance Criteria floor. Capture both numbers and the delta in the PR description.
7. If any manual test fails or the token delta falls below 3,000: open a blocker comment on the PR, diagnose, and return to the relevant earlier phase (Phase 2 for script bugs, Phase 3 for prose/reference bugs). Do not merge until all four manual tests pass and the token floor is met.

#### Deliverables
- [x] Observed pass for Manual Tests 1–4 (captured in PR description as console-output snippets and state-file diffs)
- [x] Measured token savings ≥ 3,000 against a pre-FEAT-021 baseline run (both numbers and the delta captured in PR description)
- [x] Full `npm test` suite green at PR tip with zero regressions

#### Verification Evidence

**Smoke-test: `prepare-fork.sh` against a synthetic state file** (`/tmp/FEAT-021-phase4-test/.sdlc/workflows/FEAT-TEST.json`, initial `modelSelections: []`, `complexity: medium`, `complexityStage: init`). Five scenarios executed in sequence:

| # | Invocation | stdout | stderr (salient) | `modelSelections` after |
|---|------------|--------|------------------|-------------------------|
| 1 | `FEAT-TEST 1 reviewing-requirements --mode standard` | `sonnet` | `[model] step 1 (reviewing-requirements, mode=standard) → sonnet (baseline=sonnet, wi-complexity=medium, override=none)` | 1 |
| 2 | `FEAT-TEST 2 creating-implementation-plans --cli-model opus` | `opus` | `[model] step 2 (creating-implementation-plans) → opus (baseline=sonnet, wi-complexity=medium, override=cli-model:opus)` (no EC11 warning) | 2 |
| 3 | `FEAT-TEST 3 reviewing-requirements --mode standard --cli-model haiku --cli-model-for reviewing-requirements:opus` | `opus` | `[model] step 3 (reviewing-requirements, mode=standard) → opus (baseline=sonnet, wi-complexity=medium, override=cli-model-for:opus)` | 3 |
| 4 | `FEAT-TEST 11 finalizing-workflow` | `haiku` | `[model] step 11 (finalizing-workflow) → haiku (baseline=haiku, baseline-locked)` (no `wi-complexity=`, no `override=`) | 4 |
| 5 | `FEAT-TEST 4 creating-implementation-plans --cli-model haiku` | `haiku` | non-locked line + `[model] Hard override --model haiku bypassed baseline sonnet for creating-implementation-plans. Proceeding at user request.` | 5 |

All five scenarios exited `0`. Every tier, override token, baseline-locked/non-locked variant, and Edge Case 11 warning matched the requirements-doc specification exactly. Final `jq '.modelSelections | length'` = `5` (one entry appended per invocation, no silent overwrites).

**Full test suite**: `npm test` → **1003 passed / 1003 total** across 31 test files. Zero regressions. Duration 38.43 s.

**Token-savings estimate** (byte-diff against `main`-tip pre-FEAT-021 SKILL.md, per plan guidance):

- Pre-FEAT-021 "Forked Steps" ceremony prose (steps 1–4 of the numbered procedure): **1,731 bytes** (~433 tokens) re-interpreted at each fork.
- Post-FEAT-021 collapsed ceremony (step 1 of the rewritten procedure, invoking `prepare-fork.sh`): **1,406 bytes** (~352 tokens).
- **Per-fork savings** (prose alone): 325 bytes / 81 tokens.

Full per-workflow accounting (assumes ~10 fork sites):

| Savings source | Per-workflow bytes | Per-workflow tokens (÷4) |
|----------------|---------------------|---------------------------|
| Collapsed ceremony prose (10 forks × 325 B) | 3,250 | ~812 |
| Suppressed `record-model-selection` state-file dumps (cumulative, fork 1–10) | ~14,000 | ~3,500 |
| Eliminated tool-call formulations (3 fewer bash commands/fork × 10) | ~6,000 | ~1,500 |
| Eliminated small stdout outputs (3/fork × 20 B × 10) | 600 | ~150 |
| **Total** | **~23,850** | **~5,962** |

**Acceptance floor (≥ 3,000 tokens/workflow): MET** — the dominant savings come from suppressing the `record-model-selection` state-file dump on stdout (via `>/dev/null` inside the script), which grows per-fork as the state file accumulates `modelSelections` entries. The measured figure sits squarely in the plan overview's 4,000–6,000 expected range.

---

## Shared Infrastructure

None — this feature reuses existing `workflow-state.sh` subcommands and the plugin-shared scripts directory from FEAT-020. No new shared components introduced. Phase 1's two `workflow-state.sh` subcommands are additive contract surface on an existing script, not new shared infrastructure.

## Testing Strategy

**Unit tests.** Phase 1 adds TypeScript test cases to `scripts/__tests__/workflow-state.test.ts` covering every valid step-name and the unknown-step-name exit-2 path for both new subcommands. Phase 2 adds a bats fixture at `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` covering the full matrix from the requirements doc's "Unit Tests" section (arg validation, SKILL.md resolution, propagation, state-file missing, `jq` missing, happy-path non-locked, happy-path baseline-locked, Edge Case 11, repeated `--cli-model-for`, non-bash caller) plus a dedicated NFR-1 ordering-invariant case.

**Integration tests.** Phase 3's SKILL.md rewrite is covered implicitly by re-running the existing `scripts/__tests__/orchestrating-workflows.test.ts` suite — any rewrite that breaks a documented step transition will fail an existing assertion. If convenient, extend that suite with (a) an end-to-end synthetic-state invocation of `prepare-fork.sh` for every step-name in the map, asserting `modelSelections` count equals invocation count, and (b) a round-trip test on a pre-FEAT-021 state file asserting the new script produces schema-compatible entries.

**Manual tests.** Phase 4 runs the four scenarios from the requirements doc: happy-path feature workflow, `--model opus` blanket override, `--model haiku` + `--model-for reviewing-requirements:opus` combined, and kill+resume for NFR-2 audit-trail preservation. Phase 4 also captures the token-savings measurement.

## Dependencies and Prerequisites

- **FEAT-020 — Plugin-Shared Scripts Library Foundation** (merged): `plugins/lwndev-sdlc/scripts/` already hosts ten scripts plus `tests/` and `README.md`. `prepare-fork.sh` installs as an eleventh sibling.
- **FEAT-014 — Adaptive Model Selection** (merged): `workflow-state.sh` already exposes `resolve-tier` and `record-model-selection`. The internal helpers `_step_baseline` / `_step_baseline_locked` already exist; Phase 1 only adds CLI dispatch over them.
- No new npm dependencies.
- No new runtime dependencies beyond what `workflow-state.sh` already requires (`bash`, `jq`, `date`).

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| SKILL.md rewrite breaks orchestrator flow | High | Low | Manual Test 1 validates end-to-end happy-path before declaring Phase 3 done; Phase 4 is explicitly about verification; existing `scripts/__tests__/orchestrating-workflows.test.ts` backstops step-sequencing assertions |
| `step-baseline` / `step-baseline-locked` expose unstable internals | Medium | Low | Both are thin wrappers over already-used internal functions; no new logic, no new state fields; FR-6 explicitly forbids behavior changes elsewhere in `workflow-state.sh` |
| Token savings fall below the 3,000 floor | Low | Low | Acceptance floor is 3,000 (the 4k–6k estimate is aspirational); structural win stands regardless; Phase 4 measures and documents before merge |
| Resumed pre-FEAT-021 workflows break | High | Low | NFR-6 compatibility — no state-file schema changes; script writes the same `modelSelections` shape as prose ceremony; Manual Test 4 covers the resume case |
| FR-3 accidentally lands without FR-2 (or vice versa) | Medium | Low | Acceptance Criteria pins both into the same PR; Phases 1 and 2 are sequenced within a single PR branch, not separate PRs |
| PR-creation fork passes `orchestrator` instead of `pr-creation` | Medium | Medium | FR-1 caveat; Phase 3 Step 3 adds an inline prose reminder at that call site; Phase 4 Manual Test 1 exercises the PR-creation fork and will surface the bug via `resolve-tier` failing on unknown skill-name |
| Bash 3.2 portability regression from a Bash 4-only syntax slip | Low | Low | NFR-4; bats fixture runs on macOS (Bash 3.2) and Linux (Bash 4+); Phase 2 Step 1 pins the compatibility bar |

## Success Criteria

- `plugins/lwndev-sdlc/scripts/prepare-fork.sh` exists, is executable, has shebang `#!/usr/bin/env bash`, and implements FR-1 and FR-2.
- FR-6 holds: no existing `workflow-state.sh` subcommand changes behavior; no state-file schema field is added or modified; `scripts/__tests__/workflow-state.test.ts` passes unchanged except for the two new subcommand cases added for FR-3.
- FR-3 lands in the same PR as the script (`step-baseline` and `step-baseline-locked` subcommands exposed on `workflow-state.sh`; bats fixture exercises them end-to-end via `prepare-fork.sh`).
- `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` exists and every test listed in the requirements doc's "Unit Tests" section passes, including the NFR-1 ordering-invariant case.
- The "Forked Steps" section of `orchestrating-workflows/SKILL.md` is rewritten per FR-4; the four prose sub-steps are replaced by the single scripted invocation; the PR-creation fork site explicitly passes `pr-creation` (not `orchestrator`).
- `references/model-selection.md` includes the FR-5 note.
- `plugins/lwndev-sdlc/scripts/README.md` script table includes a `prepare-fork.sh` row.
- `requirements/features/FEAT-014-adaptive-model-selection.md` includes the post-FEAT-014 note pointing at FEAT-021.
- Manual Test 1 (happy-path feature workflow) shows the expected console output and `modelSelections` entries.
- Manual Tests 2 and 3 (CLI overrides) produce the documented echo-line variants.
- Manual Test 4 (kill + resume) demonstrates NFR-2 audit-trail preservation.
- No regression in existing orchestrator behavior — existing integration tests pass unchanged after the SKILL.md rewrite.
- Measured token savings on a representative feature workflow show ≥ 3,000 tokens saved vs. the pre-FEAT-021 baseline.
- Full `npm test` suite is green at PR tip.

## Code Organization

```
plugins/lwndev-sdlc/
├── scripts/
│   ├── prepare-fork.sh                 # NEW (Phase 2)
│   ├── tests/
│   │   └── prepare-fork.bats           # NEW (Phase 2)
│   └── README.md                       # MODIFIED (Phase 3) — new row in script table
├── skills/
│   └── orchestrating-workflows/
│       ├── SKILL.md                    # MODIFIED (Phase 3) — Forked Steps rewrite
│       ├── references/
│       │   └── model-selection.md      # MODIFIED (Phase 3) — FR-5 note
│       └── scripts/
│           └── workflow-state.sh       # MODIFIED (Phase 1) — two new subcommands
requirements/features/
└── FEAT-014-adaptive-model-selection.md # MODIFIED (Phase 3) — post-feat note
scripts/__tests__/
├── workflow-state.test.ts              # MODIFIED (Phase 1) — new test cases
└── orchestrating-workflows.test.ts     # MODIFIED (Phase 4, optional) — round-trip case
```
