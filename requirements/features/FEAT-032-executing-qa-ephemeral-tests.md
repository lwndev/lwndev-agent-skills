# Feature Requirements: executing-qa ephemeral tests + addressing-qa-findings dev-fix skill + adoption into dev suite

## Overview

Refactor `executing-qa` so QA-authored test files no longer accumulate in the repo, and add a developer-persona skill (`addressing-qa-findings`) that consumes a QA `ISSUES-FOUND` artifact, fixes the production code, runs a re-QA loop, and adopts the QA test into the developer-owned suite as a permanent regression test under a `{module}.qa.{ext}` sibling naming convention. `finalizing-workflow` gains a safety-net check that blocks merge if any pre-adoption QA test files survive.

## Feature ID

`FEAT-032`

## GitHub Issue

[#267](https://github.com/lwndev/lwndev-marketplace/issues/267)

## Priority

High — fixes two structural defects in the SDLC chain:

1. QA-authored tests accumulate forever (8+ orphaned `qa-*.test.ts` in `tests/unit/`, plus the `qa-CHORE-037-husky-hooks.bats` that broke main per #260).
2. There is no developer-persona skill that consumes QA findings; today the orchestrator advances from `ISSUES-FOUND` straight to `finalizing-workflow` (which merges the PR), so findings are silently dropped.

Closes (or supersedes) #260, #262 and unblocks #265 (v2 adoption) and #266 (one-time QA-file cleanup). #261 (drop `--skip-test` from `executing-qa` Step 5.5) is **deferred** as a follow-up issue — out of scope here.

## User Story

As a workflow user whose `executing-qa` run returned `ISSUES-FOUND`, I want the orchestrator to invoke a developer-persona fix skill that reproduces, fixes, re-validates, and **adopts** the QA test into the regression suite — so that adversarial knowledge is preserved as a permanent test, the production bug is fixed in the same PR, and no `qa-*` prefixed files leak past merge.

## Scope

### In scope

- `plugins/lwndev-sdlc/skills/executing-qa/`
  - SKILL.md updates: drop dedicated `qa-<dimension>` filename convention as a long-term artifact; describe the new lifecycle (write → run → embed in artifact → await re-QA → delete on adoption)
  - `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template-v2.md`: per-finding `## Reproduction` block with the QA test source embedded as a code block
  - `plugins/lwndev-sdlc/skills/executing-qa/scripts/render-qa-results.sh`: embed test source under each finding
  - New `re-qa` mode (auto-detected by presence of prior committed QA test files for the ID): re-execute the prior committed QA tests, render an updated artifact, return verdict — does NOT regenerate or write new tests
  - `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` (FR-10 diff guard): keep the report-only diff guard; document that the new dev-fix skill is allowed to MOVE the files (not edit them)
- New skill `plugins/lwndev-sdlc/skills/addressing-qa-findings/`
  - Developer persona (not QA)
  - Inputs: `qa/test-results/QA-results-{ID}.md` and the committed QA test files on the branch
  - Workflow: parse findings → reproduce failure → write production fix → confirm QA test passes → run full suite → commit fix → return for re-QA → after re-QA passes, run adoption script → commit adoption
  - Adoption script: deterministic `git mv` of QA test to `{module}.qa.{ext}` sibling location next to existing peer test for the same SUT
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/`
  - Verdict-based branching: `executing-qa` returning `ISSUES-FOUND` triggers `addressing-qa-findings` instead of advancing to `finalizing-workflow`
  - Re-QA loop with hard cap N=2 fix attempts; on exhaustion, pause with a `qa-loop-exhausted` reason for human escalation
  - Loop counter persisted in workflow state
  - `EXPLORATORY-ONLY` verdict continues to advance directly to finalize (no test files to adopt)
- `plugins/lwndev-sdlc/skills/finalizing-workflow/`
  - Safety-net check that scans the branch for surviving `qa-*` prefixed files (the *original* QA naming, not `*.qa.*` siblings); blocks merge with a clear error if any are found
- Test layout / parity assertion fixes
  - `tests/unit/shared-scripts.test.ts:102-117` (hard-coded `14` literal at line 107): change from `expect(batsFiles.length).toBe(...)` to per-script `existsSync` (set-based parity); drop hard-coded `14`; tolerate `*.qa.bats` siblings
  - Audit other length-based assertions under `tests/unit/*.test.ts` for the same pattern; relax to set-based where `*.qa.*` siblings would falsely trip the count
- `CLAUDE.md`
  - Document the new QA lifecycle and adoption pattern; remove references to `qa-` prefix accumulation as expected behavior
- Test coverage for every new script behavior at the canonical test leaf (Vitest for TS, Bats for shell)

### Out of scope

- v2 adoption (AST-merge into existing test file, periodic consolidation/pruning) — tracked in **#265**
- One-time cleanup of accumulated historical `qa-*` files — tracked in **#266**
- Rewriting QA test imports when the adopted path requires path adjustments (deferred to v2 / handled manually for v1)
- Squash-vs-merge commit policy decisions (the `qa(test):` and `qa(adopt):` commits are accepted as-is; squash-merge flows naturally hide them)

## Functional Requirements

### FR-1: QA tests are ephemeral on the feature branch

`executing-qa` writes adversarial tests into the framework's test root (e.g. `tests/unit/qa-<dimension>.test.ts`, `tests/bats/qa/qa-<dimension>.bats`) using full project context (helpers, fixtures, mocks, imports). The tests are committed to the feature branch via the existing `commit-qa-tests.sh` so they survive session loss, branch switches, and multi-machine work — but they MUST NOT survive merge to main. Their lifecycle is bounded by the workflow: born in `executing-qa`, consumed by `addressing-qa-findings`, deleted (via `git mv` to adopted location) before `finalizing-workflow`.

### FR-2: QA test source embedded in the artifact

`render-qa-results.sh` embeds the QA test source code as a fenced code block under each finding's `## Reproduction` section in `qa/test-results/QA-results-{ID}.md`. The code block is delimited by language-aware fences (e.g. \`\`\`typescript, \`\`\`bash) and includes the relative path of the source file as a comment header. The artifact is the canonical readable record; the on-disk committed test is the runnable artifact. Both exist concurrently during the workflow.

### FR-3: `executing-qa` re-QA mode

When `executing-qa` is invoked and prior QA test files for the workflow ID already exist on the branch, it enters **re-QA mode**.

**Auto-detection mechanism**: re-QA mode is entered when both of the following hold:

1. The marker file `.sdlc/qa/.executing-qa-baseline-{ID}` (written by `plugins/lwndev-sdlc/skills/executing-qa/scripts/qa-baseline.sh` as `MARKER_PATH=${MARKER_DIR}/.executing-qa-baseline-${id}`) is present — meaning a prior QA run has been baselined for this ID.
2. At least one `qa-*` test file exists at the framework's test root for the ID, matched against the explicit v1 glob set: `tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`. The patterns `qa-*.py` and `qa-*.go` are reserved as forward-compatible no-ops, identical to FR-9, until pytest and go-test dispatch land in FR-5.

No new marker is introduced; re-QA mode reuses the existing `qa-baseline.sh` marker as the single source of truth for "this workflow has had a prior QA run".

**Re-QA mode behavior**:

- Does NOT regenerate or write new tests
- Re-executes the existing committed QA tests via the framework runner
- Renders an updated `qa/test-results/QA-results-{ID}.md` (overwrite per FR-12)
- Emits the same return contract (`Verdict: <VERDICT> | Passed: <N> | Failed: <N> | Errored: <N>`)
- Does NOT delete QA test files. Deletion is owned exclusively by `addressing-qa-findings` (via `git mv` during adoption — see FR-13). Re-QA mode cannot return `EXPLORATORY-ONLY` (no path to that verdict from a re-execution of committed adversarial tests — Edge Case 6). The re-QA verdict set is therefore `{PASS, ISSUES-FOUND, ERROR}`; orchestrator dispatch (FR-7) only consults those three rows after a re-QA invocation.

Re-QA mode is a behavior-mode of the same skill, NOT a separate `re-executing-qa` skill (avoids skill proliferation).

### FR-4: New skill `addressing-qa-findings`

Plugin path: `plugins/lwndev-sdlc/skills/addressing-qa-findings/SKILL.md`

Persona: developer (consumes QA findings; writes production fixes).

Argument: workflow ID (e.g. `FEAT-032`).

The skill is invoked **twice per re-QA loop attempt** by the orchestrator: once for the **fix phase**, once for the **adopt phase**. The phase is auto-detected from workflow state using the triple `{qaLastVerdict, qaFixAttempts, adoptedTests}`:

- **Fix phase** = `qaLastVerdict == ISSUES-FOUND` AND `adoptedTests` is empty
- **Adopt phase** = `qaLastVerdict == PASS` AND `qaFixAttempts > 0` AND `adoptedTests` is empty

Auto-detection means callers do not pass a phase argument — the skill reads these three fields (already in the FR-7 dispatch contract) to decide. No new state field is required; in particular, no `lastStepKind` is introduced.

#### Fix phase

1. Resolve the QA artifact path (`qa/test-results/QA-results-{ID}.md`) and parse findings
2. **Pre-check**: confirm the git working tree is clean (no uncommitted changes from prior workflow steps); if dirty, fail with `failed | working tree dirty; commit or stash before re-running` (load-bearing carve-out)
3. Process findings as a single batch (one attempt = one full pass over all findings, NOT per-finding loops):
   1. Read each embedded QA test source AND locate the committed test file on the branch
   2. Execute each QA test locally; confirm each fails at HEAD (sanity check)
   3. Write production fix(es) — may span multiple files; one commit at the end of the batch
   4. Re-execute each QA test; confirm each passes locally
4. Run the full test suite (build-health gate). On failure (FR-4-EC) — see Edge Case 13.
5. Commit the production fix(es) with `fix({ID}): <summary>`
6. Return contract: `done | phase=fix-committed | awaiting-re-qa`

#### Adopt phase

1. **Pre-check**: confirm `qaLastVerdict == PASS` (the orchestrator already validates this; the skill double-checks). If not PASS, fail with `failed | adopt phase invoked without re-QA PASS verdict`.
2. For each committed QA test file on the branch:
   1. Run the adoption script (FR-5) on that file
   2. **Emit the adopted path to stdout immediately on script exit 0** — one line per successful `git mv`, before continuing to the next file. This stdout stream is consumed by the orchestrator to record `adoptedTests` incrementally, so partial progress survives a subsequent failure.
   3. On script exit 2, abort the adoption: stop calling the script, leave already-moved files in place (partial-success outcome — see FR-5 aggregation), and emit `failed | adoption failed for <path>; <N> adopted, <M> remaining` (FR-5 partial-success path, see Edge Case 14). The previously-emitted stdout path lines remain valid; they are the source of truth for `adoptedTests` on partial-success failure.
3. Commit the adoption with `qa(adopt): {ID} promote QA tests into regression suite`
4. Return contract: `done | phase=adopted | artifact=qa/test-results/QA-results-{ID}.md | adopted=<N>`

The skill MUST NOT attempt to "fix" without an upstream finding (the QA artifact is the only source of authority for what to address).

### FR-5: Deterministic adoption script

Plugin path: `plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts/adopt-qa-test.sh`

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/addressing-qa-findings/scripts/adopt-qa-test.sh" <qa-test-path>
```

Behavior:

1. Parse the QA test source for `import` / `require` / bats `load` statements
2. Identify the SUT module from the imports (the production module under test)
3. Locate the existing test file for that SUT (e.g. `foo.test.ts` for source `foo.ts`; `foo.bats` for `foo.sh`)
4. Compute the sibling target path: `{existing-test-dir}/{base}.qa.{ext}` (e.g. `tests/unit/foo.qa.test.ts` next to `tests/unit/foo.test.ts`; `tests/bats/shared/foo.qa.bats` next to `tests/bats/shared/foo.bats`)
5. `git mv <qa-test-path> <new-path>`
6. Print the new path on stdout (single line, trailing newline)

Per-framework dispatch is keyed off the framework names already produced by `plugins/lwndev-sdlc/skills/executing-qa/scripts/capability-discovery.sh` (the executing-qa variant, NOT the `documenting-qa` script of the same name). v1 must support Vitest (TS/JS) and Bats; pytest and go-test support is acceptable but optional for v1 (track as follow-ups if dispatch fails for those frameworks).

Exit codes:

- `0` success
- `1` filesystem / `git mv` failure
- `2` SUT cannot be determined (no resolvable imports / multiple plausible peers / no existing peer test)

On exit `2`, the script prints a structured stderr message naming the QA test path and the reason; `addressing-qa-findings` surfaces this verbatim (load-bearing carve-out) and pauses for human review with state `paused | adoption-failed`.

**Aggregation across multiple QA test files**: `addressing-qa-findings` calls `adopt-qa-test.sh` once per QA test file, in order. On the first exit-2, the skill aborts the loop — already-moved files remain moved (partial success), and the skill returns `failed | adoption failed for <path>; <N> adopted, <M> remaining`. The orchestrator pauses with `adoption-failed`. Resume requires either manual adoption of the remaining files or human intervention. This is single-shot abort-on-error semantics, not best-effort all-or-nothing.

### FR-6: Adopted-test naming convention

Adopted tests live at `{existing-test-dir}/{base}.qa.{ext}` — co-located with peer tests, NOT in a dedicated `tests/regression/` (or similar) directory. The `.qa.` infix is the adoption marker. Examples:

- `tests/unit/foo.test.ts` peer → `tests/unit/foo.qa.test.ts`
- `tests/bats/shared/check-acceptance.bats` peer → `tests/bats/shared/check-acceptance.qa.bats`
- `src/foo.test.ts` (co-located convention) peer → `src/foo.qa.test.ts`

The `*.qa.*` files satisfy the existing test-layout rules under `scripts/test-layout-rules.ts` without modification (any `.test.ts` under `tests/unit/` and any `.bats` under `tests/bats/` are accepted).

### FR-7: Orchestrator verdict-based branching

`orchestrating-workflows` consults the QA verdict after every `executing-qa` invocation and dispatches:

| Verdict | Action |
|---------|--------|
| `PASS` (initial run) | Detected when `qaLastVerdict == PASS` AND `qaFixAttempts == 0`. Advance to `finalizing-workflow` |
| `PASS` (after fix phase) | Detected when `qaLastVerdict == PASS` AND `qaFixAttempts > 0` AND `adoptedTests` is empty. Re-invoke `addressing-qa-findings` for the adopt phase (FR-4); on its return, advance to `finalizing-workflow` |
| `ISSUES-FOUND` | Branch to `addressing-qa-findings` fix phase; on its return (`done | phase=fix-committed`), re-invoke `executing-qa` in re-QA mode (FR-3); loop until `PASS` or loop cap (FR-8) |
| `ERROR` | Pause with `pauseReason: qa-error` for human escalation |
| `EXPLORATORY-ONLY` | Advance to `finalizing-workflow` (no test files to adopt) |

The fix-then-adopt sequence requires three orchestrator-driven invocations per loop attempt: (1) `addressing-qa-findings` fix phase, (2) `executing-qa` re-QA mode, (3) on PASS, `addressing-qa-findings` adopt phase. The orchestrator dispatches each step based on the most recent return contract — the skill itself does not loop internally.

This is a real change to the orchestrator's main-context QA step — the existing comment in `orchestrating-workflows/SKILL.md` ("the orchestrator does NOT change advance behavior based on verdict") is updated to reflect the new gating.

**Closure on `EXPLORATORY-ONLY`**: the verdict is reachable only from initial-run dispatch, never from post-loop dispatch. FR-3 establishes that re-QA mode cannot return `EXPLORATORY-ONLY`; therefore the `EXPLORATORY-ONLY → finalizing-workflow` row in the table above is consulted only when `qaFixAttempts == 0` AND the most recent invocation was an initial `executing-qa` run. The orchestrator never sees this path after a re-QA invocation.

### FR-7a: `pauseReason` enum extension

The four new pause reasons introduced by this feature — `qa-error` (FR-7), `qa-loop-exhausted` (FR-8), `fix-suite-failed` (NFR-2 / Edge Case 13), `adoption-failed` (NFR-2 / Edge Case 14) — extend the closed enum currently validated by `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` in `cmd_pause` (around L1138). The script's allow-list MUST be updated to accept all seven values: `plan-approval`, `pr-review`, `review-findings`, `qa-error`, `qa-loop-exhausted`, `fix-suite-failed`, `adoption-failed`. Bats coverage at `tests/bats/skills/orchestrating-workflows/workflow-state-record-findings-qa.bats` (the existing per-skill leaf for QA-related state assertions) must add positive tests for each of the four new values and a negative test confirming an unknown reason still exits 1. (Follow-up issue [#270](https://github.com/lwndev/lwndev-marketplace/issues/270) tracks renaming this file to `workflow-state.bats` for clarity — out of scope here; the spec uses the current filename until that rename lands.) The resume dispatch in `check-resume-preconditions.sh` and the orchestrator's resume procedure must add branches for the four new reasons.

**Error-message contract**: when an unknown reason is rejected, `cmd_pause` MUST emit `Error: Invalid pause reason '${reason}'. Expected one of: plan-approval, pr-review, review-findings, qa-error, qa-loop-exhausted, fix-suite-failed, adoption-failed.` to stderr and exit 1. The enumerated list in the message is kept literally in sync with the allow-list; a Bats assertion in the same test file pins the exact message text so drift between the validator and the message is caught at test time.

### FR-8: Re-QA loop cap N=2

The orchestrator persists a `qaFixAttempts` counter in workflow state (`.sdlc/workflows/{ID}.json`). One **attempt** is defined as a complete fix-phase pass over **all findings in the current artifact** plus a single re-QA execution — NOT one attempt per finding. So if a workflow has 5 findings, `addressing-qa-findings` (fix phase) addresses all 5 in a single batch, and the subsequent re-QA either returns PASS (loop ends) or ISSUES-FOUND (counter increments to 2, loop continues with the next batch). This matches the NFR-1 cost analysis ("2× fix attempts + 2× re-QA executions").

The counter is incremented each time the **fix phase** of `addressing-qa-findings` completes successfully (the adopt phase does not consume an attempt). The counter is reset on workflow start.

When `qaFixAttempts >= 2` AND the most recent re-QA verdict is still `ISSUES-FOUND`, the orchestrator pauses with `pauseReason: qa-loop-exhausted`. Resume from this pause requires explicit user action:

- **Approve advance** → counter is preserved (no reset); orchestrator advances to `finalizing-workflow` (the safety-net check will trip if QA test files remain — user must adopt or remove manually first)
- **Restart loop with higher cap** → counter is reset to 0; user invokes the orchestrator with an explicit `--qa-loop-cap <N>` flag (added in this feature) overriding the default of 2
- **Abandon** → workflow stays paused; user is expected to manually clean up or revert

The cap is `N=2` (not 3) — chosen as the tighter end of the design's 2–3 range to limit worst-case cost. Adjustable via the `--qa-loop-cap <N>` flag (or future configuration) if observed agent behavior justifies relaxation.

**Resume invocation surface.** The orchestrator surfaces these three options at the pause prompt; the canonical CLI mappings are:

- **Approve advance** → re-invoke `/orchestrating-workflows {ID} --approve-advance` (counter preserved; orchestrator advances; safety-net may still trip per Edge Case 16).
- **Restart loop with higher cap** → re-invoke `/orchestrating-workflows {ID} --qa-loop-cap <N>` (counter reset to 0; new cap takes effect for this workflow only).
- **Abandon** → no re-invocation; workflow stays paused indefinitely (no flag).

Both `--approve-advance` and `--qa-loop-cap <N>` are added as new orchestrator flags by this feature; both are positional-independent and parsed by the existing `parse-model-flags.sh`-style scaffold.

**Flag conflict**: `--approve-advance` and `--qa-loop-cap <N>` are **mutually exclusive** on a single resume invocation. If both are provided, the parser exits 2 with `Error: --approve-advance and --qa-loop-cap are mutually exclusive` to stderr. Rationale: the two flags map to opposite resume actions (advance-past-loop vs. restart-loop); accepting both would make the user's intent ambiguous. Bats coverage in `tests/bats/skills/orchestrating-workflows/` asserts the exit-2 path and the message text.

### FR-9: `finalizing-workflow` safety-net check

Before performing the merge, `finalizing-workflow` runs a check that scans tracked files in the working tree (via `git ls-files`) for any filename matching the original QA naming glob set. Untracked `qa-*` files do not block merge (they will not reach main); branch-diff and remote refs are not consulted. The glob set matches the same frameworks `executing-qa` writes for. v1 supports Vitest (TS/JS) and Bats (per FR-5), so the v1 globs are: `qa-*.test.ts`, `qa-*.test.js`, `qa-*.bats`. The globs `qa-*.py` and `qa-*.go` are added forward-compatibly when pytest and go-test support are added to FR-5; until then, scanning for them is a no-op (no false positives).

Note: FR-9's glob set intentionally forms a superset of FR-1's write convention — the safety net catches any `qa-*`-prefixed leakage anywhere under the tracked tree, not just the dimension-named files the canonical writer produces.

The check lives in `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh` as a new parallel subshell sibling to the existing clean-tree / branch / PR / build-health checks. It writes its status to `$tmpdir/qa-leakage.reason` and is evaluated in precedence order after the build-health gate (it is the last gate before merge). No new script file is introduced.

If any matching file is found, the merge is blocked with the error:

```
[error] QA test files were not adopted; the addressing-qa-findings skill did not complete cleanly:
  - <path-1>
  - <path-2>
Resolve by running addressing-qa-findings to adoption, or manually adopting/deleting these files.
```

Adopted siblings (`*.qa.*`) are explicitly NOT matched — only the `qa-*` prefix glob is checked. The check is idempotent and safe to re-run.

### FR-10: Set-based parity assertion

`tests/unit/shared-scripts.test.ts` lines 102-117 (the parity describe block; hard-coded `14` literal at line 107) is replaced with a set-based assertion: every entry in `CANONICAL_SCRIPTS` must have a matching `tests/bats/shared/<name>.bats`; additional `*.qa.bats` siblings are tolerated; the hard-coded count is removed entirely.

The replacement pattern:

```ts
for (const script of CANONICAL_SCRIPTS) {
  const expected = path.join(BATS_SHARED_DIR, `${script}.bats`);
  expect(existsSync(expected)).toBe(true);
}
// no length-based assertion; *.qa.bats siblings allowed
```

### FR-11: Length-assertion audit

Every `*.test.ts` file under `tests/unit/` is audited for length-based assertions (`expect(x.length).toBe(...)`, `expect(x).toHaveLength(...)`, etc.) over directories that may receive `*.qa.*` siblings (`tests/unit/`, `tests/bats/shared/`, `tests/bats/skills/**`, `tests/fixtures/**`). Each hit is either:

- Relaxed to a set-based assertion (preferred), OR
- Filtered to exclude `*.qa.*` files before the count, OR
- Documented as intentionally strict (with a comment explaining why `.qa.` siblings are not expected in that path)

The audit produces a list of changes; each one is implemented in this feature.

**Audit deliverable**: the audit list is recorded in the PR body under a `## Length-Assertion Audit` heading. Each row names the source file and line range, the original assertion, the chosen treatment (`relaxed` / `filtered` / `documented-strict`), and a one-sentence rationale. This makes the audit reviewable without re-running the search and survives squash-merge into the main history. The same list also appears as a section in the implementation plan's deliverable for this requirement, so the plan's QA test plan can verify each entry was addressed.

### FR-12: QA artifact versioning across re-QA

When `executing-qa` runs in re-QA mode (FR-3), it overwrites `qa/test-results/QA-results-{ID}.md` with the latest results. Prior results are NOT preserved as separate files; the artifact represents the *current* QA verdict at any point in the workflow. The audit trail of attempts is in `.sdlc/workflows/{ID}.json` (loop counter and per-step findings history) — not in duplicated artifact files.

This overwrite contract is load-bearing for downstream consumers: `addressing-qa-findings` always reads the current artifact (no stale-read risk), and the safety-net check in FR-9 only ever sees one canonical QA results file. The overwrite behavior is asserted by the FR-12 acceptance criterion (re-QA artifact-overwrite Bats fixture).

**Artifact commit ownership**: `executing-qa` (both initial and re-QA mode) commits `qa/test-results/QA-results-{ID}.md` before returning, alongside the QA test file commit produced by `commit-qa-tests.sh`. The commit message is `qa({ID}): record QA results` (initial) or `qa({ID}): re-record QA results after fix attempt {N}` (re-QA, where `{N}` is the current `qaFixAttempts` counter at write time). This guarantees the working tree is clean on `addressing-qa-findings` entry, satisfying the FR-4 fix-phase precheck without requiring the precheck to whitelist the artifact path. On re-QA mode, the artifact commit replaces (overwrites + commits) the prior artifact contents in a new commit; prior commits are preserved as the audit trail.

### FR-13: Adoption ownership

`addressing-qa-findings` is the **sole** owner of QA test deletion. Deletion is always performed via `git mv` during adoption (the move IS the deletion). `executing-qa` (in either initial or re-QA mode) NEVER deletes QA test files. `EXPLORATORY-ONLY` is unreachable from re-QA mode (Edge Case 6) so there is no parallel ownership rule for that path.

This ownership rule is testable: an acceptance criterion asserts that no skill or script other than `addressing-qa-findings` deletes any `qa-*` file (grep over plugin scripts plus a Bats negative test).

### FR-14: CLAUDE.md documentation

`CLAUDE.md` is updated in this feature to:

- Document the QA test lifecycle (ephemeral, committed-during-workflow, deleted-via-adoption)
- Document the `*.qa.*` sibling naming convention
- Reference the `addressing-qa-findings` skill in the chain descriptions
- Remove any prose that treats `qa-*` accumulation as expected behavior

## Output Format

### `addressing-qa-findings` return contract (final line)

The skill emits one of three shapes depending on phase and outcome:

- **Fix phase success**: `done | phase=fix-committed | awaiting-re-qa`
- **Adopt phase success**: `done | phase=adopted | artifact=qa/test-results/QA-results-{ID}.md | adopted=<N>` where `<N>` is the count of QA test files adopted
- **Either phase failure**: `failed | <one-sentence reason>` — examples: `failed | working tree dirty; commit or stash before re-running` (fix-phase precheck), `failed | adoption failed for <path>; <N> adopted, <M> remaining` (adopt-phase partial-success abort), `failed | full suite gate failed after fix; reverting commit not implemented in v1, manual intervention required` (FR-4 step 4 failure — see Edge Case 13)

The orchestrator dispatches based on the `phase=...` token. After a `phase=fix-committed` return, the orchestrator runs `executing-qa` in re-QA mode. After a `phase=adopted` return, the orchestrator advances to `finalizing-workflow`.

### `executing-qa` re-QA return contract

Identical to the existing `executing-qa` return contract:

```
Verdict: <PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY> | Passed: <N> | Failed: <N> | Errored: <N>
```

### Workflow state additions (`.sdlc/workflows/{ID}.json`)

```json
{
  "qaFixAttempts": <int>,
  "qaLastVerdict": "PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY",
  "adoptedTests": ["tests/unit/foo.qa.test.ts", "..."]
}
```

`qaFixAttempts` is incremented inside the orchestrator's QA loop. `qaLastVerdict` is the verdict from the most recent `executing-qa` invocation. `adoptedTests` is the list of paths emitted on stdout by `addressing-qa-findings` (one line per successful `git mv`, captured incrementally — see FR-4 adopt phase step 2.2). On a `done | phase=adopted` return, `adoptedTests` length matches the contract's `adopted=<N>` token. On a `failed | adoption failed for <path>; <N> adopted, <M> remaining` return (FR-5 partial-success), `adoptedTests` length equals `<N>` (the paths already moved before the abort) and the orchestrator pauses with `adoption-failed`; `adoptedTests` is preserved across the pause so resume can reason about what remains.

## Non-Functional Requirements

### NFR-1: Performance

- Adoption script runs in under 2 seconds per QA test file (deterministic file ops + grep over imports; no LLM calls)
- Re-QA mode reuses the existing `run-framework.sh` runner; no additional startup cost beyond the framework's own
- Loop cap N=2 bounds worst-case cost per workflow:
  - **N=2** (default): 2× full-batch fix passes + 2× full re-QA executions = ~4× the runtime of a single passing QA run.
  - **N=3** (opt-in via `--qa-loop-cap 3`): adds one more full pass + re-execution = ~6×. Chosen tighter end (N=2) bounds expected cost in the common case where two attempts converge or escalate to a human; N=3 is reserved for known-noisy domains via explicit override.

### NFR-2: Error handling

- Adoption script exit 2 (SUT undeterminable) → orchestrator pauses with `adoption-failed`; user must intervene (FR-5 aggregation, Edge Case 14)
- Re-QA mode invoked without prior QA test files → emits `ERROR` verdict with summary "re-QA invoked but no prior QA test files found for {ID}"
- `finalizing-workflow` safety-net trip → blocks merge; user runs `addressing-qa-findings` or manually resolves
- Loop cap exhaustion → pauses with `qa-loop-exhausted`; user can advance, raise the cap via `--qa-loop-cap <N>`, or abandon
- Working-tree dirty on `addressing-qa-findings` entry → skill exits `failed | working tree dirty; commit or stash before re-running`. The skill does NOT auto-stash. (Aligns with the rest of the SDLC chain's clean-tree precondition.)
- Full-suite gate fails after fix → pauses with `fix-suite-failed`; v1 has no auto-revert (Edge Case 13)

### NFR-3: Backwards compatibility

- Existing workflows in progress (with `qa-*` prefixed test files already on a feature branch) continue to work; the safety-net check applies on their next finalize
- Historical `qa-*` files in main (covered by #266) are NOT touched by this feature; the safety net only blocks NEW such files from leaking
- `executing-qa` PASS-on-first-run path is unchanged (no `addressing-qa-findings` invocation, no re-QA loop)
- **Workflow state schema migration**: `.sdlc/workflows/{ID}.json` files written before this feature lacked the `qaFixAttempts`, `qaLastVerdict`, and `adoptedTests` fields. `workflow-state.sh` reads missing fields with default values at read time: `qaFixAttempts: 0`, `qaLastVerdict: null`, `adoptedTests: []`. The defaults are written back to the file on the next state mutation (in-place migration), matching the FEAT-014 FR-13 precedent. No standalone migration script is required; resume of a pre-FEAT-032 workflow silently upgrades the state file on the first write.

### NFR-4: Test coverage

- Every new script (`adopt-qa-test.sh`, re-QA mode logic, safety-net check, set-based parity) has Bats or Vitest coverage at the canonical leaf
- The orchestrator's verdict-branching logic has Vitest coverage for the four verdict paths (`PASS`, `ISSUES-FOUND`, `ERROR`, `EXPLORATORY-ONLY`)
- The loop-cap behavior has Vitest coverage for the `qaFixAttempts >= 2` pause path
- An end-to-end Bats fixture exercises `ISSUES-FOUND → addressing-qa-findings → re-QA PASS → adoption → finalize` (no shortcuts)

## Dependencies

- `executing-qa` skill (existing) — modified for re-QA mode, artifact embedding, deletion ownership
- `orchestrating-workflows` skill (existing) — modified for verdict branching, loop counter, pause reasons
- `finalizing-workflow` skill (existing) — modified for safety-net check (new parallel sibling check in `preflight-checks.sh`; no new script file)
- `workflow-state.sh` (existing) — extended for `qaFixAttempts`, `qaLastVerdict`, `adoptedTests` fields
- `capability-discovery.sh` (existing, in `executing-qa`) — used by `adopt-qa-test.sh` for per-framework dispatch
- No new third-party dependencies

## Edge Cases

1. **Adoption: no peer test exists for the SUT** — adoption script exits 2; orchestrator pauses with `adoption-failed`. User decides whether to create a peer test and re-run, or to delete the QA test manually.
2. **Adoption: multiple plausible peer tests** — adoption script exits 2 (ambiguity). User picks one and either adjusts imports or runs adoption manually.
3. **Adoption: QA test imports a helper that lives next to the QA test (e.g. `./helpers/qa-mock.ts`)** — after `git mv`, the import path may break. v1 leaves this for the developer to fix (manual import adjustment); v2 (issue #265) handles AST-aware rewriting.
4. **Re-QA mode invoked without prior QA test files** — `executing-qa` emits `ERROR` with summary indicating the missing prior tests; orchestrator pauses for human escalation.
5. **Loop cap exhaustion (`qaFixAttempts == 2` AND verdict still `ISSUES-FOUND`)** — orchestrator pauses with `qa-loop-exhausted`; user can manually advance, raise the cap, or abandon.
6. **`EXPLORATORY-ONLY` verdict** — no findings, no test files to adopt; orchestrator advances to finalize directly. `executing-qa` re-QA mode is NOT invoked (no prior committed QA tests in this path).
7. **`ERROR` verdict on first `executing-qa` run** — orchestrator pauses with `qa-error`; `addressing-qa-findings` is NOT invoked (no findings to consume).
8. **User manually deletes QA test files mid-workflow** — re-QA mode emits `ERROR`; orchestrator pauses. No silent recovery — the workflow expects QA test files to exist throughout the fix loop.
9. **`finalizing-workflow` safety-net trips on a `*.qa.*` file** — does NOT trip; the glob is `qa-*` prefix only. Adopted siblings pass.
10. **`finalizing-workflow` safety-net trips on a manually-named `qa-foo.test.ts` outside the workflow** — trips; user must rename or remove. Acceptable false positive (the convention is reserved for QA-authored tests).
11. **Squash vs merge-commit policy** — squash-merge hides `qa(test):` and `qa(adopt):` commits from main history; merge-commit shows them. Both are acceptable. No policy enforcement in this feature.
12. **`addressing-qa-findings` invoked without a `qa/test-results/QA-results-{ID}.md`** — skill exits with `failed | no QA artifact at qa/test-results/QA-results-{ID}.md`; orchestrator pauses.
13. **Full-suite build-health gate fails after fix in FR-4 step 4** — `addressing-qa-findings` exits with `failed | full suite gate failed after fix; reverting commit not implemented in v1, manual intervention required`. Orchestrator pauses with `pauseReason: fix-suite-failed`. v1 does NOT auto-revert the fix commit; the developer must manually revert or amend. This is a deliberate v1 limitation; v2 may add an auto-revert path. The QA test files remain on the branch (they will be caught by the safety net at finalize if not adopted).
14. **Partial-success adoption (FR-5 aggregation)** — On the first `adopt-qa-test.sh` exit-2 across multiple QA test files, `addressing-qa-findings` aborts the loop. Already-moved files remain at their `*.qa.*` sibling paths (committed, not reverted). The skill returns `failed | adoption failed for <path>; <N> adopted, <M> remaining`. Orchestrator pauses with `pauseReason: adoption-failed`. User adopts the remaining files manually, fixes the `adopt-qa-test.sh` exit-2 cause, or removes the offending QA test file. The orchestrator does NOT auto-resume after manual fix; user re-invokes.
15. **User resumes from `qa-loop-exhausted` pause with `--qa-loop-cap <N>`** — counter is reset to 0; the workflow continues with the elevated cap. The audit trail in `.sdlc/workflows/{ID}.json` records the cap change as a state event so the loop history remains traceable.
16. **User resumes from `qa-loop-exhausted` pause with "approve advance"** — counter is preserved (informational); orchestrator advances to `finalizing-workflow`. The safety-net check (FR-9) WILL trip because QA test files remain on the branch — user is expected to manually adopt or `rm` the files first, then re-invoke advance. (This is by design: there is no implicit "force merge with QA files" path.)
17. **v1 user on Python or Go project** — pytest and go-test are out of FR-5 v1 dispatch; the FR-9 safety net's `qa-*.py` / `qa-*.go` globs are forward-compatible no-ops (they will never match in v1). When v1.x adds adoption support for those frameworks, FR-9 pattern enablement and FR-5 dispatch MUST land in lockstep — enabling FR-9 patterns ahead of FR-5 dispatch would strand `qa-*.py` / `qa-*.go` files at the safety net with no in-skill adoption path. Conversely, enabling FR-5 dispatch ahead of FR-9 patterns would silently allow leakage to main. The lockstep constraint is the rollout invariant for those languages.

## Testing Requirements

### Unit Tests (Vitest)

- `tests/unit/orchestrating-workflows.test.ts` — verdict-branching dispatch table for all four verdicts
- `tests/unit/orchestrating-workflows.test.ts` — `qaFixAttempts` increment + cap pause path
- `tests/unit/workflow-state.test.ts` — new fields persistence (`qaFixAttempts`, `qaLastVerdict`, `adoptedTests`)
- `tests/unit/shared-scripts.test.ts` — set-based parity assertion (replacement for the hard-coded 14)

### Integration / Bats Tests

- `tests/bats/skills/executing-qa/re-qa-mode.bats` — auto-detect prior QA tests and re-execute without regenerating
- `tests/bats/skills/addressing-qa-findings/adopt-qa-test.bats` — happy path (Vitest), happy path (Bats), exit-2 paths (no peer, multiple peers, undeterminable SUT)
- `tests/bats/skills/finalizing-workflow/safety-net.bats` — trips on `qa-*` prefix; passes on `*.qa.*` sibling
- `tests/bats/skills/orchestrating-workflows/qa-loop.bats` — `ISSUES-FOUND → addressing-qa-findings → re-QA PASS → finalize` end-to-end

### Manual Testing

- Run a real `ISSUES-FOUND` workflow against a known-buggy fixture branch; confirm the loop completes within N=2; confirm adoption produces a `*.qa.*` sibling; confirm the safety-net check passes; confirm finalize merges cleanly
- Confirm an `EXPLORATORY-ONLY` workflow advances directly to finalize with no adoption attempted
- Confirm an `ERROR` verdict pauses with `qa-error` and does not invoke `addressing-qa-findings`

## Future Enhancements

- **v2 adoption (issue #265)** — AST-merge of QA tests into the existing peer test file as new `it`/`describe` blocks; periodic consolidation/pruning of accumulated `*.qa.*` siblings into their parents
- **Loop-cap configurability** — promote `N=2` to a configurable value if observed agent behavior justifies it
- **AST-aware import rewriting** during adoption (deferred from v1 per design 3.9)
- **Cross-workflow QA test reuse** — recognize when an adopted QA test for FEAT-X covers a finding raised by FEAT-Y; skip re-authoring (out of scope for v1)

## Acceptance Criteria

- [ ] `executing-qa` no longer leaks `qa-<dimension>` prefixed files past merge (verified by `finalizing-workflow` safety-net)
- [ ] New `addressing-qa-findings` skill exists at `plugins/lwndev-sdlc/skills/addressing-qa-findings/SKILL.md` with developer persona
- [ ] `addressing-qa-findings` consumes `qa/test-results/QA-results-{ID}.md`, reproduces failures, writes production fixes, and runs adoption
- [ ] `addressing-qa-findings` operates in two distinct phases (fix, adopt) with auto-detected dispatch from the `{qaLastVerdict, qaFixAttempts, adoptedTests}` triple per FR-4 (fix iff `qaLastVerdict == ISSUES-FOUND` AND `adoptedTests` empty; adopt iff `qaLastVerdict == PASS` AND `qaFixAttempts > 0` AND `adoptedTests` empty); emits the corresponding return contract for each
- [ ] `adopt-qa-test.sh` deterministically renames QA tests to `{module}.qa.{ext}` siblings; supports Vitest and Bats; exits 2 on unresolvable SUT
- [ ] Orchestrator branches to `addressing-qa-findings` (fix phase) on `ISSUES-FOUND` verdict; loops with cap N=2; pauses with `qa-loop-exhausted` on exhaustion
- [ ] `EXPLORATORY-ONLY` and initial-run `PASS` verdicts advance directly to `finalizing-workflow` (no fix loop)
- [ ] `PASS` verdict in re-QA mode (after fix phase) triggers `addressing-qa-findings` adopt phase, then advance
- [ ] `ERROR` verdict pauses with `qa-error` (no fix loop)
- [ ] `finalizing-workflow` safety-net blocks merge if any `qa-*` file remains; allows `*.qa.*` siblings
- [ ] `tests/unit/shared-scripts.test.ts:102-117` parity assertion is set-based; tolerates `*.qa.bats` siblings; hard-coded `14` literal at line 107 is removed
- [ ] All length-based assertions over QA-relevant directories are audited and either relaxed or documented as intentional
- [ ] `CLAUDE.md` documents the new QA lifecycle and `*.qa.*` adoption convention
- [ ] Workflow state schema includes `qaFixAttempts`, `qaLastVerdict`, `adoptedTests`
- [ ] QA artifact embeds test source under each finding's `## Reproduction` section
- [ ] FR-12: `executing-qa` re-QA mode overwrites `qa/test-results/QA-results-{ID}.md` (does not version per-attempt); Bats fixture asserts the artifact matches the latest run
- [ ] FR-13: no skill or script other than `addressing-qa-findings` deletes any `qa-*` file (assertion via grep over plugin scripts and a Bats negative test)
- [ ] Re-QA loop attempt = full pass over all findings + 1 re-QA execution (per FR-8); per-finding loops do NOT consume separate attempts; verified by the loop fixture
- [ ] `--qa-loop-cap <N>` flag accepted on resume from `qa-loop-exhausted`; resets counter and continues
- [ ] Full test suite green; new behaviors covered by Vitest or Bats at the canonical leaf
- [ ] End-to-end Bats fixture exercises `ISSUES-FOUND → addressing-qa-findings (fix) → re-QA → addressing-qa-findings (adopt) → finalize` without shortcuts
- [ ] FR-2: `render-qa-results.sh` emits language-aware fences (e.g. ` ```typescript `, ` ```bash `) and a path-comment header on the embedded QA test source under each finding's `## Reproduction` section
- [ ] FR-3: re-QA mode is entered iff the `qa-baseline` marker file `.sdlc/qa/.executing-qa-baseline-{ID}` is present AND at least one file matches the v1 glob set (`tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`)
- [ ] FR-4: fix-phase pre-check fails fast on a dirty working tree with the literal message `failed | working tree dirty; commit or stash before re-running`; no auto-stash
- [ ] FR-5: on the first `adopt-qa-test.sh` exit-2 across N candidate files, the M previously-moved files remain at their `*.qa.*` paths (committed, not reverted), `adoptedTests` length equals M, and the skill returns `failed | adoption failed for <path>; <N> adopted, <M> remaining`
- [ ] FR-12: `executing-qa` commits `qa/test-results/QA-results-{ID}.md` before returning, with message `qa({ID}): record QA results` (initial) or `qa({ID}): re-record QA results after fix attempt {N}` (re-QA)
- [ ] FR-7a: `workflow-state.sh` `cmd_pause` accepts the four new pause reasons (`qa-error`, `qa-loop-exhausted`, `fix-suite-failed`, `adoption-failed`); unknown reasons still exit 1; rejection message enumerates all seven accepted values literally and is pinned by a Bats assertion
- [ ] FR-8: `--approve-advance` and `--qa-loop-cap <N>` flags accepted by `orchestrating-workflows` resume; unknown flags rejected with exit 2; passing both flags on the same invocation exits 2 with `Error: --approve-advance and --qa-loop-cap are mutually exclusive`
