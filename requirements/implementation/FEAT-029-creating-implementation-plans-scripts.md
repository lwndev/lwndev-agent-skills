# Implementation Plan: creating-implementation-plans Scripts + Per-Phase Tier Reduction

## Overview

FEAT-029 collapses the deterministic prose inside `creating-implementation-plans` into five skill-scoped shell scripts (FR-1 through FR-5: plan-skeleton rendering, DAG validation, per-phase complexity scoring, advisory split suggestion, phase-size enforcement) and couples that move-to-scripts work with a per-phase model-selection redesign (FR-6 through FR-10: per-phase aware `resolve-tier`, lowered `implementing-plan-phases` baseline, threaded `--phase`/`--plan-file` through `prepare-fork.sh`, `max`-of-per-phase-tiers post-plan classifier, and a rewritten `references/model-selection.md`). Two compounding savings levers: ~550–750 tok per plan creation from prose-to-script, plus an order-of-magnitude reduction on `implementing-plan-phases` fork costs once mechanical phases resolve to Haiku and Sonnet/Opus is reserved for genuinely complex phases.

The build sequence rolls out in three stages of increasing risk: plan-time scripts first (FR-1, FR-2, FR-3, FR-5) shipped together with `validate-phase-sizes.sh` running as a warn-only gate inside `render-plan-scaffold.sh`'s opt-in `--enforce-phase-budget` flag; the advisory `split-phase-suggest.sh` (FR-4) packaged alongside; then the tier-resolution amendments (FR-6, FR-7, FR-8, FR-9) which flip the gate to error and engage per-phase classification end-to-end; finally the documentation rewrite (FR-10) and SKILL.md lean-down (NFR-4 / NFR-6). The plan is self-bootstrapping: the very last phase that wires FR-9 can score itself against the FR-3 budget table — a deliberate canary that demonstrates per-phase tier reduction in production on its own implementation.

