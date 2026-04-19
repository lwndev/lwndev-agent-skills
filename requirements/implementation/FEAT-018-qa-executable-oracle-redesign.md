# Implementation Plan: QA Redesign — Executable Oracle + Adversarial Persona + Independent Planning

## Overview

Redesign `documenting-qa` and `executing-qa` so that QA produces a real engineering signal instead of a structurally-forced PASS. The redesign addresses three root causes identified in #163 and #170: no independent oracle (the plan-builder and verifier share the same ground truth), string-graded stop hooks (blocking on regex phrases rather than artifact presence), and a closed planning loop (the planning agent reads the same requirements doc that drove implementation).

The new design introduces three independently-swappable layers: a **capability-discovery module** (detects what is testable in the consumer repo), a **persona module** (ships the `qa` adversarial tester overlay; extensible without restructuring), and an **executable-oracle runner** (writes and runs real tests; graded on artifact structure, not phrases). A prerequisite architectural decision (FR-11) is locked in Phase 0: the test-plan reconciliation step in `reviewing-requirements` is removed from the orchestrator chains (Option B), because the new no-spec-during-planning design deliberately diverges the plan from the requirements doc, making "does plan match spec?" the wrong question. The FR-5 bidirectional delta already provides the reconciliation signal.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-018 | [#170](https://github.com/lwndev/lwndev-marketplace/issues/170) | [FEAT-018-qa-executable-oracle-redesign.md](../features/FEAT-018-qa-executable-oracle-redesign.md) | High | High | Pending |

**Related issues:** [#163](https://github.com/lwndev/lwndev-marketplace/issues/163) (closed, diagnostic predecessor), [#169](https://github.com/lwndev/lwndev-marketplace/issues/169) (open, bookkeeping migration — independent, out of scope)

---

## Recommended Build Sequence

The phase order enforces a strict dependency graph: (0) lock the architectural decision and enumerate scope; (1) build the capability-discovery module in isolation with full unit tests; (2) build the persona module and loader; (3) define the version-2 artifact schema and rewrite both stop hooks — these are the gate mechanisms everything else depends on; (4) rewrite `documenting-qa/SKILL.md` consuming layers 1–3; (5) rewrite `executing-qa/SKILL.md` consuming layers 1–3; (6) rewrite or replace `qa-verifier.md`; (7) execute the orchestrator chain-table renumbering unlocked by the Phase 0 FR-11 Option B decision; (8) integration test pass and NFR-5 smoke run as the final gate. No phase may begin until its dependencies are complete.

---

### Phase 0 — FR-11 Decision Lock and Orchestrator Scope Enumeration
**Feature:** [FEAT-018](../features/FEAT-018-qa-executable-oracle-redesign.md) | [#170](https://github.com/lwndev/lwndev-marketplace/issues/170)
**Status:** ✅ Complete
**Phase Dependencies:** None — this is the entry point.

#### Rationale

FR-11 is explicitly deferred to planning time. Two phases (4 and 7) have mutually exclusive implementations depending on whether Option A (repurpose the test-plan reconciliation mode) or Option B (remove it) is chosen. The plan cannot be executed ambiguously — the decision must be committed before any implementation begins.

**Recommendation: Option B — Remove the test-plan reconciliation step.**

Reasoning:
- The new `documenting-qa` planning prompt (FR-4) deliberately builds the plan from user summary + code context + capability report, **without** reading the requirements doc. The plan organizes scenarios by adversarial dimension, not by FR row. This means the plan will always diverge from the spec — that divergence is the point.
- Asking "does the plan match the spec?" (the test-plan reconciliation mode's current question) is therefore the wrong question. A plan that maps every FR row is a bad plan under the new design.
- The FR-5 bidirectional delta (coverage-surplus + coverage-gap) already provides the reconciliation signal — it is produced after every `executing-qa` run and appears in the version-2 results artifact. This is a higher-quality signal than a pre-execution checklist comparison.
- FEAT-017 established the pattern for removing a reconciliation step from the orchestrator chains. The same surgical approach applies here: delete the row, renumber downstream steps, sweep all references.

**Tradeoff acknowledged:** Option A (repurpose the mode to check FR-4 structural rules) would add a structural gating step — verifying that the plan is organized by dimension, that priorities are assigned, that the persona overlay is composed. This is a legitimate quality gate. However, the stop hook (Phase 3) already enforces these structural rules on the plan artifact directly, making a separate reviewing step redundant. Option A is re-openable as a follow-up feature if the stop hook proves insufficient; the plan baseline is Option B.

**Orchestrator chain-length impact (FR-12):**
- Feature chain: was `6 + N + 4`, becomes `5 + N + 4` (drop step 6 "Reconcile test plan"). Feature total for N=3 phases: 12 steps (was 13).
- Chore chain: was 8 steps, becomes 7 steps (drop step 4 "Reconcile test plan").
- Bug chain: was 8 steps, becomes 7 steps (same transformation as chore).

**Files requiring renumbering (scope enumeration for Phase 7):**
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — feature/chore/bug chain tables, chain-length prose, main-context step headings, Fork Step-Name Map, Findings Handling scope line, Persisting Findings chain-step-to-index table
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` — delete fork-instruction blocks for test-plan reconciliation steps in all three chains; renumber downstream step headings
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/verification-and-relationships.md` — verification checklist items, chain-length assertions, skill-relationship tables
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` — grep-swept for stale step references
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — step generators (`generate_feature_steps`, `generate_chore_steps`, `generate_bug_steps`) drop the "Reconcile test plan" step entry
- `scripts/__tests__/orchestrating-workflows.test.ts` — chain-length assertions, step-name arrays, main-context-steps test description
- `scripts/__tests__/workflow-state.test.ts` — state-file fixtures, step-length assertions
- `CLAUDE.md` — workflow-chain descriptions in the "Existing Skills" section

#### Implementation Steps

1. Read this plan document and confirm the FR-11 Option B decision is recorded here — no file edits needed in Phase 0 itself. The plan document is the deliverable.
2. Enumerate and record the exact grep tokens to sweep in Phase 7: `Reconcile test plan`, `test-plan reconciliation`, `test-plan` (in mode-argument context), `6+N+4` (feature chain length), `step 6` (feature reconcile step), `step 4` (chore/bug reconcile step), `8 steps` (chore/bug chain length), `fixed 8 steps`, `steps 2, 4` (findings-handling scope), `generate_feature_steps`, `generate_chore_steps`, `generate_bug_steps`.
3. Confirm `reviewing-requirements/SKILL.md` test-plan reconciliation mode is **preserved unchanged** — only the orchestrator invocation is removed. The mode remains invocable standalone. (Parallel to FEAT-017's treatment of the code-review mode.)

#### Deliverables

- [x] This plan document committed with FR-11 Option B decision recorded, tradeoff documented, and Phase 7 scope enumerated.

---

### Phase 1 — Capability Discovery Module
**Feature:** [FEAT-018](../features/FEAT-018-qa-executable-oracle-redesign.md) | [#170](https://github.com/lwndev/lwndev-marketplace/issues/170)
**Status:** ✅ Complete
**Phase Dependencies:** Phase 0 (scope locked).

#### Rationale

The capability-discovery module is a pure, side-effect-free component: given a consumer repo root, it produces a JSON capability report. Building it first with full unit tests means (a) it is testable in complete isolation before any skill integration touches it, (b) Phases 4 and 5 can reference the report schema without designing it in-flight, and (c) edge cases 1, 2, and 6 (from the requirements) are exercised by unit tests that run on every `npm test` invocation, giving early regression coverage.

The module ships as a shell script rather than a TypeScript module because the skills themselves run in shell contexts and the existing `stop-hook.sh` pattern establishes that shell scripts are the correct mechanism for skill-adjacent tooling.

#### Implementation Steps

1. **Create `plugins/lwndev-sdlc/skills/documenting-qa/scripts/capability-discovery.sh`** (executable, `#!/usr/bin/env bash`, `set -euo pipefail`). The script accepts one argument: the consumer repo root path. It exits 0 on success (including graceful degradation to exploratory-only), non-zero only on fatal errors (e.g., the root path does not exist).

2. **Implement detection logic in deterministic order** (vitest → jest → pytest → go test):
   - `vitest`: check `package.json` for `"vitest"` key in `dependencies` or `devDependencies`, or for the existence of `vitest.config.{ts,js,mjs}`. Use `jq` for package.json parsing; use `test -f` for config file existence.
   - `jest`: check `package.json` for `"jest"` key, or for `jest.config.{ts,js,mjs,json}`.
   - `pytest`: check for `pyproject.toml` containing `pytest` (grep), `pytest.ini` existence, or `tests/` directory containing `test_*.py` files.
   - `go test`: check for `go.mod` existence AND at least one `*_test.go` file (use `find` with a max depth of 5 to avoid reading the full tree on large repos — NFR, edge case 10).
   - Multi-framework detection (edge case 1): when a second framework signal is found after the first match, append a warning note to the `notes` array but do not change the already-selected framework.

3. **Implement package-manager detection** (`npm`, `yarn`, `pnpm`) for the npm-family frameworks: check for `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` in that order (first match wins).

4. **Implement test-command resolution**: if `package.json` `scripts.test` exists, use its value. Otherwise, fall back to framework-standard invocations: `npx vitest run`, `npx jest`, `pytest`, `go test ./...`. Log the fallback as a note (edge case 2).

5. **Implement test-directory creation detection** (edge case 6): if a framework is detected but no test directory exists (`__tests__/` for jest-family, `tests/` for pytest, no `_test.go` files for go), append a note: `"no test directory found; skill will create <convention> directory"`. Do not create the directory from this script — that is the skill's responsibility.

6. **Output the capability report as JSON to stdout** using `jq -n` with `--arg` / `--argjson` to avoid shell-injection risks. The output schema:
   ```json
   {
     "id": "${ID}",
     "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
     "mode": "test-framework" | "exploratory-only",
     "framework": "vitest" | "jest" | "pytest" | "go-test" | null,
     "packageManager": "npm" | "yarn" | "pnpm" | null,
     "testCommand": "<string>" | null,
     "language": "typescript" | "javascript" | "python" | "go" | null,
     "notes": ["<string>", ...]
   }
   ```
   When no framework is detected: `mode: "exploratory-only"`, `framework: null`, `packageManager: null`, `testCommand: null`. A note is appended: `"No supported framework detected. Detection attempted: vitest, jest, pytest, go test."`.

7. **Write the report to `/tmp/qa-capability-{ID}.json`** (the ID is passed as the first argument, the consumer repo root as the second). The `/tmp` path ensures recomputation on every run (stale reports cannot persist across sessions).

8. **Create `scripts/__tests__/capability-discovery.test.ts`** using the existing vitest test harness pattern (similar to `stop-hook` tests: create a `tmpdir` fixture, write detection signals, invoke the script, read stdout). Write one `describe` block per framework plus the no-framework case:
   - `describe('vitest detection')`: fixture with `package.json` containing `"vitest": "^1.0.0"` in `devDependencies` → asserts `mode: "test-framework"`, `framework: "vitest"`, `packageManager: "npm"` (given `package-lock.json`), `testCommand: "npm test"` (given a `scripts.test` entry).
   - `describe('vitest config-file detection')`: fixture with `vitest.config.ts` present but no `package.json` vitest dep → asserts `framework: "vitest"`.
   - `describe('jest detection')`: fixture with `jest.config.js` → asserts `framework: "jest"`.
   - `describe('pytest detection')`: fixture with `pytest.ini` → asserts `framework: "pytest"`, `language: "python"`.
   - `describe('go-test detection')`: fixture with `go.mod` + a `foo_test.go` file → asserts `framework: "go-test"`, `language: "go"`.
   - `describe('no-framework fallback')`: fixture with no detection signals → asserts `mode: "exploratory-only"`, `framework: null`.
   - `describe('multi-framework detection — edge case 1')`: fixture with both vitest and jest signals → asserts `framework: "vitest"`, `notes` array contains a warning string.
   - `describe('no test-script fallback — edge case 2')`: fixture with vitest dep but no `scripts.test` → asserts `testCommand: "npx vitest run"`.
   - `describe('no test directory — edge case 6')`: fixture with jest but no `__tests__/` → asserts `notes` contains `"no test directory found"`.
   - `describe('large repo — edge case 10')`: fixture with 100 nested directories and a `_test.go` at depth 6 → asserts detection completes in <5 seconds (use `Date.now()` timing in the test).

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/documenting-qa/scripts/capability-discovery.sh` — executable, all detection paths implemented, JSON emitted to stdout and `/tmp/qa-capability-{ID}.json`
- [x] `scripts/__tests__/capability-discovery.test.ts` — 10 test cases covering all FR-1 detection paths, edge cases 1/2/6/10, and the no-framework fallback

---

### Phase 2 — Persona Module and Loader
**Feature:** [FEAT-018](../features/FEAT-018-qa-executable-oracle-redesign.md) | [#170](https://github.com/lwndev/lwndev-marketplace/issues/170)
**Status:** Pending
**Phase Dependencies:** Phase 0 (scope locked). Independent of Phase 1.

#### Rationale

The persona module is a content layer (a prompt fragment) plus a loader mechanism (a shell helper that reads the fragment and validates it). Building it before the skill rewrites means the rewrites can reference a stable, tested interface rather than designing it in-flight. The loader's "missing persona = abort with clear error" behavior (edge case 8, NFR-2) must be in place before the stop hooks in Phase 3 can test for it. The directory structure established here (FR-7) is the extensibility contract for future personas.

The loader ships as a shell function in a sourced helper (`persona-loader.sh`) rather than being inlined into each stop hook, keeping the implementation DRY across `documenting-qa` and `executing-qa`.

#### Implementation Steps

1. **Create the persona directory structure** in both skills:
   - `plugins/lwndev-sdlc/skills/documenting-qa/personas/` (directory)
   - `plugins/lwndev-sdlc/skills/executing-qa/personas/` (directory)
   - A shared location is considered but rejected: the two skills may diverge in persona needs (e.g., `executing-qa` needs execution-oriented directives), and the per-skill directory makes the composition point unambiguous. For the first cut, the `qa.md` content is identical in both locations.

2. **Create `plugins/lwndev-sdlc/skills/documenting-qa/personas/qa.md`** with the adversarial tester overlay. Required content (FR-6):
   ```markdown
   ---
   name: qa
   description: Generic adversarial tester — probes failure modes the implementation likely did not anticipate.
   ---

   # QA Persona: Adversarial Tester

   You are an adversarial software tester. Your goal is to find bugs, not to confirm correctness.
   Do not read the requirements document during plan construction. Build your plan from the user-facing
   summary, the code diff, and the capability report only.

   ## Dimensions to probe

   ### Inputs
   Boundary values, unicode, empty/null, oversized payloads, malformed formats, injection attempts.
   ...

   ### State transitions
   Cancel mid-flow, double-click, back/forward navigation, stale tabs, interrupted network mid-submit.
   ...

   ### Environment
   Offline, slow network, cold cache, permission-denied filesystems, missing environment variables.
   ...

   ### Dependency failure
   API 500s, timeouts, rate limits, database disconnects, third-party-service outages.
   ...

   ### Cross-cutting
   Accessibility (keyboard nav, screen reader, color contrast), i18n (RTL, non-ASCII),
   concurrency (two clients, race conditions, shared state), permissions and authorization.
   ...

   ## Empty-findings directive
   If your plan or run produces zero findings for any applicable dimension, you MUST explicitly justify
   why that dimension is not applicable to the change at hand. A plan with an applicable dimension
   that has no scenarios and no justification is invalid and will fail stop-hook validation.
   ```

3. **Create `plugins/lwndev-sdlc/skills/executing-qa/personas/qa.md`** with identical content to the documenting-qa version. Note in a comment: `# Shared content — update both files together until a shared-personas mechanism is introduced`.

4. **Create `plugins/lwndev-sdlc/skills/documenting-qa/scripts/persona-loader.sh`** (sourced helper, not executed directly). Exports a single function `load_persona(persona_name, skill_dir)`:
   - Constructs the path: `"${skill_dir}/personas/${persona_name}.md"`
   - Checks file existence: if missing, emit to stderr: `Error: persona file not found at <path>. Available personas: $(ls "${skill_dir}/personas/" 2>/dev/null | tr '\n' ' ')` and return exit code 1.
   - Validates frontmatter: the file must contain a `---` block at line 1 with a `name:` field. If malformed, emit: `Error: persona file at <path> has missing or malformed frontmatter (expected: name: field).` and return exit code 1.
   - On success, prints the persona file's full content to stdout (for composition into the skill's prompt context).

5. **Create `plugins/lwndev-sdlc/skills/executing-qa/scripts/persona-loader.sh`** — identical to the documenting-qa version (same DRY note).

6. **Create `scripts/__tests__/persona-loader.test.ts`** covering three cases:
   - `describe('persona present and well-formed')`: fixture with `personas/qa.md` containing valid frontmatter → `load_persona qa <dir>` exits 0 and prints the file content.
   - `describe('persona missing — edge case 8')`: fixture with empty `personas/` directory → `load_persona qa <dir>` exits 1 and stderr contains `Error: persona file not found`.
   - `describe('persona malformed frontmatter — edge case 8 variant')`: fixture with `personas/qa.md` missing the frontmatter `---` block → exits 1 and stderr contains `Error: persona file`.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/documenting-qa/personas/qa.md` — adversarial tester persona overlay covering all 5 FR-6 dimensions plus the empty-findings directive
- [ ] `plugins/lwndev-sdlc/skills/executing-qa/personas/qa.md` — same content (cross-referenced)
- [ ] `plugins/lwndev-sdlc/skills/documenting-qa/scripts/persona-loader.sh` — `load_persona` function with present/missing/malformed handling
- [ ] `plugins/lwndev-sdlc/skills/executing-qa/scripts/persona-loader.sh` — same implementation
- [ ] `scripts/__tests__/persona-loader.test.ts` — 3 test cases covering present, missing, and malformed

---

### Phase 3 — Artifact Schema + Stop-Hook Rewrite
**Feature:** [FEAT-018](../features/FEAT-018-qa-executable-oracle-redesign.md) | [#170](https://github.com/lwndev/lwndev-marketplace/issues/170)
**Status:** Pending
**Phase Dependencies:** Phase 0 (schema version decision locked in the plan).

#### Rationale

The stop hooks are the most security-critical component of this redesign. The current hooks gate on regex phrases in the last assistant message — which is precisely the failure mode the redesign attacks. The new hooks gate on artifact structure. They must be in place before the skill rewrites in Phases 4 and 5 produce artifacts — the hooks define what "done" means for each skill.

This phase is placed third (before the skill rewrites) because: (a) the hook tests can be written against synthetic fixture artifacts without needing the full skill machinery; (b) having passing hook tests gives Phase 4 and 5 a contract to fulfill; (c) if the hook logic is wrong, it is much cheaper to fix in isolation than after a full skill rewrite.

The version-2 artifact schema is also defined here. The existing version-1 artifacts (34 files in `qa/test-results/`) are NOT touched (NFR-3, FR-10). The `version` frontmatter field distinguishes them.

#### Implementation Steps

##### Artifact Schema (version 2)

1. **Document the version-2 plan artifact schema** at `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template-v2.md` (new file). Required sections per FR-4 and FR-9:
   ```markdown
   ---
   id: FEAT-XXX
   version: 2
   timestamp: 2026-04-19T14:22:00Z
   persona: qa
   ---

   ## User Summary
   {2-5 sentence description of what the feature claims to do, in user terms}

   ## Capability Report
   - Mode: test-framework | exploratory-only
   - Framework: vitest | jest | pytest | go-test | none
   - Package manager: npm | yarn | pnpm | none
   - Test command: <string> | none

   ## Scenarios (by dimension)

   ### Inputs
   {- [P0|P1|P2] <description> | mode: test-framework|exploratory | expected: <test shape>}

   ### State transitions
   {same pattern}

   ### Environment
   {same pattern}

   ### Dependency failure
   {same pattern}

   ### Cross-cutting (a11y, i18n, concurrency, permissions)
   {same pattern}

   ## Non-applicable dimensions
   {- <dimension>: <justification>}
   ```

2. **Document the version-2 results artifact schema** at `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template-v2.md` (new file). Required sections per FR-9:
   ```markdown
   ---
   id: FEAT-XXX
   version: 2
   timestamp: 2026-04-19T14:22:00Z
   verdict: PASS | ISSUES-FOUND | ERROR | EXPLORATORY-ONLY
   persona: qa
   ---

   ## Summary
   {One-line summary of the run}

   ## Capability Report
   {Copied from FR-1 capability report}

   ## Execution Results
   - Total: N
   - Passed: N
   - Failed: N
   - Errored: N
   - Exit code: 0
   - Duration: Xs
   - Test files: [qa-inputs.spec.ts, ...]

   ## Scenarios Run
   | ID | Dimension | Priority | Result | Test file |
   |-----|-----------|----------|--------|-----------|

   ## Findings
   {Per-finding: severity | dimension | title | reproduction | evidence}

   ## Reconciliation Delta
   ### Coverage beyond requirements
   {- Scenario X — not mentioned in spec}
   ### Coverage gaps
   {- FR-N / AC — no corresponding scenario in plan}
   ### Summary
   - coverage-surplus: N
   - coverage-gap: M

   ## Exploratory Mode
   {Only for EXPLORATORY-ONLY: Reason + dimensions covered}
   ```

3. **Document the version-1/version-2 split** in a comment at the top of both template files: `# Version history: version-1 artifacts have no frontmatter 'version' field. Parsers must treat absence of 'version' as version 1. New runs produce version 2.`

##### Stop-Hook Rewrites

4. **Rewrite `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh`**. Remove all regex phrase-matching. New validation logic:
   - Guard: if `ACTIVE_FILE` does not exist, exit 0 (unchanged).
   - Guard: if `stop_hook_active == true`, remove active file and exit 0 (unchanged).
   - Parse `last_assistant_message` from stdin JSON (unchanged).
   - **New**: instead of grep on message text, check for the artifact file. Determine the ID from the state file path context or from a message pattern `QA-results-{ID}.md`. If no ID can be determined from the message, block with: `"Stop hook: could not determine QA results artifact path from message. Ensure the results file path is mentioned in your final message."` and exit 2.
   - **Validate artifact existence**: check `qa/test-results/QA-results-{ID}.md` exists. If not: `"Stop hook: results artifact qa/test-results/QA-results-{ID}.md does not exist."` exit 2.
   - **Validate frontmatter `## Verdict` section**: use `grep -m1 "^## Verdict"` in the artifact. If missing: `"Stop hook: artifact is missing '## Verdict' section."` exit 2.
   - **Validate verdict value**: extract the line after `## Verdict` and check it matches `^(PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY)$`. If not: `"Stop hook: artifact verdict is not one of PASS, ISSUES-FOUND, ERROR, EXPLORATORY-ONLY."` exit 2.
   - **Validate `## Capability Report` section**: must be present. If not: `"Stop hook: artifact is missing '## Capability Report' section."` exit 2.
   - **Conditional validation for PASS/ISSUES-FOUND**: `## Execution Results` section must be present and must contain `Total:`, `Passed:`, `Failed:` lines. If not: `"Stop hook: PASS/ISSUES-FOUND verdict requires '## Execution Results' with Total/Passed/Failed counts."` exit 2.
   - **Conditional validation for EXPLORATORY-ONLY**: `## Exploratory Mode` section must be present and contain a `Reason:` line. If not: `"Stop hook: EXPLORATORY-ONLY verdict requires '## Exploratory Mode' section with Reason."` exit 2.
   - **Validate per-dimension coverage** (FR-6, FR-8): `## Scenarios Run` section must be present OR `## Exploratory Mode` must be present (for EXPLORATORY-ONLY runs). The artifact must contain at least one of: a populated `## Scenarios Run` table with at least one row, or `## Exploratory Mode` content with non-empty dimension coverage. If the artifact has only the section header and no rows, block with: `"Stop hook: no scenario coverage found. Populate '## Scenarios Run' or provide dimension coverage in '## Exploratory Mode'."` exit 2.
   - On all validations passing: remove active file, exit 0.

5. **Rewrite `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh`**. New validation logic:
   - Guards: same active-file and stop_hook_active checks.
   - **New**: check for plan artifact `qa/test-plans/QA-plan-{ID}.md`. Determine ID same as above.
   - **Validate `## User Summary`** section: must be present and non-empty (more than the template placeholder). If not: `"Stop hook: plan artifact is missing '## User Summary' section."` exit 2.
   - **Validate `## Capability Report`** section: must be present. If not: `"Stop hook: plan artifact is missing '## Capability Report' section."` exit 2.
   - **Validate `## Scenarios (by dimension)`** section: must contain at least one of the five dimension subsections (`### Inputs`, `### State transitions`, `### Environment`, `### Dependency failure`, `### Cross-cutting`). If not: `"Stop hook: plan artifact is missing dimension sections under '## Scenarios (by dimension)'."` exit 2.
   - **Validate dimension coverage** (FR-8): check that every dimension section has either at least one scenario line (matching `- \[P[0-2]\]`) OR a corresponding entry in `## Non-applicable dimensions`. If a dimension section is empty and not listed as non-applicable: `"Stop hook: dimension '<X>' has no scenarios and is not listed as non-applicable."` exit 2.
   - **Validate no requirements-doc reading**: the plan artifact must NOT contain any literal FR-N pattern (`FR-\d+`) in its `## Scenarios` sections (FR-4). If found: `"Stop hook: plan contains 'FR-N' references in Scenarios section. The planning agent must not copy FR rows from the requirements doc."` exit 2. (Exception: `## Reconciliation Delta` and `## Non-applicable dimensions` sections may contain FR references — scope the grep to the Scenarios sections only.)
   - **Validate version-2 frontmatter**: `version: 2` must be present in the plan frontmatter. If not: `"Stop hook: plan artifact is missing 'version: 2' in frontmatter."` exit 2.
   - On all validations passing: remove active file, exit 0.

6. **Update `scripts/__tests__/executing-qa.test.ts`** — replace existing stop-hook behavioral tests with new artifact-structure-based tests:
   - `it('exits 0 when a well-formed PASS artifact exists and is referenced in the message')`: create fixture `qa/test-results/QA-results-FEAT-001.md` with all required sections, verdict `PASS`, message `"QA complete. Results at qa/test-results/QA-results-FEAT-001.md."` → exit 0.
   - `it('exits 0 when verdict is ISSUES-FOUND with Execution Results section')`: same with `ISSUES-FOUND` verdict.
   - `it('exits 0 when verdict is ERROR with Execution Results section')`: same with `ERROR` verdict (no Execution Results required for ERROR).
   - `it('exits 0 when verdict is EXPLORATORY-ONLY with Exploratory Mode section')`: fixture has `## Exploratory Mode` with `Reason:` line → exit 0.
   - `it('exits 2 when artifact does not exist')`: no fixture file, message references it → exit 2, stderr contains `does not exist`.
   - `it('exits 2 when artifact is missing ## Verdict section')`: fixture with no `## Verdict` → exit 2.
   - `it('exits 2 when verdict value is not an allowed enum')`: fixture with `## Verdict\nverdict: pass` (lowercase) → exit 2, stderr contains `not one of`.
   - `it('exits 2 when PASS artifact is missing ## Execution Results')`: PASS verdict but no `## Execution Results` section → exit 2.
   - `it('exits 2 when EXPLORATORY-ONLY artifact is missing ## Exploratory Mode')`: EXPLORATORY-ONLY verdict but no `## Exploratory Mode` → exit 2.
   - `it('exits 2 when artifact has no scenario coverage')`: `## Scenarios Run` present but empty table → exit 2.
   - `it('exits 0 when state file is absent (skill not active)')`: no state file → exit 0 regardless of artifact state.
   - `it('exits 0 when stop_hook_active is true')`: state file present but bypass flag set → exit 0.
   - Keep existing `it('exits 0 on empty stdin')` and `it('exits 0 on malformed JSON')` tests.
   - Update `it('script checks for both verification and reconciliation patterns')` to instead assert: `scriptContent contains 'Verdict'` and `scriptContent contains 'Capability Report'`.

7. **Update `scripts/__tests__/documenting-qa.test.ts`** — replace stop-hook behavioral tests with plan-artifact-structure-based tests (parallel to above, covering the documenting-qa stop hook's new validation logic):
   - `it('exits 0 when a well-formed v2 plan artifact exists')`: fixture with all required sections → exit 0.
   - `it('exits 2 when plan artifact does not exist')`: exit 2, stderr mentions path.
   - `it('exits 2 when plan artifact is missing ## User Summary')`: exit 2.
   - `it('exits 2 when plan artifact is missing ## Capability Report')`: exit 2.
   - `it('exits 2 when plan artifact has no dimension sections')`: exit 2.
   - `it('exits 2 when plan artifact has empty dimension section with no non-applicable justification')`: exit 2, stderr mentions the dimension name.
   - `it('exits 2 when plan artifact contains FR-N references in Scenarios section')`: exit 2, stderr mentions `FR-N references`.
   - `it('exits 2 when plan artifact is missing version: 2 in frontmatter')`: exit 2.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template-v2.md` — version-2 plan artifact schema with version-1/version-2 split note
- [ ] `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template-v2.md` — version-2 results artifact schema with same split note
- [ ] `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` — rewritten to validate artifact structure, not regex-match phrases; all FR-8 conditions implemented
- [ ] `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` — rewritten to validate plan artifact structure; FR-4 no-spec enforcement; version-2 frontmatter check
- [ ] `scripts/__tests__/executing-qa.test.ts` — stop-hook behavioral tests updated to artifact-structure assertions (12 new cases replacing 8 phrase-matching cases)
- [ ] `scripts/__tests__/documenting-qa.test.ts` — stop-hook behavioral tests updated (8 new artifact-structure cases)

---

### Phase 4 — Rewrite `documenting-qa/SKILL.md`
**Feature:** [FEAT-018](../features/FEAT-018-qa-executable-oracle-redesign.md) | [#170](https://github.com/lwndev/lwndev-marketplace/issues/170)
**Status:** Pending
**Phase Dependencies:** Phases 1 (capability discovery script in place), 2 (persona loader in place), 3 (stop hook and artifact schema defined).

#### Rationale

The `documenting-qa` skill rewrite consumes all three lower layers: capability discovery (Phase 1), persona loader (Phase 2), and the version-2 plan artifact schema (Phase 3). The rewrite is a complete replacement of the planning logic — the old "read requirements doc, map FR rows to test entries" approach is replaced by "run discovery, load persona, build adversarial scenarios from code context only." The stop hook written in Phase 3 enforces the contract; the skill rewrite must satisfy that contract.

The `qa-verifier` subagent is NOT used in the rewritten `documenting-qa`. The old plan-completeness loop (Ralph loop with qa-verifier) is replaced by the stop hook's structural validation. The `qa-verifier` is addressed in Phase 6.

#### Implementation Steps

1. **Rewrite `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`** — full replacement. Preserve frontmatter fields (`name`, `description`, `allowed-tools`, `hooks`). Add `Bash` to `allowed-tools` (the skill now invokes `capability-discovery.sh` and `persona-loader.sh`). Keep the stop hook command path unchanged.

2. **New Step 1 — Run capability discovery**: invoke `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/scripts/capability-discovery.sh {ID} {consumer_repo_root}`. Read the output from `/tmp/qa-capability-{ID}.json`. If the script exits non-zero, log the error and proceed as `mode: exploratory-only`. The consumer repo root is the directory containing the `package.json` / `go.mod` / `pyproject.toml` etc. — for this plugin, it is the working directory of the consumer project (not the plugin root). Document how to determine it: `pwd` at skill invocation time.

3. **New Step 2 — Load persona**: invoke `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/scripts/persona-loader.sh qa ${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa`. If it exits non-zero, abort with the error message — do not silently substitute a default persona (NFR-2, edge case 8).

4. **New Step 3 — Gather code context (no requirements doc)**: the planning agent's prompt must explicitly include: `"Do NOT read requirements/features/FEAT-*.md, requirements/chores/CHORE-*.md, or requirements/bugs/BUG-*.md during this step. Build the plan from the user-facing summary and code diff only."` The user-facing summary is obtained:
   - If a PR exists: from the PR title + PR body first paragraph (read via Bash: `gh pr view {prNumber} --json title,body`).
   - If no PR: read only the `## User Story` section from the requirements doc — not the FR grid, not the ACs, not the edge cases.
   Code context: `git diff main...HEAD` output (or the PR diff).

5. **New Step 4 — Build test plan using adversarial dimensions**: compose the persona overlay (from Step 2) into the planning context. Build scenarios organized by the five FR-6 dimensions (Inputs, State transitions, Environment, Dependency failure, Cross-cutting). For each scenario: assign a priority (P0/P1/P2), specify the expected execution mode (`test-framework` or `exploratory`), and write a brief description of the expected test shape. For any dimension where no scenarios apply, write a justification in `## Non-applicable dimensions`.

6. **New Step 5 — Write plan artifact in version-2 format**: save to `qa/test-plans/QA-plan-{ID}.md` using `test-plan-template-v2.md` as the structure. Set `version: 2` in frontmatter. Populate all required sections.

7. **Remove the qa-verifier Ralph loop** from the new skill — the old completeness-verification loop is gone. The stop hook is the completeness gate. The skill should still mention in its Verification Checklist: `[ ] Plan artifact saved to qa/test-plans/QA-plan-{ID}.md with version: 2 frontmatter`.

8. **Update the `## Relationship to Other Skills` table**: remove the row `"Reconcile after QA plan creation | Use reviewing-requirements — test-plan reconciliation mode"` (consistent with FR-11 Option B decision). Keep the row for `Reconcile after PR review` as it references a different mode.

9. **Update `scripts/__tests__/documenting-qa.test.ts`** — update SKILL.md content assertions:
   - Remove `it('should document qa-verifier subagent delegation')` (the Ralph loop is gone).
   - Remove `it('should document the ralph loop pattern')` (replaced by stop-hook gate).
   - Add `it('should reference capability-discovery.sh in step instructions')`: asserts `skillMd.toContain('capability-discovery.sh')`.
   - Add `it('should forbid reading requirements docs during planning')`: asserts `skillMd.toContain('Do NOT read requirements/')`.
   - Add `it('should reference the persona loader')`: asserts `skillMd.toContain('persona-loader.sh')`.
   - Add `it('should specify version-2 artifact output')`: asserts `skillMd.toContain('version: 2')`.
   - Add `it('should include Bash in allowed-tools')`: updates the existing `should NOT include Bash` test to `should include Bash`.
   - Retain `it('should specify test plan output path format')` and `it('should include "Verification Checklist" section')`.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` — fully rewritten: capability discovery in step 1, persona load in step 2, no-spec code-context gathering in step 3, adversarial scenario planning in step 4, version-2 artifact output in step 5; Ralph loop removed; `Reconcile after QA plan creation` row removed from relationship table
- [ ] `scripts/__tests__/documenting-qa.test.ts` — SKILL.md assertions updated for new structure (qa-verifier loop tests removed; 5 new assertions for capability discovery, persona, no-spec, version-2, Bash tool)

---

### Phase 5 — Rewrite `executing-qa/SKILL.md`
**Feature:** [FEAT-018](../features/FEAT-018-qa-executable-oracle-redesign.md) | [#170](https://github.com/lwndev/lwndev-marketplace/issues/170)
**Status:** Pending
**Phase Dependencies:** Phases 1 (capability discovery), 2 (persona loader), 3 (stop hook and results schema).

#### Rationale

The `executing-qa` rewrite is the most complex: it must implement the write-and-run loop (FR-2), the exploratory fallback (FR-3), the reconciliation delta (FR-5), and the version-2 results artifact (FR-9). It depends on the same lower layers as Phase 4 but its output is the artifact that the stop hook validates. The rewrite is done in a separate phase from Phase 4 so that the planning skill and execution skill can be reviewed and tested independently.

#### Implementation Steps

1. **Rewrite `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`** — full replacement. Preserve frontmatter fields and stop hook command path. Retain `Bash` in `allowed-tools` (the skill already has it; now it also invokes capability-discovery and persona-loader).

2. **New Step 1 — Run capability discovery and load persona**: mirror Phase 4 Step 1–2 exactly. The capability report should be read from `/tmp/qa-capability-{ID}.json` if it already exists (produced by `documenting-qa` in the same session). If the file is absent or older than 1 hour (check mtime), re-run `capability-discovery.sh` to get a fresh report.

3. **New Step 2 — Load the test plan**: read `qa/test-plans/QA-plan-{ID}.md`. If it does not exist, stop with an actionable error. If the plan's `version` frontmatter field is absent or `1`, log a warning: `"Test plan is version 1 (pre-redesign). Scenario organization may differ from the new format. Proceeding in compatibility mode."` — still proceed, but the reconciliation delta (Step 5) will have reduced coverage.

4. **New Step 3 — Execute write-and-run loop (test-framework mode)**: when `capability.mode == "test-framework"`:
   a. For each P0/P1 scenario in the test plan, write a test file using the detected framework. File naming: `qa-{dimension}.spec.ts` (vitest/jest) or `test_qa_{dimension}.py` (pytest) or `qa_{dimension}_test.go` (go). Write to the framework's conventional test directory (creating it if absent per edge case 6).
   b. Execute the test command: `capability.testCommand` (or the fallback invocation). Capture stdout and stderr. Record exit code.
   c. Parse results: total tests run, passed, failed, errored, duration. For failing tests, capture the first 50 lines of failing-test output.
   d. If the runner exits non-zero with no test output (compile error, crash): set verdict `ERROR`; include the stderr in the artifact.
   e. If all written tests pass: verdict `PASS`. If any fail: verdict `ISSUES-FOUND`.
   f. Commit the written test files to the PR branch as part of the run's output (add + commit with message `qa(FEAT-{ID}): add executable QA tests from executing-qa run`).

5. **New Step 3 (exploratory fallback)**: when `capability.mode == "exploratory-only"` OR when the test-framework run cannot produce executable tests for any reason:
   - Emit a structured exploratory review covering all five FR-6 dimensions.
   - For each applicable dimension, surface at least one plausible issue or explicitly justify non-applicability.
   - Set verdict `EXPLORATORY-ONLY`.
   - Populate `## Exploratory Mode` with `Reason:` (per FR-3).

6. **New Step 4 — Run reconciliation delta (FR-5)**: after the run completes, read the requirements doc (now permitted — only the planning step forbids it). Produce:
   - `coverage-surplus`: scenarios in the test plan that do not correspond to any FR/AC/edge case in the spec.
   - `coverage-gaps`: FRs/ACs/edge cases in the spec that have no corresponding scenario in the test plan.
   - Write the delta to `## Reconciliation Delta` in the results artifact.
   - If the requirements doc is absent (edge case 7): skip the delta with a note: `"Requirements doc not found at <path>. Reconciliation delta skipped."`

7. **New Step 5 — Write version-2 results artifact**: save to `qa/test-results/QA-results-{ID}.md` using `test-results-template-v2.md`. Set `version: 2`, `verdict: <value>`, `persona: qa`. Populate all required sections. The stop hook validates this artifact — the skill must produce exactly the structure the hook expects.

8. **Remove the reconciliation loop** (the old Step 3 that reconciled requirements docs with implementation). This function is moved to issue #169 (bookkeeping migration). The only reconciliation remaining in this skill is the FR-5 delta report (coverage-surplus/coverage-gap), which is a reporting step, not a document-editing step.

9. **Update `scripts/__tests__/executing-qa.test.ts`** — update SKILL.md content assertions:
   - Remove `it('should document the verification ralph loop')` and `it('should document the reconciliation loop')` (both replaced by new structure).
   - Remove `it('should document fix behavior for failed entries')` and `it('should document preservation rules for existing documents')` (doc-editing is removed from this skill).
   - Add `it('should reference capability-discovery.sh')`: asserts `skillMd.toContain('capability-discovery.sh')`.
   - Add `it('should document test-framework mode write-and-run loop')`: asserts `skillMd.toContain('write-and-run')` or `skillMd.toContain('test-framework mode')`.
   - Add `it('should document EXPLORATORY-ONLY fallback')`: asserts `skillMd.toContain('EXPLORATORY-ONLY')`.
   - Add `it('should document reconciliation delta')`: asserts `skillMd.toContain('Reconciliation Delta')`.
   - Add `it('should document ISSUES-FOUND verdict')`: asserts `skillMd.toContain('ISSUES-FOUND')`.
   - Add `it('should specify version-2 artifact output with version frontmatter')`: asserts `skillMd.toContain('version: 2')`.
   - Update `it('should document qa-verifier subagent delegation')` — the new skill does not delegate to qa-verifier for verification; update or remove this test (the qa-verifier is used in a different capacity in Phase 6, if at all).

10. **Update test results template tests in `scripts/__tests__/executing-qa.test.ts`** — the existing `test results template` describe block reads `assets/test-results-template.md` (v1). Add a new `describe('test results template v2')` block that reads `assets/test-results-template-v2.md` and asserts the v2-specific sections: `## Verdict`, `## Capability Report`, `## Execution Results`, `## Scenarios Run`, `## Findings`, `## Reconciliation Delta`, `## Exploratory Mode`.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — fully rewritten: capability discovery + persona load in step 1; test plan load in step 2; write-and-run loop (or exploratory fallback) in step 3; reconciliation delta in step 4; version-2 results artifact in step 5; doc-editing reconciliation loop removed
- [ ] `scripts/__tests__/executing-qa.test.ts` — SKILL.md assertions updated (5 old assertions removed, 6 new assertions added); v2 template describe block added

---

### Phase 6 — Rewrite `qa-verifier.md` Agent
**Feature:** [FEAT-018](../features/FEAT-018-qa-executable-oracle-redesign.md) | [#170](https://github.com/lwndev/lwndev-marketplace/issues/170)
**Status:** Pending
**Phase Dependencies:** Phases 4 and 5 (skill rewrites define the agent's new responsibilities).

#### Rationale

The current `qa-verifier.md` agent is built around the "read the file and confirm the described condition" model — the same closed-loop that the redesign replaces. In the new design, the primary oracle is the executable runner (the skill writes and runs tests). The agent's role shifts to: (a) adversarial scenario generation assistance during planning (if needed as an Agent fork) and (b) reconciliation delta computation (diffing test plan scenarios against requirements doc entries).

**Decision**: Replace the existing `qa-verifier.md` agent with a new `qa-reconciliation-agent.md` focused on the FR-5 delta. Keep `qa-verifier.md` in place but rewrite it around the adversarial tester persona — it can serve as a consultation agent for `documenting-qa` when the skill needs a second opinion on scenario coverage.

#### Implementation Steps

1. **Rewrite `plugins/lwndev-sdlc/agents/qa-verifier.md`** — replace the "verify conditions by reading files" prompt with an adversarial-scenario-coverage agent:
   - New role: "You are an adversarial QA scenario reviewer. You review a test plan and determine whether it adequately covers the adversarial dimensions for the described feature."
   - Input: the test plan content + user-facing summary + capability report. NOT the requirements doc (consistent with FR-4).
   - Output: a structured coverage verdict: for each of the five FR-6 dimensions, mark coverage as `adequate | sparse | missing` and provide a brief rationale. End with an overall recommendation: `APPROVE` (plan is adversarially sound) or `AUGMENT` (specific gaps listed).
   - Preserve existing frontmatter fields (`model`, `tools`).

2. **Create `plugins/lwndev-sdlc/agents/qa-reconciliation-agent.md`** (new file):
   - Role: "You compute the bidirectional coverage delta between a QA test plan and a requirements document."
   - Input: the test plan content + requirements doc content.
   - Output: the FR-5 delta structure (coverage-surplus list + coverage-gaps list + summary counts).
   - This agent is invoked by `executing-qa/SKILL.md` Step 4 (Phase 5) to produce the reconciliation delta.

3. **Update `scripts/__tests__/qa-verifier.test.ts`** — existing tests validate the agent's structure (frontmatter, sections). Update to reflect the new role:
   - Replace assertions about `## Primary Mode: Direct Verification` and per-entry PASS/FAIL with assertions about dimension coverage (`Inputs`, `State transitions`, `Environment`, `Dependency failure`, `Cross-cutting`).
   - Add assertion: agent output format contains `APPROVE` or `AUGMENT`.
   - Retain frontmatter assertions (model, tools).

#### Deliverables

- [ ] `plugins/lwndev-sdlc/agents/qa-verifier.md` — rewritten around adversarial-scenario-coverage review; FR-4 compliant (no requirements-doc input)
- [ ] `plugins/lwndev-sdlc/agents/qa-reconciliation-agent.md` — new agent for FR-5 delta computation
- [ ] `scripts/__tests__/qa-verifier.test.ts` — updated to reflect new agent role and output format

---

### Phase 7 — Orchestrator Chain-Table Changes (FR-11 Option B)
**Feature:** [FEAT-018](../features/FEAT-018-qa-executable-oracle-redesign.md) | [#170](https://github.com/lwndev/lwndev-marketplace/issues/170)
**Status:** Pending
**Phase Dependencies:** Phase 0 (FR-11 decision locked). Logically independent of Phases 1–6, but should land before Phase 8 so the smoke run uses accurate chain tables.

#### Rationale

This phase mirrors FEAT-017's pattern exactly: the test-plan reconciliation step (feature step 6, chore/bug step 4) is removed from all three chains. The orchestrator chain tables must reflect the new step positions before the NFR-5 smoke run in Phase 8, so that a real workflow produces accurate state files.

The scope enumeration from Phase 0 is the work-item list for this phase. Line-number anchors are intentionally omitted from the steps below — locate changes by content (grep tokens from Phase 0) rather than line number, as edits from Phases 4–6 may have shifted lines.

#### Implementation Steps

1. **Edit `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — feature chain table**: delete the row `| 6 | Reconcile test plan | reviewing-requirements | fork |`. Renumber downstream rows: `7…6+N` → `6…5+N`; `6+N+1` → `5+N+1`; `6+N+2` → `5+N+2`; `6+N+3` → `5+N+3`; `6+N+4` → `5+N+4`. Update the chain-length prose from "has 6 + N + 4 steps" to "has 5 + N + 4 steps".

2. **Edit the chore chain table**: delete the `| 4 | Reconcile test plan | reviewing-requirements | fork |` row. Renumber: `5 → 4`, `6 → 5`, `7 → 6`, `8 → 7`. Update "fixed 8 steps" to "fixed 7 steps".

3. **Edit the bug chain table**: same transformation as the chore chain (delete step 4, renumber 5→4 through 8→7, update prose).

4. **Update Feature Chain Main-Context Steps heading**: `(Steps 1, 5, 6+N+3)` → `(Steps 1, 4, 5+N+3)`. Step 5 `documenting-qa` becomes Step 4; Step `6+N+3 executing-qa` becomes Step `5+N+3`.

5. **Update Chore/Bug Chain main-context step headings**: `Step 3 — documenting-qa` becomes `Step 3` (unchanged — was step 3, stays step 3 because only step 4 is deleted). `Step 7 — executing-qa` becomes `Step 6`. Wait — confirm current chore chain numbering before editing: `1=doc-chores, 2=review-std, 3=doc-qa, 4=reconcile(removed), 5→4=exec-chores, 6→5=PAUSE, 7→6=exec-qa, 8→7=finalize`. So `Step 7 — executing-qa` becomes `Step 6 — executing-qa`.

6. **Update Fork Step-Name Map row for `reviewing-requirements`**: change the step list to remove the test-plan reconciliation call site. Update the Findings Handling scope line from `feature steps 2/6; chore/bug steps 2/4` to `feature steps 2; chore/bug steps 2` (the reconcile-test-plan step was the only `test-plan` mode site). Update the Persisting Findings chain-step-to-index table accordingly.

7. **Edit `references/step-execution-details.md`**: delete the fork-instruction blocks for feature step 6 (Reconcile test plan), chore step 4 (same), bug step 4 (same). Renumber downstream step headings in all three chains.

8. **Edit `references/verification-and-relationships.md`**: delete verification checklist items referencing the removed step. Update chain-length assertions from "8 steps" to "7 steps" (chore/bug) and from "6+N+4" to "5+N+4" (feature). Update skill-relationship tables to remove `reviewing-requirements (test-plan mode)` as an orchestrator-invoked mode.

9. **Grep-sweep `references/chain-procedures.md`**: check for `Reconcile test plan`, `test-plan`, `step 4` (chore/bug context), `step 6` (feature context). Apply narrow edits if found.

10. **Edit `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh`** — step generators: remove the `Reconcile test plan` step entry from `generate_feature_steps`, `generate_chore_steps`, and `generate_bug_steps`. Update "8-step"/"13-step" code comments to "7-step"/"12-step".

11. **Update `CLAUDE.md` "Existing Skills" section** — the workflow-chain descriptions in the three chains (feature, chore, bug). Remove the `reviewing-requirements (test-plan reconciliation)` step from each chain description. Feature chain: `documenting-features → reviewing-requirements → creating-implementation-plans → documenting-qa → implementing-plan-phases → ...` (drop the test-plan reconciliation entry). Chore/bug chains: same removal.

12. **Update `scripts/__tests__/orchestrating-workflows.test.ts`**: remove `Reconcile test plan` from step-name arrays (feature, chore, bug). Update chain-length assertions: feature `5+N+4`, chore `7`, bug `7`. Update main-context-steps test description to `(1, 4, 5+N+3)`.

13. **Update `scripts/__tests__/workflow-state.test.ts`**: remove `Reconcile test plan` step entries from chore and bug chain fixtures. Update `toHaveLength` assertions from 8 to 7. Update `populate-phases` indexed-step assertions: total `13 → 12`, renumber phase-step/post-phase-step indices.

14. **Grep-sweep for stale tokens** after steps 1–13: `Reconcile test plan`, `test-plan reconciliation`, `6+N+5` (should be gone), `step 6` (chore/bug context, should be gone), `Steps 2, 4` (findings-handling scope, should now be `Steps 2` only), `fixed 8 steps`.

15. **Preserve unchanged**: `reviewing-requirements/SKILL.md` test-plan reconciliation mode is retained — only the orchestrator invocation is removed. Confirm with `git diff --stat` for this path.

16. **Run `npm test` and iterate until green.**

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — feature/chore/bug chain tables updated (step 6/4/4 deleted + renumbered); chain-length prose updated; main-context step headings renumbered; Fork Step-Name Map and Findings Handling scope updated
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` — three fork-instruction blocks deleted; downstream step headings renumbered
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/verification-and-relationships.md` — checklist items deleted; chain lengths updated; skill-relationship tables updated
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` — grep-swept (likely no edits)
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — step generators drop `Reconcile test plan` entry; code comments updated
- [ ] `CLAUDE.md` — workflow-chain descriptions updated in all three chains
- [ ] `scripts/__tests__/orchestrating-workflows.test.ts` — chain-length assertions updated; step-name arrays shortened; main-context-steps test renamed
- [ ] `scripts/__tests__/workflow-state.test.ts` — state-file fixtures updated; `toHaveLength` and `populate-phases` assertions updated
- [ ] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — zero changes (confirmed via `git diff --stat`)

---

### Phase 8 — Integration Test Pass and NFR-5 Smoke Run
**Feature:** [FEAT-018](../features/FEAT-018-qa-executable-oracle-redesign.md) | [#170](https://github.com/lwndev/lwndev-marketplace/issues/170)
**Status:** Pending
**Phase Dependencies:** All prior phases complete. This is the final gate.

#### Rationale

This phase serves two purposes: (1) a full `npm test` green-pass verifying that all test changes across phases 1–7 are consistent and no regressions were introduced; and (2) the NFR-5 smoke run — a real end-to-end invocation of the redesigned `executing-qa` against a recent feature branch to produce a non-PASS verdict, demonstrating that the new design can say "no." The smoke run is non-optional: it is the feature's proof of value.

#### Implementation Steps

##### Integration Test Pass

1. **Run `npm run validate`** — confirms all plugin skills pass `ai-skills-manager` validation. Fix any validation errors (typically frontmatter schema issues introduced during the skill rewrites).

2. **Run `npm test`** — all test files run sequentially per `fileParallelism: false`. Expected: all tests pass. For any failing test not introduced by this feature's changes, investigate before proceeding — do not mask pre-existing failures.

3. **Run `npm run lint`** — check for linting issues in all new `.ts` test files and scripts. Fix any issues found.

##### Fixture Integration Test

4. **Create a minimal fixture repo** at `scripts/__tests__/fixtures/qa-fixture/` with:
   - A `package.json` with `vitest` as a devDependency, a `scripts.test` of `vitest run`, and a simple feature function: `export function add(a, b) { return a + b; }` in `src/add.ts`.
   - A `vitest.config.ts`.
   - A `src/add.ts` with a deliberate off-by-one bug: `return a + b + 1;` (to ensure the QA run produces a failing test).
   - No existing test files (so the QA run must write them from scratch).

5. **Write an integration test in `scripts/__tests__/capability-discovery.test.ts`** (or a new file `scripts/__tests__/qa-integration.test.ts`) that:
   - Runs `capability-discovery.sh` against the fixture repo root → asserts `framework: "vitest"`, `testCommand: "vitest run"`.
   - Simulates the `executing-qa` write-and-run loop by: (a) writing a test file to the fixture's `__tests__/` dir that calls `add(1, 2)` and asserts the result is `3`; (b) running `vitest run` in the fixture dir; (c) asserting exit code is non-zero (the bug causes the assertion to fail); (d) asserting the test output contains a failing test name.
   - This test confirms the end-to-end path: discovery → test write → run → non-zero exit → `ISSUES-FOUND` verdict.

6. **Write a no-framework integration test**: a second fixture with no framework signals → asserts `mode: "exploratory-only"` from capability discovery.

##### NFR-5 Smoke Run

7. **Identify the smoke-run target**: use the FEAT-017 PR branch (or FEAT-016, whichever has more testable surface area). FEAT-017 modified orchestrator documentation and test fixtures — the PR diff is all `.md` and `.ts` files. A reasonable adversarial scenario: "does the step-removal create any race conditions or off-by-one errors in the state machine?" Alternatively, use a feature branch with code changes (preferred for a more meaningful smoke run).

8. **Invoke the redesigned `executing-qa` skill** against the selected target:
   - Ensure the feature branch is checked out locally.
   - Run `documenting-qa FEAT-017` first to produce a version-2 plan artifact (if not already present).
   - Run `executing-qa FEAT-017`.
   - Observe: the capability discovery runs and detects `vitest`. The skill writes QA test files to the fixture. The test runner executes. The stop hook validates the resulting artifact.

9. **Assert non-PASS verdict**: the smoke run must produce either `ISSUES-FOUND` or `EXPLORATORY-ONLY` (FEAT-017 is all documentation changes; the test suite passes cleanly, so the verdict will likely be `EXPLORATORY-ONLY` or `ISSUES-FOUND` if adversarial scenarios surface edge cases in the test logic). If the verdict is `PASS`, the smoke run has failed the NFR-5 gate — investigate and adjust the adversarial scenarios or choose a feature branch with more surface area.

10. **Commit the smoke-run artifact**: save `qa/test-results/QA-results-FEAT-017.md` (or `FEAT-016.md`) to the repo as evidence. The artifact must be version 2 (with frontmatter `version: 2`) and must contain a populated reconciliation delta section. Commit with message: `qa(FEAT-018): NFR-5 smoke run artifact — non-PASS verdict demonstrated`.

11. **Final grep-sweep across all modified files**: search for `verdict.*pass` (lowercase), `verification.*complete`, `reconciliation.*complete` — confirm none appear as load-bearing patterns in the new stop hooks (they were the old regime). Any hit should be in a comment or test fixture for historical reference only.

#### Deliverables

- [ ] `scripts/__tests__/fixtures/qa-fixture/` — minimal vitest fixture repo with a deliberate bug for integration testing
- [ ] `scripts/__tests__/qa-integration.test.ts` — fixture-based integration tests: vitest discovery → test write → run → `ISSUES-FOUND` verdict; no-framework → `EXPLORATORY-ONLY`
- [ ] `npm test` passing — all tests green across the full test suite
- [ ] `npm run validate` passing — all plugin skills valid
- [ ] `npm run lint` passing — no linting issues
- [ ] `qa/test-results/QA-results-{target-ID}.md` — smoke-run evidence artifact committed; version 2 frontmatter; non-PASS verdict; reconciliation delta populated

---

## Shared Infrastructure

### New Scripts (skill-layer tooling)

```
plugins/lwndev-sdlc/skills/documenting-qa/scripts/
├── capability-discovery.sh     Phase 1 — consumed by documenting-qa and executing-qa
└── persona-loader.sh           Phase 2 — sourced helper, exported load_persona()

plugins/lwndev-sdlc/skills/executing-qa/scripts/
└── persona-loader.sh           Phase 2 — identical to documenting-qa version
```

### Artifact Templates

```
plugins/lwndev-sdlc/skills/documenting-qa/assets/
└── test-plan-template-v2.md    Phase 3 — version-2 plan schema

plugins/lwndev-sdlc/skills/executing-qa/assets/
└── test-results-template-v2.md Phase 3 — version-2 results schema
```

### Persona Files

```
plugins/lwndev-sdlc/skills/documenting-qa/personas/
└── qa.md                       Phase 2 — adversarial tester overlay

plugins/lwndev-sdlc/skills/executing-qa/personas/
└── qa.md                       Phase 2 — same content
```

## Testing Strategy

### Unit Tests (Phases 1–3)

All new test files run under the existing vitest harness (`fileParallelism: false`). Each new test file follows the pattern of existing skill tests: create a temp directory, write fixture files, invoke the script/hook/loader, assert on stdout/stderr/exit code.

| Test file | What it covers |
|---|---|
| `scripts/__tests__/capability-discovery.test.ts` | FR-1 detection paths (4 frameworks + no-framework), edge cases 1/2/6/10 |
| `scripts/__tests__/persona-loader.test.ts` | Persona present/missing/malformed (edge case 8) |
| `scripts/__tests__/executing-qa.test.ts` (updated) | Stop-hook artifact-structure validation for all 4 verdict shapes + malformed variants |
| `scripts/__tests__/documenting-qa.test.ts` (updated) | Stop-hook plan-artifact validation; FR-4 no-spec enforcement |
| `scripts/__tests__/qa-verifier.test.ts` (updated) | New agent role — adversarial dimension coverage verdict |

### Integration Tests (Phase 8)

| Test | Fixture | Expected |
|---|---|---|
| `documenting-qa` round-trip | `qa-fixture/` (vitest, no existing tests) | `qa/test-plans/QA-plan-*.md` with version-2 frontmatter and 5 dimension sections |
| `executing-qa` round-trip (test-framework) | `qa-fixture/` with deliberate bug | `ISSUES-FOUND` verdict, failing test names in artifact |
| `executing-qa` round-trip (no-framework) | Empty fixture | `EXPLORATORY-ONLY` verdict with Reason |

### Smoke Test (Phase 8, NFR-5)

Manual invocation of the redesigned skills against a real feature branch (FEAT-017 or FEAT-016). The smoke run is verified by the committed artifact in `qa/test-results/`.

### Preserved Tests

`scripts/__tests__/reviewing-requirements.test.ts` — zero changes (the test-plan reconciliation mode is preserved in the skill; only the orchestrator invocation is removed).

## Dependencies and Prerequisites

- `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` — rewritten in Phase 4
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — rewritten in Phase 5
- `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` — rewritten in Phase 3
- `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` — rewritten in Phase 3
- `plugins/lwndev-sdlc/agents/qa-verifier.md` — rewritten in Phase 6
- `plugins/lwndev-sdlc/agents/qa-reconciliation-agent.md` — new in Phase 6
- `plugins/lwndev-sdlc/skills/documenting-qa/scripts/capability-discovery.sh` — new in Phase 1
- `plugins/lwndev-sdlc/skills/documenting-qa/scripts/persona-loader.sh` — new in Phase 2
- `plugins/lwndev-sdlc/skills/executing-qa/scripts/persona-loader.sh` — new in Phase 2
- `plugins/lwndev-sdlc/skills/documenting-qa/personas/qa.md` — new in Phase 2
- `plugins/lwndev-sdlc/skills/executing-qa/personas/qa.md` — new in Phase 2
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — updated in Phase 7
- `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — NOT modified (test-plan mode preserved)
- `CLAUDE.md` — updated in Phase 7

**Tooling**: `jq` (already a declared dependency of `workflow-state.sh`), `bash` (existing convention), `vitest` (existing test runner).

**External**: `gh` CLI for PR body extraction in `documenting-qa` Step 3 (already available in workflows that have reached a PR stage). If unavailable, fall back to `git diff main...HEAD`.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Stop-hook rewrite (Phase 3) is overly strict — blocks runs that produce valid but slightly non-standard artifacts | High | Medium | The hook uses exact section-header string matching (`^## Verdict`, `^## Capability Report`). Use the template files as the canonical format and test every valid variant (PASS/ISSUES-FOUND/ERROR/EXPLORATORY-ONLY) in unit tests. The `stop_hook_active` bypass remains as the last resort escape hatch. |
| Capability discovery produces wrong framework detection on edge cases (e.g., a repo with jest in node_modules but no config) | Medium | Medium | Detection checks only manifest files (`package.json` deps) and config files — not `node_modules`. The `node_modules` path is excluded from config-file glob patterns by using exact file names, not recursive globs. Unit tests cover each detection signal independently. |
| NFR-5 smoke run produces PASS (the new design still cannot say "no" on FEAT-017's docs-only changes) | High | Medium | Choose a feature branch with code changes (not just docs). Alternatively, introduce a deliberate bug in the fixture and assert ISSUES-FOUND on that. The smoke run failing the NFR-5 gate must trigger a redesign of the adversarial scenarios before the PR is merged. |
| Phase 7 orchestrator renumbering misses a stale reference, leaving chain tables in an inconsistent state | Medium | Medium | Phase 7 step 14 is an explicit grep-sweep of all literal step-number tokens. Run `npm test` as the final consistency check — chain-length assertions in `orchestrating-workflows.test.ts` and `workflow-state.test.ts` will catch any missed renaming. |
| `documenting-qa` stop hook's FR-4 no-spec check (grep for `FR-\d+` in Scenarios sections) produces false positives on legitimate test descriptions that happen to mention "FR-6 dimensions" | Low | Low | Scope the grep to lines within `## Scenarios (by dimension)` section only (use `sed -n '/^## Scenarios/,/^## /p'`). The term "FR-6" in the persona overlay is not in the scenarios section. Test this edge case in `documenting-qa.test.ts`. |
| Phase 6 `qa-verifier.md` rewrite breaks `qa-verifier.test.ts` assertions that other skills depend on indirectly | Low | Low | `qa-verifier.md` is only invoked by `documenting-qa` and `executing-qa`. After the Phase 4/5 rewrites, documenting-qa no longer uses the qa-verifier for the Ralph loop; executing-qa uses `qa-reconciliation-agent.md` for the delta. Update `qa-verifier.test.ts` in Phase 6 in lockstep with the agent rewrite. |
| Backward compatibility: the 34 existing version-1 artifacts are read by a future consumer that expects version-2 schema | Low | Low | FR-10 / NFR-3: no tooling today reads these artifacts. The version-2 schema adds frontmatter `version: 2`; parsers must treat absence as version 1. Document this in both template files' version-history comments. No action needed until a consumer is built. |
| `persona-loader.sh` abort-on-missing behavior blocks the skill entirely when the personas directory is accidentally absent | Medium | Low | The personas directory is committed to the plugin structure. The persona-loader unit test (Phase 2) and the `npm run validate` check (Phase 8) both exercise the path. Add a note in the SKILL.md: "If persona load fails, check that `plugins/lwndev-sdlc/skills/{skill}/personas/qa.md` exists." |

## Success Criteria

Every acceptance criterion from the requirements doc maps to at least one phase:

| Acceptance Criteria | Phase(s) | Verification |
|---|---|---|
| Capability-discovery module implemented for vitest, jest, pytest, go-test (FR-1) | Phase 1 | `capability-discovery.test.ts` unit tests; Phase 8 integration test |
| Capability discovery degrades to `exploratory-only` for no-framework repos (FR-1, FR-3) | Phase 1 | `no-framework fallback` test case |
| Detection order deterministic; multi-framework detection records warning (FR-1, edge case 1) | Phase 1 | `multi-framework detection` test case |
| `executing-qa` writes and runs real tests, produces structured results artifact (FR-2) | Phase 5 | Phase 8 integration test (ISSUES-FOUND verdict on fixture) |
| `executing-qa` produces ISSUES-FOUND/ERROR/EXPLORATORY-ONLY verdicts (FR-2, FR-3) | Phases 3, 5 | Stop-hook unit tests + Phase 8 integration tests |
| `documenting-qa` planning prompt forbids reading requirements doc (FR-4) | Phase 4 | SKILL.md assertion in `documenting-qa.test.ts`; stop-hook FR-N check |
| Planning output organized by dimension; every scenario has priority and execution mode (FR-4) | Phases 3, 4 | Plan stop-hook validation (dimension sections required) |
| Reconciliation delta produced after every `executing-qa` run (FR-5) | Phase 5 | SKILL.md assertion; Phase 8 smoke-run artifact has populated delta |
| Adversarial tester persona (`qa`) covers all 5 FR-6 dimensions (FR-6) | Phase 2 | `persona-loader.test.ts`; `qa.md` content review |
| Empty-findings directive enforced; zero-dimension runs fail validation (FR-6, FR-8) | Phases 2, 3 | Stop-hook unit tests for missing dimension coverage |
| Persona-module slot in place: directory + loader allow adding new persona without restructuring (FR-7) | Phase 2 | `persona-loader.test.ts`; directory structure committed |
| `executing-qa/scripts/stop-hook.sh` rewritten to validate artifact structure (FR-8) | Phase 3 | 12 stop-hook unit tests in `executing-qa.test.ts` |
| `documenting-qa`'s stop hook validates plan artifact structure (FR-8) | Phase 3 | 8 stop-hook unit tests in `documenting-qa.test.ts` |
| Structured results artifact conforms to version-2 schema (FR-9) | Phase 3, 5 | `test-results-template-v2.md` assertions; smoke-run artifact |
| Structured plan artifact conforms to version-2 schema (FR-9) | Phase 3, 4 | `test-plan-template-v2.md` assertions; Phase 8 integration test |
| Existing 34 `qa/test-results/` artifacts preserved unmodified (FR-10, NFR-3) | All (by omission) | `git diff --stat` on `qa/test-results/` before Phase 8 smoke run shows no changes to existing files |
| FR-11 decision made and recorded (reviewing-requirements test-plan mode removed from orchestrator) | Phase 0 | This plan document |
| Orchestrator chain tables updated; CLAUDE.md workflow chains updated (FR-12) | Phase 7 | Chain-length assertions in `orchestrating-workflows.test.ts` and `workflow-state.test.ts` |
| Orchestrator main-context calling pattern for documenting-qa/executing-qa unchanged (NFR-6) | Phase 7 | Orchestrator SKILL.md main-context step sections retain same invocation pattern |
| All edge cases have corresponding unit or integration tests | Phases 1–5, 8 | Test map: EC1→Phase 1, EC2→Phase 1, EC3→Phase 8, EC4→Phase 5, EC5→Phase 5, EC6→Phase 1, EC7→Phase 5, EC8→Phase 2, EC9→Phase 3, EC10→Phase 1 |
| NFR-5 smoke run: at least one real run produces non-PASS verdict with artifact committed | Phase 8 | Committed `qa/test-results/QA-results-{target-ID}.md` with non-PASS verdict |
| `qa-verifier.md` agent rewritten around adversarial-persona model (not file-read verification) | Phase 6 | `qa-verifier.test.ts` updated assertions |
| `scripts/__tests__/` updated for new artifact format and stop-hook behavior | Phases 3–7 | Full `npm test` green |
| PR description references this doc, #170, #163, #169 | Phase 8 | PR creation checklist |

## Code Organization

New files and modified files by phase:

```
plugins/lwndev-sdlc/
├── agents/
│   ├── qa-verifier.md                               Phase 6 (rewrite)
│   └── qa-reconciliation-agent.md                   Phase 6 (new)
└── skills/
    ├── documenting-qa/
    │   ├── SKILL.md                                 Phase 4 (rewrite)
    │   ├── assets/
    │   │   └── test-plan-template-v2.md             Phase 3 (new)
    │   ├── personas/
    │   │   └── qa.md                                Phase 2 (new)
    │   └── scripts/
    │       ├── capability-discovery.sh              Phase 1 (new)
    │       ├── persona-loader.sh                    Phase 2 (new)
    │       └── stop-hook.sh                         Phase 3 (rewrite)
    ├── executing-qa/
    │   ├── SKILL.md                                 Phase 5 (rewrite)
    │   ├── assets/
    │   │   └── test-results-template-v2.md          Phase 3 (new)
    │   ├── personas/
    │   │   └── qa.md                                Phase 2 (new)
    │   └── scripts/
    │       ├── persona-loader.sh                    Phase 2 (new)
    │       └── stop-hook.sh                         Phase 3 (rewrite)
    └── orchestrating-workflows/
        ├── SKILL.md                                 Phase 7 (chain-table edits)
        ├── scripts/
        │   └── workflow-state.sh                    Phase 7 (step generators)
        └── references/
            ├── step-execution-details.md            Phase 7 (fork blocks deleted)
            ├── verification-and-relationships.md    Phase 7 (checklist + tables)
            └── chain-procedures.md                  Phase 7 (grep-swept)

scripts/__tests__/
├── capability-discovery.test.ts                     Phase 1 (new)
├── persona-loader.test.ts                           Phase 2 (new)
├── qa-integration.test.ts                           Phase 8 (new)
├── fixtures/
│   └── qa-fixture/                                  Phase 8 (new)
├── documenting-qa.test.ts                           Phases 3, 4 (updated)
├── executing-qa.test.ts                             Phases 3, 5 (updated)
├── qa-verifier.test.ts                              Phase 6 (updated)
├── orchestrating-workflows.test.ts                  Phase 7 (updated)
└── workflow-state.test.ts                           Phase 7 (updated)

CLAUDE.md                                            Phase 7 (workflow-chain descriptions)
```

**Preserved unchanged:**
```
plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md
qa/test-results/QA-results-*.md  (all 34 existing v1 artifacts)
scripts/__tests__/reviewing-requirements.test.ts
```