Per-phase complexity discipline applies to this plan itself. Each phase aims for ≤7 implementation steps, ≤9 deliverables, and ≤8 distinct file paths. Mixed phases ("scripts + tests + docs + state-file migration") are split until each unit is reviewable and testable in isolation. The `**ComplexityOverride:**` per-phase line is **not** part of the current plan template and is not used here — it becomes part of the format only after FR-3 ships.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-029 | [#190](https://github.com/lwndev/lwndev-marketplace/issues/190) | [FEAT-029-creating-implementation-plans-scripts.md](../features/FEAT-029-creating-implementation-plans-scripts.md) | High | Medium-High | Pending |

## Recommended Build Sequence

### Phase 1: Directory Scaffold + `render-plan-scaffold.sh` (FR-1)

**Feature:** [FEAT-029](../features/FEAT-029-creating-implementation-plans-scripts.md) | [#190](https://github.com/lwndev/lwndev-marketplace/issues/190)
**Status:** ✅ Complete

#### Rationale

Phase 1 establishes the `creating-implementation-plans/scripts/` directory (the skill currently has no skill-scoped scripts), the `scripts/tests/` and `scripts/tests/fixtures/` siblings, and the bats-coverage convention inherited verbatim from FEAT-026 / FEAT-027. Landing FR-1 first is correct for three reasons: (1) it is the user-facing entry point for plan authoring and exercises the upstream `resolve-requirement-doc.sh` integration path that every subsequent phase depends on for fixture construction, (2) the `--enforce-phase-budget` flag is wired but warn-only at this stage (no FR-5 dependency yet — the flag is documented as a no-op until Phase 3 ships `validate-phase-sizes.sh`), and (3) the rendered scaffold output is the canonical fixture shape that Phases 2 and 3's bats fixtures parse. Establishing the fixture once here means Phases 2/3 can extend rather than re-derive.

The `--enforce-phase-budget` flag is implemented as a parsed-but-deferred no-op in Phase 1 (emit a `[warn] --enforce-phase-budget will activate once validate-phase-sizes.sh ships in Phase 3` line on stderr; do not exit non-zero). Phase 3 wires the actual gate.

#### Implementation Steps

1. Create the new directories: `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/`, `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/`, and `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/`.

2. Write `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/render-plan-scaffold.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`; pin to Bash 3.2-compatible syntax.
   - Top-of-file comment block: purpose, signature `render-plan-scaffold.sh <FEAT-IDs> [--enforce-phase-budget]`, exit codes (`0` success / `1` upstream resolver or I/O failure / `2` missing args, malformed `FEAT-IDs`, or target file already exists), and a note that `--enforce-phase-budget` is a no-op until Phase 3.
   - Parse `<FEAT-IDs>` as a comma-separated list (tolerate whitespace around commas). Empty list → exit `2`. Each ID must match `^FEAT-[0-9]+$` → exit `2` on mismatch.
   - Resolve every ID via `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh "<FEAT-NNN>"`. Surface upstream stderr verbatim and exit `1` on any unresolved ID.
   - For each resolved feature doc, extract: name (from `# Feature Requirements:` heading), priority (from `## Priority` section), and the ordered list of `### FR-N` blocks.
   - Render the plan skeleton from the template at `${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/assets/implementation-plan.md`: substitute the title with `# Implementation Plan: <Primary Feature Name>`; emit one Features Summary row per ID (`Complexity` defaults to `TBD`, `Status` defaults to `Pending`); emit one `### Phase N: <placeholder>` block per FR with `**Status:** Pending`, a `**Depends on:**` placeholder line, an `#### Implementation Steps` placeholder list, and an `#### Deliverables` placeholder list.
   - Write the rendered plan to `requirements/implementation/<primary-FEAT-ID>-<slug>.md`. Slug derived from the primary feature doc's filename suffix (everything after the `FEAT-NNN-` prefix). Refuse to overwrite — exit `2` if the target exists.
   - Emit the absolute path on stdout. Exit `0`.
   - `--enforce-phase-budget` parsed but warn-only this phase: emit `[warn] --enforce-phase-budget will activate once validate-phase-sizes.sh ships (FEAT-029 Phase 3).` to stderr; do not exit non-zero.
   - `chmod +x`.

3. Create `scripts/tests/fixtures/feat-fixture-single.md` — a synthetic feature doc with three FRs used as the resolver target by happy-path tests. Place it under the fixtures directory and have the bats setup symlink or copy it into a temporary `requirements/features/` shape that mimics the resolver's expectations.

4. Create `scripts/tests/fixtures/feat-fixture-multi-a.md` and `scripts/tests/fixtures/feat-fixture-multi-b.md` — two synthetic feature docs with two FRs each, used by the multi-feature happy-path test.

5. Write `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/render-plan-scaffold.bats`:
   - Follow the PATH-shadowing fixture pattern from `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` (per-test `setup()` builds `FIXTURE_DIR="$(mktemp -d)"`, places the fixture feature docs under `${FIXTURE_DIR}/requirements/features/`, runs the script with `cd "${FIXTURE_DIR}"`, asserts on stdout/stderr/file-system state, `teardown()` deletes `FIXTURE_DIR`).
   - Happy-path single feature: stdout is the absolute target path; the rendered file exists and contains the expected title, one Features Summary row, three `### Phase N` blocks (one per FR), and `**Status:** Pending` lines.
   - Happy-path multi-feature (`FEAT-XXX,FEAT-YYY`): two summary rows, four phase blocks (two per source feature in document order), title uses the primary feature's name.
   - Whitespace tolerance: `FEAT-XXX, FEAT-YYY` (with space after comma) parses identically.
   - `--enforce-phase-budget` warn-only this phase: stderr contains the documented `[warn]` line, exit `0`.
   - Error path: missing arg → exit `2`; malformed `FEAT-IDs` (e.g., `feat-029`, `FEAT-`, empty string after split) → exit `2`; target file already exists → exit `2`; resolver failure (non-existent FEAT-ID) → exit `1` with resolver stderr surfaced.

6. Run the bats fixture locally (`bats plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/render-plan-scaffold.bats`) and confirm all cases pass.

7. Run `npm test -- --testPathPatterns=creating-implementation-plans | tail -50` and `npm run validate` to confirm zero regressions.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/` (directory)
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/` (directory)
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/` (directory)
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/render-plan-scaffold.sh`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/feat-fixture-single.md`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/feat-fixture-multi-a.md`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/feat-fixture-multi-b.md`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/render-plan-scaffold.bats`

---

### Phase 2: DAG Validation + Per-Phase Complexity Scoring (FR-2, FR-3)

**Feature:** [FEAT-029](../features/FEAT-029-creating-implementation-plans-scripts.md) | [#190](https://github.com/lwndev/lwndev-marketplace/issues/190)
**Status:** ✅ Complete
**Depends on:** Phase 1

#### Rationale

`validate-plan-dag.sh` (FR-2) and `phase-complexity-budget.sh` (FR-3) share two load-bearing primitives: (1) the `### Phase N: <name>` block-boundary scanner (heading → next heading or EOF), and (2) the fence-aware line filter (skip lines inside ```` ``` ```` / ```` ~~~ ```` blocks). Implementing both scripts in one phase amortises the parsing investment and ensures the fence-tracking pattern is verified once and reused with confidence. FEAT-027 Phase 1 established the same pattern for `**Status:**` lines; FEAT-029 Phase 2 establishes it for `**Depends on:**` lines (FR-2) and for signal-extraction (FR-3 implementation-step counts, deliverable counts, backticked-path extraction, heuristic-flag substring scans).

FR-3 is the engine for everything downstream: FR-5 invokes it as a gate, FR-6 invokes it for per-phase tier resolution at fork time, and FR-9 invokes it in the post-plan classifier. Landing it here — with full bats coverage of every signal threshold, every heuristic flag, the override clamp, and the `overBudget` flag — means subsequent phases have a stable, tested oracle to call against.

The phase deliberately excludes FR-4 (`split-phase-suggest.sh`) and FR-5 (`validate-phase-sizes.sh`) to keep the unit reviewable. FR-5 composes FR-3 trivially and ships in Phase 3 with FR-4.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/validate-plan-dag.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`; Bash 3.2-compatible.
   - Top-of-file comment block: purpose, signature `validate-plan-dag.sh <plan-file>`, exit codes (`0` ok / `1` cycle, unresolved reference, or I/O error / `2` missing arg).
   - Scan the plan for every `### Phase <N>: <name>` heading. For each block, walk lines until the next `### Phase` heading or EOF; track fence state (toggle on lines starting with ```` ``` ```` or `~~~`); extract the first `**Depends on:**` line outside fences. Permitted forms: `Phase 1`, `Phase 1, Phase 3`, `none`, or omission. Tokens that don't match `Phase <N>` (e.g., `PR #123`) are ignored — free-text rationale lines coexist with the strict parser.
   - Build the dependency graph in memory. Run two checks:
     - **Reference resolution**: every `Phase <N>` token must reference a phase that exists in the plan. On unresolved → stderr `error: phase <X> depends on non-existent phase <Y>`, exit `1`.
     - **Cycle detection**: Kahn's algorithm topological sort. On cycle → stderr `error: cycle detected involving phases <list>`, exit `1`. The list must include every phase in the cycle (NFR-2 requirement) so the model can author the fix in one pass.
   - On success: stdout `ok`, exit `0`.
   - `chmod +x`.

2. Write `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/phase-complexity-budget.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`; Bash 3.2-compatible.
   - Top-of-file comment block: purpose, signature `phase-complexity-budget.sh <plan-file> [--phase N]`, exit codes (`0` success / `1` plan I/O error or no `### Phase` blocks / `2` missing arg or malformed `--phase`), and the per-phase budget table verbatim from FR-3 (so future tuning happens in one place).
   - Define the budget thresholds at the top of the script as named variables: `STEPS_LOW_MAX=3`, `STEPS_MED_MAX=7`, `DELIVERABLES_LOW_MAX=4`, `DELIVERABLES_MED_MAX=9`, `FILES_LOW_MAX=3`, `FILES_MED_MAX=8`, plus arrays for `LOW_FLAGS=("schema" "migration" "test infra")` and `HIGH_FLAGS=("public api" "security" "multi-skill refactor")`.
   - Reuse the block scanner and fence tracker from `validate-plan-dag.sh` (factor a small helper sourced inline, OR copy-and-test — choose the simpler path; do not over-engineer a shared library for two callers).
   - For each phase block (or only `--phase N` when supplied):
     - Count `^[0-9]+\.` lines inside the `#### Implementation Steps` subsection.
     - Count `- \[[ x]\]` lines inside the `#### Deliverables` subsection.
     - Extract unique backticked paths from deliverable lines (pattern `` `<path>` ``).
     - Substring-scan the entire phase block (case-insensitive) for low-tier flags and high-tier flags. Track which flags matched.
     - Map each signal to a tier independently: `≤STEPS_LOW_MAX → haiku`, `≤STEPS_MED_MAX → sonnet`, else `opus`. Same shape for deliverables and files.
     - Compute final tier as `max` of the four signal tiers in `haiku < sonnet < opus` ordering. Apply heuristic-flag bumps: each low-flag match `+1 tier`, each high-flag match `+1 tier`, capped at `opus`.
     - Detect `**ComplexityOverride:** <tier>` line inside the phase block (fence-aware). When present, the override **replaces** the computed tier outright. Allowed values `haiku`, `sonnet`, `opus`.
     - Compute `overBudget`: true when any single signal independently scored `opus` AND no override is clamping it down.
   - Stdout shape:
     - `--phase N`: single JSON object `{"phase":N,"tier":"...","signals":{"steps":N,"deliverables":N,"files":N,"flagsLow":[...],"flagsHigh":[...]},"overBudget":bool,"override":"tier|null"}`.
     - No `--phase`: JSON array of objects in document order.
   - Use `jq` for JSON assembly when available; pure-bash `printf` fallback otherwise. Match the FEAT-027 / FEAT-021 fallback pattern.
   - `chmod +x`.

3. Create `scripts/tests/fixtures/dag-valid-plan.md` — a 3-phase plan with `Phase 2 Depends on Phase 1` and `Phase 3 Depends on Phase 1, Phase 2`. Used by `validate-plan-dag.sh` happy path.

4. Create `scripts/tests/fixtures/dag-cycle-plan.md` — a 4-phase plan with `Phase 2 Depends on Phase 4` and `Phase 4 Depends on Phase 2` to exercise the cycle detector.

5. Create `scripts/tests/fixtures/dag-fenced-plan.md` — a plan with `**Depends on:** Phase 99` inside a fenced block (template documentation) and a real `**Depends on:** Phase 1` outside fences. The fenced reference must be ignored.

6. Create `scripts/tests/fixtures/budget-mixed-plan.md` — a 4-phase plan covering threshold boundaries: Phase 1 (3 steps / 4 deliverables / 3 files / no flags → haiku, all axes at low boundary), Phase 2 (7 steps / 9 deliverables / 8 files → sonnet, all axes at sonnet upper boundary), Phase 3 (5 steps + the substring `schema` → sonnet base + low-flag bump → opus), Phase 4 (8 steps / 10 deliverables / 9 files → opus on every axis, `overBudget=true`).

7. Create `scripts/tests/fixtures/budget-override-plan.md` — a 2-phase plan where Phase 1 would score `opus` but contains `**ComplexityOverride:** haiku`; Phase 2 has no override and scores `sonnet`.

8. Write `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/validate-plan-dag.bats`:
   - Happy path (valid 3-phase DAG) → stdout `ok`, exit `0`.
   - 2-cycle (`Phase 2 Depends on Phase 4`, `Phase 4 Depends on Phase 2`) → exit `1`, stderr lists both phases.
   - Larger 3-cycle (constructed in a fixture variant) → exit `1`, stderr lists all three.
   - Unresolved reference (`Phase 1 Depends on Phase 99`) → exit `1`, stderr names both phases.
   - Fence-awareness (`dag-fenced-plan.md` — fenced `Phase 99` reference ignored, real `Phase 1` reference parsed) → stdout `ok`, exit `0`.
   - Absence of `**Depends on:**` line treated as no dependencies → stdout `ok`.
   - Free-text token (`**Depends on:** PR #123 merging`) ignored → stdout `ok`.
   - Missing arg → exit `2`. Non-existent file → exit `1`.

9. Write `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/phase-complexity-budget.bats`:
   - Happy path with `--phase 1` on `budget-mixed-plan.md` → JSON object with tier `haiku`, all four signals reported.
   - Happy path without `--phase` → JSON array, four entries in document order, tiers `[haiku, sonnet, opus, opus]`.
   - Threshold boundaries: steps `3` → haiku, `4` → sonnet, `7` → sonnet, `8` → opus; same shape for deliverables (`4`/`5`, `9`/`10`) and files (`3`/`4`, `8`/`9`).
   - Heuristic flag matches: low-flag `schema` on a sonnet-base phase → bumps to opus; high-flag `security` on a haiku-base phase → bumps to sonnet.
   - Heuristic stacking: a phase matching both `schema` and `public api` and a high-base sonnet → caps at opus, no overflow.
   - `overBudget` true when steps independently score opus AND no override clamping (use a phase with 9 steps but only 2 deliverables / 1 file).
   - `**ComplexityOverride:**` clamps: haiku, sonnet, opus all replace the computed tier; `overBudget` reported as the pre-override value (false when override clamps an over-budget phase down).
   - Fence-awareness: `**ComplexityOverride:**` inside a fenced block ignored.
   - Error tests: missing arg → exit `2`; malformed `--phase abc` → exit `2`; non-existent file → exit `1`; plan with no `### Phase` blocks → exit `1`.

10. Run both bats fixtures locally and confirm all cases pass. Run `npm test -- --testPathPatterns=creating-implementation-plans | tail -60` and `npm run validate` to confirm zero regressions.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/validate-plan-dag.sh`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/phase-complexity-budget.sh`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/dag-valid-plan.md`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/dag-cycle-plan.md`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/dag-fenced-plan.md`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/budget-mixed-plan.md`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/budget-override-plan.md`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/validate-plan-dag.bats`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/phase-complexity-budget.bats`

---

### Phase 3: Advisory Splitter + Phase-Size Gate (FR-4, FR-5)

**Feature:** [FEAT-029](../features/FEAT-029-creating-implementation-plans-scripts.md) | [#190](https://github.com/lwndev/lwndev-marketplace/issues/190)
**Status:** ✅ Complete
**Depends on:** Phase 2

#### Rationale

`split-phase-suggest.sh` (FR-4) is advisory and never writes the plan file; `validate-phase-sizes.sh` (FR-5) is a thin composer over `phase-complexity-budget.sh` (FR-3) that translates the per-phase JSON into actionable warnings. They ship together because they form the user-visible "plan-size discipline" pair: FR-5 surfaces an over-budget phase, FR-4 proposes a viable split, the model authors the actual split, the loop terminates when FR-5 returns `ok`.

This phase also flips the warn-only `--enforce-phase-budget` flag in `render-plan-scaffold.sh` (FR-1) into a real gate: when the flag is set, FR-5 is invoked after rendering and its non-zero exit propagates as the script's exit `1`. The Phase 1 `[warn] --enforce-phase-budget will activate ...` line is removed.

`split-phase-suggest.sh` deliberately stays prose-light: the script proposes a viable cut but the semantic judgment (does this split keep TDD pairing intact? does it preserve the phase's narrative arc?) remains the model's responsibility.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/split-phase-suggest.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`; Bash 3.2-compatible.
   - Top-of-file comment block: purpose, signature `split-phase-suggest.sh <plan-file> <phase-N>`, exit codes (`0` success even on heuristic-best-effort / `1` plan I/O error or phase block missing / `2` missing args).
   - Reuse the block scanner from Phase 2. Read the requested phase block; extract the implementation-step list (lines matching `^[0-9]+\. `) and the deliverable list (for chunk-name derivation).
   - Scan each step for explicit `Depends on Step <N>` annotations (e.g., `4. Run tests (depends on Step 3)`). Record those constraints.
   - Default split shape: 2-way for 4–7 steps, 3-way for 8+ steps, no split for ≤3 steps (`{"original":N,"suggestions":[]}`, exit `0`).
   - Group steps into contiguous chunks aiming for roughly equal counts (within ±1 step). Boundary placement must satisfy every recorded `Depends on Step N` constraint (no chunk may end before its prerequisite).
   - Derive chunk names heuristically: take the first step's leading verb + a noun extracted from the deliverable list (best-effort; the model authors the final names).
   - Stdout: single JSON object `{"original":N,"suggestions":[{"name":"...","steps":[1,2,3]},...]}`. Use `jq` when available; pure-bash fallback otherwise.
   - **Advisory only**: never writes the plan file. `chmod +x`.

2. Write `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/validate-phase-sizes.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`; Bash 3.2-compatible.
   - Top-of-file comment block: purpose, signature `validate-phase-sizes.sh <plan-file>`, exit codes (`0` ok / `1` one or more failing phases or plan I/O error / `2` missing arg).
   - Invoke `${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/phase-complexity-budget.sh <plan-file>` (FR-3); parse the JSON array (use `jq` when available; pure-bash fallback otherwise).
   - For every phase where `overBudget == true` and `override == null`, emit `[warn] phase <N>: over budget — <signal>=<value> exceeds opus threshold; either split (see split-phase-suggest.sh) or add **ComplexityOverride:** high to the phase block.` to stderr. Pick the dominant signal (the one that scored opus first by axis-precedence: steps > deliverables > files); when multiple axes scored opus, list the highest-scoring one.
   - On no failing phases: stdout `ok`, exit `0`. On one or more failing phases: nothing on stdout, stderr lists every offender, exit `1`.
   - `chmod +x`.

3. Amend `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/render-plan-scaffold.sh` from Phase 1: when `--enforce-phase-budget` is supplied, after the rendered file is written, invoke `validate-phase-sizes.sh <rendered-path>` and propagate the exit code. Remove the Phase 1 `[warn] --enforce-phase-budget will activate ...` placeholder line. Preserve all other FR-1 behaviour.

4. Create `scripts/tests/fixtures/split-overflow-plan.md` — a 1-phase plan where the phase has 9 implementation steps (forces a 3-way split). Include one explicit `Depends on Step 4` annotation on Step 6 to exercise the constraint logic.

5. Create `scripts/tests/fixtures/split-tiny-plan.md` — a 1-phase plan with a single implementation step. Used to verify the `{"suggestions":[]}` empty-array path.

6. Write `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/split-phase-suggest.bats`:
   - Happy path (4-step phase) → 2-way split, JSON has 2 suggestion entries with non-overlapping `steps` arrays summing to all 4 indices.
   - Happy path (8-step phase) → 3-way split, 3 suggestion entries, balanced ±1 step.
   - 1-step phase → `{"original":N,"suggestions":[]}`, exit `0`.
   - Step-ordering preservation: every suggestion's `steps` array is monotonically increasing; concatenated in suggestion order, equals `[1,2,...,N]`.
   - `Depends on Step 4` annotation: split boundary on a 6-step phase must not place Step 5 in a chunk that terminates before Step 4 is included.
   - Error tests: missing args → exit `2`; non-existent file → exit `1`; phase block missing → exit `1`.

7. Write `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/validate-phase-sizes.bats`:
   - Happy path on a plan with all phases at/under budget → stdout `ok`, exit `0`.
   - One over-budget phase (no override) → exit `1`, stderr contains the documented `[warn] phase <N>: over budget — ...` line for that phase only.
   - Override clamps an over-budget phase → that phase passes the gate; stdout `ok` if no other failures.
   - Multiple over-budget phases → stderr lists each on its own line, exit `1`.
   - Missing arg → exit `2`; non-existent file → exit `1` (resolver-style propagation).

8. Extend `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/render-plan-scaffold.bats` (from Phase 1):
   - `--enforce-phase-budget` on a freshly-rendered plan (placeholder phase blocks have no signals → all phases score `haiku` → gate passes) → exit `0`, no `[warn]` placeholder line on stderr.
   - Confirm the Phase 1 placeholder warn line is no longer emitted.

9. Run all bats fixtures locally; run `npm test -- --testPathPatterns=creating-implementation-plans | tail -60` and `npm run validate`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/split-phase-suggest.sh`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/validate-phase-sizes.sh`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/render-plan-scaffold.sh` (amended: `--enforce-phase-budget` wired to FR-5)
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/split-overflow-plan.md`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/fixtures/split-tiny-plan.md`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/split-phase-suggest.bats`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/validate-phase-sizes.bats`
- [x] `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/render-plan-scaffold.bats` (extended)

---

### Phase 4: Lower `implementing-plan-phases` Baseline + Per-Phase `resolve-tier` (FR-7, FR-6)

**Feature:** [FEAT-029](../features/FEAT-029-creating-implementation-plans-scripts.md) | [#190](https://github.com/lwndev/lwndev-marketplace/issues/190)
**Status:** Pending
**Depends on:** Phase 2

#### Rationale

This phase amends `workflow-state.sh` in two coupled ways: the baseline-matrix entry for `implementing-plan-phases` drops from `sonnet` to `haiku` (FR-7), and `resolve-tier` learns to consult `phase-complexity-budget.sh` (Phase 2's FR-3) when called with `--phase N --plan-file <path>` and `<skill> == implementing-plan-phases` (FR-6). The two changes ship together because they are semantically coupled — lowering the baseline without per-phase classification would default every `implementing-plan-phases` fork to Haiku regardless of the phase's actual complexity (a regression for genuinely-complex phases); shipping per-phase classification without lowering the baseline would leave the floor at Sonnet (negating the savings lever).

FR-7 changes a single line in the `_step_baseline` function (the `implementing-plan-phases` entry). The bats coverage extension covers the new baseline value and the upgrade-only override-chain semantics (soft overrides still push tier up; hard overrides still bypass).

FR-6 amends the `resolve-tier` dispatch case to accept `--phase N --plan-file <path>`. Both flags must be supplied together (exit `2` on partial supply). When both are present and `<skill> == implementing-plan-phases`, the script invokes `phase-complexity-budget.sh <plan-file> --phase <N>` and uses the returned tier as the work-item complexity axis input (Axis 2) in place of the persisted workflow-level `complexity`. The override chain (Axis 3) walks unchanged. When `--phase`/`--plan-file` are present but `<skill>` is not `implementing-plan-phases`, the flags are accepted but ignored with `[info] resolve-tier: --phase ignored for non-phase skill <skill>` on stderr.

The persisted `modelSelections[step-N][phase-N]` keying is the schema extension. NFR-5 requires silent in-place migration for pre-existing state files — the per-phase entry is added on first FR-6 invocation; pre-existing entries are untouched.

Edge Case 9 (graceful degradation): when `phase-complexity-budget.sh` exits non-zero (malformed plan, missing file), `resolve-tier` falls back to the workflow-level `complexity` value and emits `[warn] resolve-tier: phase-complexity-budget failed for phase <N>; falling back to workflow complexity <tier>.` to stderr. The fork still runs.

#### Implementation Steps

1. Amend `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` `_step_baseline` function: change the `implementing-plan-phases` entry from `sonnet` to `haiku`. Confirm `_step_baseline_locked` for `implementing-plan-phases` is `false` (it is not baseline-locked — only `finalizing-workflow` and `pr-creation` are locked) and leave it unchanged.

2. Amend the `resolve-tier)` dispatch case in `workflow-state.sh`:
   - Parse two new optional flags `--phase N` and `--plan-file <path>` from the existing argv parser. Both must be supplied together: supplying only `--phase` or only `--plan-file` → exit `2` with `Error: --phase and --plan-file must be supplied together`.
   - When both are present and `<skill> == implementing-plan-phases`: invoke `${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/phase-complexity-budget.sh <plan-file> --phase <N>`. Capture stdout. On non-zero exit: emit the documented `[warn] resolve-tier: phase-complexity-budget failed for phase <N>; falling back to workflow complexity <tier>.` to stderr and proceed with the existing workflow-level `complexity` value. On success: parse the JSON `tier` field via `jq -r .tier` and use that value as the work-item complexity axis input.
   - When both flags are present but `<skill>` is not `implementing-plan-phases`: accept the flags, emit `[info] resolve-tier: --phase ignored for non-phase skill <skill>` to stderr, proceed with existing behaviour.
   - When neither flag is present: behaviour is unchanged.

3. Extend the `record-model-selection)` dispatch (or the writer function it calls) to persist the per-phase tier under `modelSelections[step-N][phase-N]`. The existing `phase` field on `modelSelections` continues to record which phase the entry belongs to; the new per-phase tier is keyed under that. Use a `jq` write that creates the nested object on first write and updates in place on subsequent writes — silent migration per NFR-5 (no schema bump, no migration script).

4. Extend `scripts/__tests__/workflow-state.test.ts` with cases:
   - `_step_baseline implementing-plan-phases` returns `haiku` (was `sonnet`).
   - `resolve-tier <ID> <step> implementing-plan-phases --phase 2 --plan-file <budget-mixed-plan>` returns the per-phase tier from FR-3 (e.g., `haiku` for a haiku-scoring phase, `sonnet` for a sonnet-scoring phase).
   - `resolve-tier <ID> <step> reviewing-requirements --phase 1 --plan-file <path>` emits the `[info] resolve-tier: --phase ignored for non-phase skill reviewing-requirements` line and resolves at the existing complexity axis.
   - `resolve-tier ... --phase 1` (no `--plan-file`) → exit `2`.
   - `resolve-tier ... --plan-file <path>` (no `--phase`) → exit `2`.
   - `resolve-tier ... --phase 1 --plan-file /nonexistent/path.md` → `[warn] resolve-tier: phase-complexity-budget failed ...` on stderr; falls back to workflow complexity.
   - `record-model-selection` extended to write `modelSelections[step-N][phase-N]`: assert the persisted JSON has the per-phase keying after a per-phase invocation; assert pre-existing entries (created without `--phase`) are untouched.

5. Run `npm test -- --testPathPatterns=workflow-state | tail -50`; confirm all new and existing cases pass.

6. Run the full `npm test` suite — confirm zero regressions. Run `npm run validate` to confirm plugin validation passes.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` (amended: `_step_baseline` lowered, `resolve-tier` accepts `--phase`/`--plan-file`, `record-model-selection` persists per-phase keying)
- [ ] `scripts/__tests__/workflow-state.test.ts` (extended: per-phase resolution, partial-flag exit `2`, fallback warn line, persistence schema)

---

### Phase 5: `prepare-fork.sh` Forwarding + Post-Plan `max` Classifier (FR-8, FR-9)

**Feature:** [FEAT-029](../features/FEAT-029-creating-implementation-plans-scripts.md) | [#190](https://github.com/lwndev/lwndev-marketplace/issues/190)
**Status:** Pending
**Depends on:** Phase 4

#### Rationale

This phase wires per-phase classification end-to-end through the orchestrator's pre-fork ceremony. `prepare-fork.sh` (FR-8) accepts and forwards two new optional flags `--phase N` and `--plan-file <path>` straight through to the internal `workflow-state.sh resolve-tier` call. The orchestrator passes them when forking `implementing-plan-phases` for phase N of a plan; other forked steps (`reviewing-requirements`, `creating-implementation-plans`, `executing-chores`, etc.) continue to behave as today. The FR-14 console echo line gains a per-phase suffix: `[model] step <N> (implementing-plan-phases) → <tier> (workflow=<complexity>, phase=<N>=<phase-tier>)`. The Unicode `→` is the documented emitter format and stays.

The post-plan classifier (FR-9) replaces the existing raw-phase-count mapping (`1→low`, `2–3→medium`, `4+→high`) with a `max`-of-per-phase-tiers calculation: invoke `phase-complexity-budget.sh <plan-file>` on the freshly-authored plan, compute `max` over all returned tiers, persist as the workflow's post-plan `complexity`. Splitting a phase no longer upgrades the workflow's complexity — it distributes work across cheaper per-phase forks. The upgrade-only invariant (FEAT-014 FR-2b) is preserved: when `max` is *lower* than the persisted init-stage `complexity`, the persisted value wins. Edge Case 8 / NFR-4 contract from FEAT-014 holds.

Edge Case 9 fallback symmetric to Phase 4: when `phase-complexity-budget.sh` exits non-zero during `classify-post-plan`, the persisted init-stage `complexity` is preserved unchanged, a `[warn] classify-post-plan: phase-complexity-budget failed; preserving init-stage complexity <tier>.` line is emitted, and the workflow continues.

This is the canary phase: it scores itself against FR-3's budget (5 implementation steps, 6 deliverables, ~6 distinct file paths, low-flag match `schema` not present, high-flag match `multi-skill refactor` not present — should score `sonnet` per FR-3's aggregation rule). The very last fork that orchestrates this phase will resolve at the per-phase tier from FR-6, demonstrating the full loop.

#### Implementation Steps

1. Amend `plugins/lwndev-sdlc/scripts/prepare-fork.sh`:
   - Parse two new optional flags `--phase N` and `--plan-file <path>` in the existing argv loop. Both must be supplied together: partial supply → exit `2` with the documented error.
   - Cross-validation: `--phase` is only valid with `<skill> == implementing-plan-phases` (the existing `--phase` validation from FEAT-021 already enforces this — extend to also require `--plan-file`). Reject other skill names with the existing exit `2` message.
   - Forward both flags verbatim into the internal `workflow-state.sh resolve-tier` call (use `${var:+--flag "$var"}` pattern, mirroring the existing `--cli-model` / `--cli-complexity` forwarding).
   - Extend the FR-14 echo line for `implementing-plan-phases` forks: append ` phase=<N>=<phase-tier>` to the parenthetical slot. Format: `[model] step <N> (implementing-plan-phases) → <tier> (workflow=<complexity>, phase=<N>=<phase-tier>)`. Read `phase-tier` from the captured `resolve-tier` stdout (which already carries the per-phase value when FR-6 resolved per-phase).
   - Other forked skills unaffected: when `--phase`/`--plan-file` are absent, the echo line uses the existing format from FEAT-021.

2. Amend the `classify-post-plan)` dispatch case in `workflow-state.sh`:
   - Replace the existing raw-phase-count mapping with: invoke `${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/phase-complexity-budget.sh <plan-file>`. Capture stdout. Parse the JSON array via `jq -r '[.[].tier] | unique'` (or pure-bash fallback). Compute `max` in the `haiku < sonnet < opus` ordering.
   - Honour the upgrade-only invariant (FEAT-014 FR-2b): read the persisted init-stage `complexity` from the state file; if `max(per-phase tiers)` ordinal is less than the persisted ordinal, keep the persisted value. Persist `max` only when it is strictly greater than the persisted value, mapping `complexityStage = post-plan` (semantics unchanged from FEAT-014).
   - On `phase-complexity-budget.sh` non-zero exit: emit `[warn] classify-post-plan: phase-complexity-budget failed; preserving init-stage complexity <tier>.` to stderr; preserve the persisted value unchanged; exit `0` (graceful degradation, matches Edge Case 9).
   - On a tier upgrade: emit the existing `[model] Work-item complexity upgraded since last invocation: <old> → <new>. Audit trail continues.` line per FEAT-014 FR-2b / NFR-2.

3. Extend `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats`:
   - `--phase N --plan-file <path>` forwarding for `implementing-plan-phases`: assert the resolved tier matches the per-phase tier from FR-3 (use `budget-mixed-plan.md` fixture); assert the FR-14 echo line includes the `phase=<N>=<phase-tier>` suffix.
   - `--phase N` without `--plan-file` → exit `2`. `--plan-file <path>` without `--phase` → exit `2`.
   - `--phase` on a non-`implementing-plan-phases` skill (e.g., `reviewing-requirements`) → exit `2` (per existing FEAT-021 cross-validation, extended).
   - Other forked skills (no `--phase` flag) → echo line uses the existing FEAT-021 format unchanged.

4. Extend `scripts/__tests__/workflow-state.test.ts`:
   - `classify-post-plan` happy path on a plan whose phases score `[haiku, sonnet, haiku, haiku]` → persists `sonnet`, emits the upgrade audit line if init was `low`/`haiku`.
   - Upgrade-only invariant: init `high` + per-phase `max(haiku,haiku,haiku) = haiku` → persisted complexity stays `high`, no audit line emitted.
   - `phase-complexity-budget.sh` failure (point at non-existent plan file): assert `[warn] classify-post-plan: phase-complexity-budget failed; preserving init-stage complexity <tier>.` line; persisted complexity unchanged; exit `0`.

5. Run `npm test -- --testPathPatterns=prepare-fork | tail -60` and `npm test -- --testPathPatterns=workflow-state | tail -60`; confirm all cases pass.

6. Integration smoke test: against a synthetic 4-phase plan where 3 phases score `haiku` and 1 scores `sonnet`, run `prepare-fork.sh <ID> <step> implementing-plan-phases --phase 1 --plan-file <plan>` for each phase. Confirm the resolved tier matches the per-phase tier; the FR-14 echo line carries the `phase=<N>=<tier>` suffix; `modelSelections` state correctly records per-phase entries.

7. Run `npm test` (full suite) and `npm run validate` — confirm zero regressions.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/scripts/prepare-fork.sh` (amended: `--phase`/`--plan-file` forwarding, FR-14 echo line extended)
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` (amended: `classify-post-plan` uses `max`-of-per-phase-tiers + upgrade-only invariant + Edge Case 9 fallback)
- [ ] `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` (extended: per-phase forwarding, partial-flag rejection, echo-line suffix)
- [ ] `scripts/__tests__/workflow-state.test.ts` (extended: `classify-post-plan` per-phase semantics, upgrade-only invariant, fallback)

---

### Phase 6: Documentation Rewrite + SKILL.md Lean-Down (FR-10, NFR-4, NFR-6)

**Feature:** [FEAT-029](../features/FEAT-029-creating-implementation-plans-scripts.md) | [#190](https://github.com/lwndev/lwndev-marketplace/issues/190)
**Status:** Pending
**Depends on:** Phase 5

#### Rationale

The user-visible cutover. With every script live and tested (Phases 1–3) and the tier-resolution path engaged end-to-end (Phases 4–5), the documentation can be rewritten with confidence that every pointer is backed by a working, tested implementation. This phase must land last for the same self-bootstrapping safety reasons as FEAT-027 Phase 4: a SKILL.md rewrite that points at not-yet-existent scripts would break the live skill mid-workflow.

Three discrete deliverables: (1) `references/model-selection.md` rewrite per FR-10 (rewriting the "Feature post-plan signal extractor" section, retiring the Edge Case 8 limitation, re-framing the Haiku-floor caution, adding a `modelSelections` migration note); (2) `creating-implementation-plans/SKILL.md` lean-down per NFR-4 (Quick Start steps 3–5 collapse into single-line script invocations of FR-1 / FR-2 / FR-5; Verification Checklist gains the FR-5 item and updates the DAG-validation item to reference FR-2 by name); (3) cross-reference updates per NFR-6 (`references/step-execution-details.md`, `references/forked-steps.md`, plugin-level READMEs).

The `creating-implementation-plans/README.md` (or plugin-level README under `${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/`) gains a one-line entry per new script (FR-1 through FR-5) mirroring the FEAT-027 README convention.

#### Implementation Steps

1. Rewrite `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md`:
   - **"Feature post-plan signal extractor" section** (under "Axis 2 — Work-item complexity signal matrix"): rewrite to document the per-phase classification path. Link to FR-3 (`phase-complexity-budget.sh`); explain the `max`-of-per-phase-tiers rule (FR-9); document the per-phase override line (`**ComplexityOverride:** <tier>`).
   - **Known Limitation bullet** that combines (a) `implementing-plan-phases` Haiku floor and (b) per-phase-classification gap: replace with two distinct entries: (1) brief note that per-phase classification is now first-class for `implementing-plan-phases` forks (link to FR-6 + FR-9), (2) re-framed entry describing the new explicit per-phase floor (`haiku`) that per-phase classification can upgrade (link to FR-7).
   - **"Tuning the baseline matrix" cautionary note** (currently "Do not drop `implementing-plan-phases` below `sonnet`"): re-frame from a hard "do not drop below sonnet" caution to a per-phase-floor explanation pointing to FR-3 + FR-6. After FR-7 ships, the prior caution is actively wrong.
   - Add a brief migration note describing the contract change for the `modelSelections` shape (per-phase keying under `modelSelections[step-N]`) for any downstream consumers.

2. Rewrite `plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md` per NFR-4:
   - **Retain verbatim** (public contract): YAML frontmatter, `When to Use This Skill` section, `Flexibility` section, `Arguments` section, `Output Style` section (lite-narration rules, load-bearing carve-outs, fork-to-orchestrator return contract), `File Locations` section (filename convention).
   - **Quick Start steps 3–5** collapse into single-line invocations of `render-plan-scaffold.sh` (FR-1), `validate-plan-dag.sh` (FR-2), and `validate-phase-sizes.sh` (FR-5). Step 1 (resolve-requirement-doc.sh) and Step 2 (ask for GitHub issue URL) unchanged.
   - **Verification Checklist** gains one new item (`validate-phase-sizes.sh`) and updates the existing DAG-validation item to reference FR-2 (`validate-plan-dag.sh`) by name.
   - Net SKILL.md token reduction target: ~550–750 tok per plan creation (NFR-4). Verify via `wc -l` against the pre-rewrite line count; aim for ≥ 15% reduction.
   - Run `npm run validate` to confirm `allowed-tools` list still passes.

3. Audit `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` and `references/forked-steps.md` per NFR-6: where these docs reference the post-plan classifier or per-step baseline matrix, replace inline prose with a link to the rewritten `references/model-selection.md` section. No duplicated prose.

4. Update `plugins/lwndev-sdlc/skills/creating-implementation-plans/README.md` (create if absent — match the FEAT-027 plugin-README convention): list the five new scripts (FR-1 through FR-5) with one-line purposes. If a `creating-implementation-plans/README.md` does not exist and the plugin-level README at `plugins/lwndev-sdlc/scripts/README.md` is the canonical location for skill-script tables, add the entries there instead (mirror the FEAT-027 README structure).

5. Audit `requirements/features/FEAT-014-adaptive-model-selection.md`: add a post-FEAT-029 note linking to FEAT-029 as the current scripted entry point for per-phase tier resolution and the `max`-of-per-phase-tiers post-plan classifier (mirror the FEAT-021 → FEAT-014 cross-reference pattern).

6. Run `npm test` (full suite); `npm run validate`; `npm run lint`; `npm run format:check`. Confirm zero regressions and clean lint/format.

7. Manual smoke test (NFR-5 backward compatibility): take a pre-FEAT-029 plan (e.g., FEAT-027's plan or any older `requirements/implementation/*.md`) and run `validate-plan-dag.sh` and `phase-complexity-budget.sh` against it. Both must succeed (no `**ComplexityOverride:**` lines and no `**Depends on:**` lines on phases is the documented backward-compat path). A pre-existing state file (without per-phase keying) must load cleanly without manual migration.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` (rewritten per FR-10)
- [ ] `plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md` (lean-down per NFR-4)
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` (cross-references updated per NFR-6)
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/forked-steps.md` (cross-references updated per NFR-6)
- [ ] `plugins/lwndev-sdlc/skills/creating-implementation-plans/README.md` (new or updated: lists FR-1 through FR-5 scripts)
- [ ] `requirements/features/FEAT-014-adaptive-model-selection.md` (post-FEAT-029 cross-reference note added)

---

## Shared Infrastructure

- **Skill-scoped scripts directory** — new `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/` and sibling `scripts/tests/` + `scripts/tests/fixtures/` created in Phase 1. Structure mirrors `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/` (FEAT-027 precedent) and `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/` (FEAT-026 precedent) exactly.
- **Block-boundary scanner** — `### Phase <N>: <name>` heading → next `### Phase` heading or EOF. Established in Phase 2 (`validate-plan-dag.sh`, `phase-complexity-budget.sh`) and reused by Phase 3 (`split-phase-suggest.sh`). One implementation, tested in Phase 2, reused with confidence.
- **Fence-tracking pattern** — toggle on lines starting with ```` ``` ```` or `~~~`; skip matched lines outside the block scanner's interest. Established in Phase 2 (`**Depends on:**`, `**ComplexityOverride:**`) and reused by Phase 3 (`split-phase-suggest.sh` step extraction). Mirrors the FEAT-027 `plan-status-marker.sh` fence-tracking pattern.
- **`jq` vs. pure-bash fallback** — FR-3, FR-4 emit JSON; both use `jq` when available and pure-bash `printf` fallback otherwise. Consistent with FEAT-021 / FEAT-027 precedent. Declare `jq` as optional in each script's top-of-file comment block.
- **No new plugin-shared scripts** — all five FR-1 through FR-5 scripts are self-contained under `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/`. The plugin-shared `plugins/lwndev-sdlc/scripts/` directory is modified only to amend `prepare-fork.sh` (Phase 5).
- **No factored-out parse helper** — the block scanner and fence tracker are short enough (~30–50 lines each) that copy-and-test across `validate-plan-dag.sh` and `phase-complexity-budget.sh` is simpler than a sourced helper. If a third caller appears in a future iteration, factor at that point. YAGNI.

## Testing Strategy

- **Unit tests (bats, Phases 1–3)** — one `.bats` file per new script under `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/`. Covers happy path, every documented exit code, fence-awareness for FR-2/FR-3, every signal-threshold boundary for FR-3, override clamps for FR-3, heuristic-flag stacking caps for FR-3, gate-failure and override-clamp passes for FR-5, ordering preservation and `Depends on Step N` constraint logic for FR-4. String-exactness on `[warn]` / `[error]` / `[info]` stderr lines.
- **Unit tests (TypeScript, Phases 4–5)** — extend `scripts/__tests__/workflow-state.test.ts` with cases for `_step_baseline` (FR-7), `resolve-tier --phase --plan-file` (FR-6 happy path, partial-flag rejection, non-phase-skill `[info]` line, fallback `[warn]` line, persistence schema), and `classify-post-plan` (FR-9 `max`-of-per-phase-tiers, upgrade-only invariant, fallback `[warn]` line). Extend `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` with cases for `--phase`/`--plan-file` forwarding (FR-8) and the FR-14 echo-line suffix.
- **Integration tests (Phase 5)** — end-to-end on a synthetic 4-phase plan where 3 phases qualify as `haiku` and 1 as `sonnet`. Run `prepare-fork.sh` for each phase; confirm the resolved tier matches the per-phase tier; confirm the FR-14 echo line carries `phase=<N>=<tier>`; confirm `modelSelections` state correctly records per-phase entries. Graceful-degradation case: simulate `phase-complexity-budget.sh` failure inside `resolve-tier`; confirm the fork still runs at the workflow-level `complexity` tier; confirm the documented `[warn]` line is emitted. Resume case: pause at the plan-approval pause point, edit a phase's `**ComplexityOverride:**` line in the plan file, resume; confirm the post-plan classifier re-runs and the per-phase tier reflects the override.
- **Manual E2E (Phase 6)** — run the orchestrating-workflows skill against a real feature (this one — FEAT-029) end to end. Confirm: `phase-complexity-budget.sh` scores produce sensible tier assignments; `validate-phase-sizes.sh` either passes or surfaces actionable warnings; per-phase forks use the resolved tiers (cross-check via `[model]` echo lines in stderr); total Opus minutes spent on the feature workflow are visibly reduced versus a pre-FEAT-029 baseline (at least one phase resolves below Opus). NFR-5 backward compatibility: a pre-existing plan (no `**ComplexityOverride:**` lines) validates clean; a pre-existing state file loads without manual migration.

## Dependencies and Prerequisites

- **#180 — `resolve-requirement-doc.sh` and the plugin-shared foundation library** (already shipped): `render-plan-scaffold.sh` (FR-1) calls `resolve-requirement-doc.sh` to resolve `FEAT-NNN` IDs to file paths.
- **FEAT-021 — `prepare-fork.sh` skeleton** (already shipped via #181): FR-8 amends the script delivered by FEAT-021. The existing `--mode`/`--phase` cross-validation logic is extended for `--phase`/`--plan-file` together.
- **FEAT-014 — Adaptive Model Selection** (already shipped): every change here builds on the override chain, complexity axis, baseline matrix, and `modelSelections` persistence introduced by FEAT-014. The post-plan classifier (FR-9), upgrade-only invariant (FR-9 + NFR-2), and override-chain walking (FR-6) all extend FEAT-014's contracts.
- **FEAT-026, FEAT-027** (already shipped): the script conventions, bats-coverage convention, and `[info]` / `[warn]` / `[model]` tagged-log convention are inherited verbatim. No reference changes; conventions are stable.
- No new npm dependencies. No new runtime dependencies beyond what existing scripts already require (`bash`, `jq`, `awk`, `sed`, `grep`, `tr`).
- No upstream blockers — every dependency is on `main`. Phases ship in order (1 → 2 → 3 → 4 → 5 → 6) within the same release branch and can land in a single PR or sequential PRs at the team's preference.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **Heuristic-flag false positive** in `phase-complexity-budget.sh`: a phase block contains `schema` in unrelated context (e.g., "this phase does not modify the database schema"); FR-3 still bumps the tier on the substring match | Medium | Medium | Documented in feature doc Edge Case 5. The per-phase `**ComplexityOverride:** <tier>` line is the explicit escape hatch (clamps the tier outright). False positives are an acceptable cost; tighter NLP is out of scope (Future Enhancement). |
| **Post-plan classifier downgrade** subtlety: a feature classified `high` at init time produces a plan whose phases all score `haiku`; the model interprets `max(haiku, haiku, ...) = haiku` as "downgrade to haiku" and is confused when the persisted complexity stays `high` | Medium | Low | The upgrade-only invariant is honoured (FR-9, NFR-5). The audit trail emits the existing `[model] Work-item complexity upgraded ...` line only on actual upgrades; no log line on the no-op preserve path keeps the audit trail clean. Documented in Edge Case 8 of the feature doc. |
| **NFR-5 backward-compat regression**: a pre-existing plan without `**ComplexityOverride:**` or `**Depends on:**` lines fails the new gates | High | Low | NFR-5 explicitly tests this in Phase 6 manual smoke. `phase-complexity-budget.sh` treats absence of an override as "no clamp" (computed tier wins); `validate-plan-dag.sh` treats absence of `**Depends on:**` as "no dependencies" (implicit sequential ordering, matching today's model behaviour). Bats fixtures include a "no-override / no-depends" plan to cover this path. |
| **Schema-migration silent bug**: `modelSelections[step-N][phase-N]` per-phase keying corrupts a pre-existing state file on first FR-6 invocation | High | Low | Phase 4 step 4 includes an explicit test case: a pre-existing state file (created without `--phase`) loads cleanly; a per-phase invocation appends the per-phase keying without modifying pre-existing entries. The migration is silent in-place per NFR-5, identical to FEAT-014 FR-13 precedent. `jq` writes use `+` operator semantics (additive merge), not full replacement. |
| **`prepare-fork.sh` cross-validation regression**: extending the existing `--mode`/`--phase` cross-validation logic for `--phase`/`--plan-file` together accidentally rejects valid FEAT-021 invocations | Medium | Low | Phase 5 step 3 extends the existing bats fixture; the regression suite from FEAT-021 (every existing case in `prepare-fork.bats`) must still pass unchanged. CI catches any cross-validation regression at PR time. |
| **Self-bootstrapping break**: SKILL.md rewrite (Phase 6) lands before scripts are tested, breaking the live `creating-implementation-plans` skill mid-workflow | High | Low | Phase 6 is strictly ordered after Phases 1–5. SKILL.md is only rewritten after all scripts exist and bats tests pass. Phase 6 implementation steps include running `npm test` before committing the rewrite. Same precedent as FEAT-027 Phase 4. |
| **`split-phase-suggest.sh` produces semantically nonsensical splits** (e.g., splits a TDD red-then-green pair across chunks) | Low | Medium | FR-4 is advisory only — the model authors the actual split. The script emits a viable cut, not the final wording. The documentation rewrite (Phase 6) makes this caveat explicit at the FR-4 callsite. |

## Success Criteria

- **FR-1**: `render-plan-scaffold.sh` exists with full bats coverage, supports single and multi-feature inputs, refuses to overwrite, supports `--enforce-phase-budget` (warn-only in Phase 1, real gate after Phase 3 lands FR-5).
- **FR-2**: `validate-plan-dag.sh` exists with full bats coverage; detects cycles and unresolved references; is fence-aware.
- **FR-3**: `phase-complexity-budget.sh` exists with full bats coverage; supports per-phase and full-plan modes; honours `**ComplexityOverride:**` clamps; budget table is documented at the top of the script for tuning.
- **FR-4**: `split-phase-suggest.sh` exists with full bats coverage; preserves step ordering and `**Depends on Step N**` annotations; emits advisory JSON without writing the plan.
- **FR-5**: `validate-phase-sizes.sh` exists with full bats coverage; integrates as the last step of FR-1 when `--enforce-phase-budget` is passed; integrates as a verification-checklist item in the rewritten SKILL.md (Phase 6).
- **FR-6**: `workflow-state.sh resolve-tier` accepts `--phase N --plan-file <path>`; per-phase tier replaces the workflow-complexity input for `implementing-plan-phases` forks; bats coverage for happy path + every malformed-flag exit; `modelSelections` schema extended with per-phase keying.
- **FR-7**: `implementing-plan-phases` baseline lowered to `haiku`; existing override chain semantics unchanged; bats coverage updated.
- **FR-8**: `prepare-fork.sh` forwards `--phase`/`--plan-file` to `resolve-tier` for `implementing-plan-phases` forks; FR-14 console echo line includes `phase=<N>=<phase-tier>`; bats coverage extended.
- **FR-9**: post-plan classifier replaced with `max`-of-per-phase-tiers; upgrade-only invariant honoured; bats coverage extended.
- **FR-10**: `references/model-selection.md` rewritten — the combined Edge Case 8 limitation is retired, the Haiku-floor caution is re-framed, the `modelSelections` migration note is added, cross-references to FR-3 / FR-6 / FR-9 are included.
- **NFR-4**: `creating-implementation-plans/SKILL.md` Quick Start collapses to single-line script invocations; Verification Checklist updated; net token reduction ~550–750 tok per plan creation.
- **NFR-5**: pre-existing state file (created before FR-6 ships) loads cleanly without manual migration; pre-existing plan without `**ComplexityOverride:**` lines validates without warnings under FR-3 / FR-5; pre-existing plan without `**Depends on:**` lines validates clean under FR-2.
- **NFR-6**: cross-references in `references/step-execution-details.md` and `references/forked-steps.md` updated to point to the rewritten `references/model-selection.md` section; the plugin-level README lists FR-1 through FR-5 with one-line purposes.
- **End-to-end**: a 4-phase synthetic plan demonstrates per-phase tier resolution working through the full pre-fork ceremony; at least one phase resolves below Opus; the FR-14 echo line carries the per-phase suffix.
- **Self-bootstrap demo**: Phase 5 of this plan (the per-phase classifier wiring) scores itself against FR-3 in Phase 6 manual smoke and demonstrates per-phase tier resolution on its own implementation.
- **Regression**: `npm test` and `npm run validate` pass on the release branch; existing FEAT-014 / FEAT-021 / FEAT-026 / FEAT-027 behaviour is unchanged.

## Code Organization

```
plugins/lwndev-sdlc/
├── scripts/
│   ├── prepare-fork.sh                                    # MODIFIED (Phase 5): --phase/--plan-file forwarding, FR-14 echo extension
│   ├── tests/
│   │   └── prepare-fork.bats                              # EXTENDED (Phase 5): per-phase forwarding, echo-line suffix
│   └── README.md                                          # MODIFIED (Phase 6, optional): script-table entries for FR-1–FR-5
└── skills/
    ├── creating-implementation-plans/
    │   ├── SKILL.md                                       # REWRITTEN (Phase 6): Quick Start collapses to script invocations
    │   ├── README.md                                      # NEW or MODIFIED (Phase 6): lists FR-1–FR-5 scripts
    │   ├── assets/                                        # UNCHANGED
    │   ├── references/                                    # UNCHANGED
    │   └── scripts/                                       # NEW directory (Phase 1)
    │       ├── render-plan-scaffold.sh                    # NEW (Phase 1): FR-1
    │       ├── validate-plan-dag.sh                       # NEW (Phase 2): FR-2
    │       ├── phase-complexity-budget.sh                 # NEW (Phase 2): FR-3
    │       ├── split-phase-suggest.sh                     # NEW (Phase 3): FR-4
    │       ├── validate-phase-sizes.sh                    # NEW (Phase 3): FR-5
    │       └── tests/                                     # NEW directory (Phase 1)
    │           ├── fixtures/                              # NEW directory (Phase 1, extended Phases 2–3)
    │           │   ├── feat-fixture-single.md             # Phase 1
    │           │   ├── feat-fixture-multi-a.md            # Phase 1
    │           │   ├── feat-fixture-multi-b.md            # Phase 1
    │           │   ├── dag-valid-plan.md                  # Phase 2
    │           │   ├── dag-cycle-plan.md                  # Phase 2
    │           │   ├── dag-fenced-plan.md                 # Phase 2
    │           │   ├── budget-mixed-plan.md               # Phase 2
    │           │   ├── budget-override-plan.md            # Phase 2
    │           │   ├── split-overflow-plan.md             # Phase 3
    │           │   └── split-tiny-plan.md                 # Phase 3
    │           ├── render-plan-scaffold.bats              # NEW (Phase 1, extended Phase 3)
    │           ├── validate-plan-dag.bats                 # NEW (Phase 2)
    │           ├── phase-complexity-budget.bats           # NEW (Phase 2)
    │           ├── split-phase-suggest.bats               # NEW (Phase 3)
    │           └── validate-phase-sizes.bats              # NEW (Phase 3)
    └── orchestrating-workflows/
        ├── references/
        │   ├── model-selection.md                         # REWRITTEN (Phase 6): FR-10 per-phase classification path
        │   ├── step-execution-details.md                  # MODIFIED (Phase 6): NFR-6 cross-references
        │   └── forked-steps.md                            # MODIFIED (Phase 6): NFR-6 cross-references
        └── scripts/
            └── workflow-state.sh                          # MODIFIED (Phases 4 + 5): _step_baseline, resolve-tier, classify-post-plan, record-model-selection
scripts/__tests__/
└── workflow-state.test.ts                                 # EXTENDED (Phases 4 + 5): per-phase resolution, classify-post-plan max semantics
requirements/features/
└── FEAT-014-adaptive-model-selection.md                   # MODIFIED (Phase 6): post-FEAT-029 cross-reference note
```
