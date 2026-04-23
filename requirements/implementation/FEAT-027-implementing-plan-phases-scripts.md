# Implementation Plan: `implementing-plan-phases` Scripts (FEAT-027)

## Overview

Collapse the deterministic prose inside `implementing-plan-phases` into six skill-scoped shell scripts so every per-phase invocation replaces its Step 2 (phase selection), Step 3 (status to in-progress), Step 6 (deliverable checkoff), Step 7 (verification), Step 8 (commit and push), Step 9 (status to complete), and Step 10 pre-PR check prose with single script calls. The plugin-shared foundation scripts `build-branch-name.sh` and `ensure-branch.sh` (items 5.3 / 5.4) already exist and are dependencies, not in scope.

All six scripts live under `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/` (a new directory — the skill currently has no skill-scoped scripts) with bats fixtures under `scripts/tests/`. The SKILL.md + references rewrite (FR-7) lands in Phase 4 after all scripts are implemented and tested, preserving the running skill's behavior mid-workflow.

The plan follows the four-layer sequencing established by FEAT-025 and used again by FEAT-026: pure/cheap scripts first, composite scripts with external dependencies later, SKILL.md cutover last. Every script ships with its bats fixture in the same phase — tests are never deferred.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-027 | [#185](https://github.com/lwndev/lwndev-marketplace/issues/185) | [FEAT-027-implementing-plan-phases-scripts.md](../features/FEAT-027-implementing-plan-phases-scripts.md) | Medium | Medium | Pending |

## Recommended Build Sequence

### Phase 1: Directory Scaffold + Plan-Document Scripts — `next-pending-phase.sh` (FR-1), `plan-status-marker.sh` (FR-2), `verify-all-phases-complete.sh` (FR-6)

**Feature:** [FEAT-027](../features/FEAT-027-implementing-plan-phases-scripts.md) | [#185](https://github.com/lwndev/lwndev-marketplace/issues/185)
**Status:** ✅ Complete

#### Rationale

These three scripts share a single concern: reading and editing the implementation plan document. None of them touch `git`, `npm`, or any external tool — they operate on the plan file only, making them fully testable without stubs.

Grouping them together in Phase 1 is the right sequencing for four reasons:

1. **Shared fixture infrastructure**: all three scripts parse `### Phase N:` blocks and `**Status:**` lines from the same document format. A single set of bats fixtures (`minimal-plan.md`, `multi-phase-plan.md`, `fenced-status-plan.md`) serves all three scripts — the fixture investment is made once.
2. **Fence-awareness is load-bearing for all three**: FR-1, FR-2, and FR-6 all must skip `**Status:**` lines inside fenced code blocks. Implementing and testing this pattern once in Phase 1 means Phase 2's `check-deliverable.sh` (which also needs fence-awareness for `- [ ]` lines) can reuse the verified pattern rather than re-deriving it.
3. **FR-6 is trivially narrow**: `verify-all-phases-complete.sh` is essentially a read-only companion to `next-pending-phase.sh` — both parse the same phase/status structure. Deferring FR-6 to a later phase would split closely related logic across phases for no benefit.
4. **Establishes the `scripts/` and `scripts/tests/` directories** that Phases 2 and 3 require.

No PATH-shadowing stubs are needed for Phase 1 tests — pure bash + POSIX utilities only.

#### Implementation Steps

1. Create the new directories:
   - `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/`
   - `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/`
   - `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/fixtures/`

2. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/next-pending-phase.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment block: purpose, signature, exit codes, optional `jq` dependency.
   - Signature: `next-pending-phase.sh <plan-file>`. Exit `2` on missing arg with usage error to stderr. Exit `1` on file not found / unreadable.
   - Parse every `### Phase <N>: <name>` heading and each block's `**Status:**` line; skip lines inside fenced code blocks (`` ``` `` / `~~~` toggle).
   - Recognize three canonical states: `Pending`, `🔄 In Progress`, `✅ Complete`.
   - Selection rule (two-tier): for each `Pending` phase, check (a) all lower-numbered phases are `✅ Complete` and (b) any explicit `**Depends on:** Phase <N>[, Phase <M>...]` line adjacent to the status is satisfied. Return the lowest-numbered phase passing both checks.
   - Special outputs:
     - All phases `✅ Complete` → stdout `{"phase":null,"reason":"all-complete"}`, exit `0`.
     - A phase is `🔄 In Progress` → stdout `{"phase":<N>,"name":"<name>","reason":"resume-in-progress"}`, exit `0`.
     - Pending phase exists but prerequisites not satisfied → stdout `{"phase":null,"reason":"blocked","blockedOn":[<N>,...]}`, exit `0`.
   - Happy-path success: stdout `{"phase":<N>,"name":"<name>"}`, exit `0`.
   - Exit `1` on no `### Phase` blocks found or a block missing its `**Status:**` line.
   - Use `jq` for JSON assembly when available; pure-bash `printf` fallback otherwise.
   - `chmod +x`.

3. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/plan-status-marker.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment block: purpose, signature, exit codes.
   - Signature: `plan-status-marker.sh <plan-file> <phase-N> <state>`. Exit `2` on missing/malformed args (`<phase-N>` must be a positive integer; `<state>` must be one of `Pending`, `in-progress`, `complete`).
   - Accept canonical state tokens:
     - `Pending` → writes `**Status:** Pending`
     - `in-progress` → writes `**Status:** 🔄 In Progress` (script emits the emoji)
     - `complete` → writes `**Status:** ✅ Complete`
   - Scope the `**Status:**` edit to the `### Phase <phase-N>:` block only (bounded by the next `### Phase` heading or end-of-file).
   - CRLF-safe: `tr -d '\r'` on read; preserve original line endings on write.
   - Fence-aware: skip `**Status:**` lines inside `` ``` `` / `~~~` fenced blocks.
   - Idempotent: if the target line already matches the requested state, emit `already set` on stdout, exit `0` without rewriting.
   - Emit `transitioned` on stdout on successful write, exit `0`.
   - Exit `1` on plan not found, no matching phase block, or no `**Status:**` line in matched block.
   - `chmod +x`.

4. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/verify-all-phases-complete.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment block: purpose, signature, exit codes.
   - Signature: `verify-all-phases-complete.sh <plan-file>`. Exit `2` on missing arg. Exit `1` on file not found / unreadable.
   - Fence-aware: parse `**Status:**` lines only outside fenced blocks.
   - Three outcomes:
     - All phases `✅ Complete` → stdout `all phases complete`, exit `0`.
     - Any phase non-complete → stdout JSON `{"incomplete":[{"phase":<N>,"name":"...","status":"Pending|in-progress"},...]}`, exit `1`.
     - No `### Phase` blocks found → stderr `[error] no phase blocks found in plan`, exit `1`.
   - `chmod +x`.

5. Create `scripts/tests/fixtures/minimal-plan.md` — a two-phase plan with Phase 1 `✅ Complete` and Phase 2 `Pending`. Used by all three scripts' bats tests.

6. Create `scripts/tests/fixtures/multi-phase-plan.md` — a four-phase plan with mixed statuses including one `🔄 In Progress` phase and one with an explicit `**Depends on:**` line. Used by FR-1 dependency-ordering tests.

7. Create `scripts/tests/fixtures/fenced-status-plan.md` — a plan containing `**Status:**` lines inside fenced code blocks that MUST NOT be read as real status. Used by fence-awareness tests for all three scripts.

8. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/next-pending-phase.bats`:
   - Happy-path tests:
     - Phase 1 Pending, no prerequisites → stdout `{"phase":1,"name":"..."}`, exit `0`.
     - Phase 1 Complete, Phase 2 Pending → stdout `{"phase":2,...}`, exit `0`.
     - All phases Complete → stdout `{"phase":null,"reason":"all-complete"}`, exit `0`.
     - Phase 1 In Progress → stdout `{...,"reason":"resume-in-progress"}`, exit `0`.
     - Phase 2 Pending but Phase 1 not complete → stdout `{...,"reason":"blocked","blockedOn":[1]}`, exit `0`.
     - Explicit `**Depends on:** Phase 2` on Phase 3 → blocked until Phase 2 is Complete.
   - Fence-awareness: `**Status:**` line in fenced block not counted as real status → phase treated as no-status, exit `1`.
   - Error tests:
     - Missing arg → exit `2`.
     - Non-existent file → exit `1`.
     - Plan with no `### Phase` blocks → exit `1`.
     - Phase block with no `**Status:**` line → exit `1`.

9. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/plan-status-marker.bats`:
   - Happy-path tests:
     - Transition Phase 1 to `in-progress` → file updated to `**Status:** 🔄 In Progress`, stdout `transitioned`, exit `0`.
     - Transition Phase 1 to `complete` → file updated to `**Status:** ✅ Complete`, stdout `transitioned`, exit `0`.
     - Transition Phase 1 to `Pending` → file updated to `**Status:** Pending`, stdout `transitioned`, exit `0`.
     - Already-correct state → stdout `already set`, exit `0`, file unchanged.
     - Multiple phases in plan → only the targeted phase's status is modified; other phases unchanged.
   - Fence-awareness: `**Status:**` inside fenced block not modified when it is inside a fenced block.
   - Error tests:
     - Missing any of the three args → exit `2`.
     - Non-positive or non-integer `<phase-N>` → exit `2`.
     - Unknown `<state>` token → exit `2`.
     - Non-existent plan file → exit `1`.
     - Phase number not in plan → exit `1`.
     - Phase block with no `**Status:**` line → exit `1`.

10. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/verify-all-phases-complete.bats`:
    - Happy-path tests:
      - All phases `✅ Complete` → stdout `all phases complete`, exit `0`.
      - One phase `Pending` → stdout JSON with `incomplete` array, exit `1`.
      - One phase `🔄 In Progress` → stdout JSON with `incomplete` array, exit `1`.
      - Mixed phases (Complete + Pending + In Progress) → incomplete array lists non-complete phases, exit `1`.
    - Fence-awareness: fenced `**Status:**` lines not counted.
    - Error tests:
      - Missing arg → exit `2`.
      - Non-existent file → exit `1`.
      - Plan with no `### Phase` blocks → stderr `[error] no phase blocks found`, exit `1`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/` (directory)
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/` (directory)
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/fixtures/` (directory)
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/next-pending-phase.sh`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/plan-status-marker.sh`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/verify-all-phases-complete.sh`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/fixtures/minimal-plan.md`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/fixtures/multi-phase-plan.md`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/fixtures/fenced-status-plan.md`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/next-pending-phase.bats`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/plan-status-marker.bats`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/verify-all-phases-complete.bats`

---

### Phase 2: Phase-Scoped Deliverable Checkoff — `check-deliverable.sh` (FR-3)

**Feature:** [FEAT-027](../features/FEAT-027-implementing-plan-phases-scripts.md) | [#185](https://github.com/lwndev/lwndev-marketplace/issues/185)
**Status:** ✅ Complete
**Depends on:** Phase 1

#### Rationale

`check-deliverable.sh` is the FEAT-027 sibling of the plugin-shared `check-acceptance.sh` — it adds phase-scoping and a numeric-index dispatch on top of `check-acceptance.sh`'s text-substring semantics. It depends on Phase 1 for two reasons:

1. **Phase-block parsing foundation**: Phase 1 establishes and tests the `### Phase <N>:` block-boundary logic (heading → next heading or EOF) and the fence-tracking pattern for `- [ ]` / `- [x]` lines. `check-deliverable.sh` reuses the same block-boundary logic for scoping and the same fence-awareness pattern for deliverable lines. Implementing Phase 2 before Phase 1 would mean re-deriving these patterns separately and then reconciling them — a higher risk of divergence.
2. **Fixture reuse**: the `minimal-plan.md` and `fenced-status-plan.md` fixtures from Phase 1 already contain `- [ ]` / `- [x]` deliverable lines inside phase blocks. Phase 2's bats fixture can extend these or create a dedicated `deliverables-plan.md` fixture that also contains fenced-block deliverables (the fence-awareness test for `- [ ]` lines).

`check-deliverable.sh` is placed in its own phase (rather than bundled with Phase 1) because its exit-code shape deliberately diverges from the other FEAT-027 scripts: it adopts `check-acceptance.sh`'s `0`/`1`/`2` (ambiguous)/`3` (missing arg) shape, not the generic `0`/`1`/`2` (missing arg) shape. This one-off deserves focused review and test coverage rather than being folded into the larger Phase 1 batch.

#### Implementation Steps

1. Study `plugins/lwndev-sdlc/scripts/check-acceptance.sh` to confirm the exit-code shape, fence-tracking logic, and stdout/stderr conventions that `check-deliverable.sh` must mirror exactly.

2. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/check-deliverable.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment block: purpose, signature, exit codes (document the one-off `2`=ambiguous / `3`=missing-arg shape explicitly and reference the NFR-2 rationale).
   - Signature: `check-deliverable.sh <plan-file> <phase-N> <idx-or-text>`. Exit `3` on missing / malformed args (`<phase-N>` must be a positive integer).
   - Exit `1` on file not found / unreadable.
   - Scope all deliverable matching to the `### Phase <phase-N>:` block (same bounds as Phase 1's `plan-status-marker.sh`).
   - Only `- [ ]` / `- [x]` lines outside fenced blocks within the phase block are considered.
   - Dispatch on `<idx-or-text>`:
     - Matches `^[0-9]+$` → treat as 1-based index into all deliverable lines (`- [ ]` and `- [x]` in document order) within the phase block. Out-of-range → stderr `error: deliverable index <N> out of range (phase has <M> deliverables)`, exit `1`.
     - Contains any non-digit → treat as literal substring matcher (identical semantics to `check-acceptance.sh`).
   - Idempotent: target line already `- [x]` → stdout `already checked`, exit `0`.
   - On `- [ ]` → flip to `- [x]`, stdout `checked`, exit `0`.
   - Ambiguity check (text mode only): computed over `- [ ]` lines only; `- [x]` lines containing the substring are ignored for ambiguity. Multiple `- [ ]` matches → stderr `error: ambiguous — <K> lines match`, exit `2`. Zero `- [ ]` but ≥ 1 `- [x]` → stdout `already checked`, exit `0`. No `- [ ]` and no `- [x]` match → stderr `error: deliverable not found`, exit `1`.
   - Exit `1` on no phase block matching `<phase-N>`.
   - `chmod +x`.

3. Create `scripts/tests/fixtures/deliverables-plan.md` — a plan containing phase blocks with `- [ ]` and `- [x]` deliverable lines including:
   - A phase with exactly three deliverables (one already checked, two unchecked) for index-dispatch tests.
   - A phase containing a fenced code block with `- [ ]` lines that MUST NOT be flipped.
   - A phase with two unchecked deliverables whose descriptions share a common substring (for ambiguity tests).

4. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/check-deliverable.bats`:
   - Follow the bats fixture setup/teardown pattern from `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/verify-references.bats` (fixture-local `FIXTURE_DIR` via `mktemp -d`, per-test `setup()` / `teardown()`, PATH not mutated in parent shell).
   - Index-dispatch tests:
     - Index `1` on a 3-deliverable phase → first deliverable checked, stdout `checked`, exit `0`.
     - Index `2` on a 3-deliverable phase → second deliverable checked.
     - Index out of range (e.g., `4` on a 3-deliverable phase) → stderr `error: deliverable index 4 out of range`, exit `1`.
     - Index `1` targeting an already-checked deliverable → stdout `already checked`, exit `0`.
   - Text-dispatch tests:
     - Unique substring match on unchecked line → `checked`, exit `0`.
     - Already-checked match with no other unchecked → `already checked`, exit `0`.
     - Ambiguous substring (matches two unchecked lines) → stderr `error: ambiguous`, exit `2`.
     - Substring present only in fenced block → exit `1` (not found outside fence).
   - Phase-scoping tests:
     - Substring that matches a deliverable in a different phase → exit `1` (not found in target phase).
   - Error tests:
     - Missing args (zero, one, or two of the three) → exit `3`.
     - Non-positive `<phase-N>` → exit `3`.
     - Non-existent plan file → exit `1`.
     - Phase number not in plan → exit `1`.
     - Fence-awareness: fenced `- [ ]` line is not flipped when the substring matches it.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/check-deliverable.sh`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/fixtures/deliverables-plan.md`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/check-deliverable.bats`

---

### Phase 3: Composite Scripts — `verify-phase-deliverables.sh` (FR-4), `commit-and-push-phase.sh` (FR-5)

**Feature:** [FEAT-027](../features/FEAT-027-implementing-plan-phases-scripts.md) | [#185](https://github.com/lwndev/lwndev-marketplace/issues/185)
**Status:** ✅ Complete
**Depends on:** Phase 1

#### Rationale

These are the two scripts with external tool dependencies (`npm` for FR-4, `git` for FR-5). They are grouped together in Phase 3 for three reasons:

1. **PATH-shadowing stub infrastructure**: both scripts require bats stubs. FR-4 needs a no-`npm` stub (PATH manipulation isolating `npm` absence); FR-5 needs `git` stubs for `add / commit / push / rev-parse`. Establishing the stub pattern once in Phase 3 mirrors exactly what FEAT-026 did with `gh` / `git grep` stubs in its Phase 2. After Phase 1 has verified the fixture infrastructure, Phase 3 can add stubs to the same `scripts/tests/` directory without ceremony.
2. **Phase-block parsing already verified**: FR-4 must parse the `#### Deliverables` subsection inside a phase block to extract backticked file paths. Phase 1 already established and tested the `### Phase <N>:` block-boundary logic. FR-4 builds directly on that verified pattern.
3. **Independence from each other**: FR-4 and FR-5 are otherwise fully independent (FR-4 reads the plan and runs npm; FR-5 runs git on the working tree). Grouping them in Phase 3 rather than further splitting across phases minimizes the number of `commit-and-push-phase.sh` calls needed during development.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/verify-phase-deliverables.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment block: purpose, signature, exit codes, optional `jq` and `npm` dependencies. Note graceful-degradation behavior when `npm` is absent.
   - Signature: `verify-phase-deliverables.sh <plan-file> <phase-N>`. Exit `2` on missing / malformed args. Exit `1` on file not found / unreadable / no phase block matching.
   - Parse the `#### Deliverables` subsection of the `### Phase <phase-N>:` block for every `- [ ]` / `- [x]` entry. Extract the backticked path from the start of each entry (pattern: `` - [x] `<path>` ``). Lines without a leading backtick are skipped (non-file deliverables).
   - Detect coverage threshold: grep the `## Testing Requirements` section and the phase block for the literal token `coverage` or a `[0-9]+%` pattern. If detected, run `npm run test:coverage`; otherwise emit `"coverage":"skipped"`.
   - Sequential execution (fails fast per check):
     1. File existence: `[ -e "$path" ]` per extracted path. Populate `files.ok` and `files.missing`.
     2. `npm test` — capture exit code + last 50 lines of output.
     3. `npm run build` — capture exit code + last 50 lines of output.
     4. `npm run test:coverage` (conditional on detection heuristic above).
   - Graceful degradation: if `npm` not on PATH, emit `[warn] verify-phase-deliverables: npm not found; skipping test/build/coverage checks.` to stderr; set `test`, `build`, `coverage` all to `"skipped"`. Exit `0` only when `files.missing` is empty.
   - Emit one JSON object on stdout (exact shape per FR-4): `files.ok`, `files.missing`, `test`, `build`, `coverage`, and `output` (populated only for failing checks).
   - Aggregate exit code: `0` only when `files.missing` is empty AND `test`/`build`/`coverage` are `pass` or `skipped`. Otherwise exit `1`.
   - Use `jq` for JSON assembly when available; pure-bash `printf` fallback otherwise.
   - `chmod +x`.

2. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/commit-and-push-phase.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment block: purpose, signature, exit codes, canonical commit message format, push-failure recovery pattern.
   - Signature: `commit-and-push-phase.sh <FEAT-ID> <phase-N> <phase-name>`. Exit `2` on missing / malformed args:
     - `<FEAT-ID>` must match `^(FEAT|CHORE|BUG)-[0-9]+$`.
     - `<phase-N>` must match `^[1-9][0-9]*$`.
     - `<phase-name>` must be non-empty / non-whitespace.
   - Derive commit type prefix from ID prefix: `FEAT-` → `feat`, `CHORE-` → `chore`, `BUG-` → `fix`.
   - Canonical commit message: `<type-prefix>(<ID>): complete phase <N> - <phase-name>`.
   - Execution sequence (fails fast):
     1. `git status --porcelain=v1` — empty output → stderr `error: no changes to commit`, exit `1`.
     2. `git add -A`.
     3. `git commit -m "<canonical message>"` — hook rejection surfaces stderr verbatim, exit `1`.
     4. Determine current branch: `git rev-parse --abbrev-ref HEAD`.
     5. Check upstream: `git rev-parse --abbrev-ref --symbolic-full-name @{u}`.
     6. Push: `git push [-u origin <branch>]` (use `-u` only when no upstream is set).
     7. On push success: stdout `pushed <branch>`, exit `0`.
     8. On push failure: emit `git push` stderr verbatim + `[error] push failed; see Push Failure Recovery in SKILL.md` to stderr, exit `1`.
   - `chmod +x`.

3. Create `scripts/tests/fixtures/verify-deliverables-plan.md` — a plan phase whose `#### Deliverables` section contains:
   - Two entries with leading backticked paths.
   - One entry without a backtick (non-file deliverable, should be skipped from file-existence check).
   - A coverage-threshold token (`coverage`) in the Testing Requirements section.

4. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/verify-phase-deliverables.bats`:
   - Follow the PATH-shadowing stub pattern from `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/verify-references.bats` for `npm` absence testing: per-test `setup()` creates `FIXTURE_DIR="$(mktemp -d)"` with a `stubs/` subdirectory containing no `npm` binary; `run` calls pass `PATH="${FIXTURE_DIR}/stubs:${PATH}"` inline; `teardown()` deletes `FIXTURE_DIR`. Parent shell PATH is never mutated.
   - File-existence tests:
     - All extracted paths exist (stub via real tmpdir files) → `files.ok` populated, `files.missing` empty.
     - One path missing → `files.missing` contains the path, exit `1`.
     - Non-file deliverable (no leading backtick) → not in `files.ok` or `files.missing`.
   - `npm` graceful-degradation tests:
     - `npm` absent from PATH → `test`/`build`/`coverage` all `"skipped"`, `[warn]` to stderr, exit `0` when all files present.
   - Coverage-heuristic tests:
     - Plan phase with no coverage token → `"coverage":"skipped"`.
     - Plan phase with `coverage` token → `npm run test:coverage` invoked (stubbed).
   - JSON shape tests:
     - `output` keys only present for failing checks.
     - `files.ok` and `files.missing` always present.
   - Error tests:
     - Missing args → exit `2`.
     - Non-existent plan file → exit `1`.
     - Phase number not in plan → exit `1`.

5. Write `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/commit-and-push-phase.bats`:
   - Use PATH-shadowing stubs for `git`:
     - Happy-path stub: `git status --porcelain=v1` emits a modified file; `git add -A` succeeds; `git commit` succeeds; `git rev-parse --abbrev-ref HEAD` emits `feat/FEAT-027-implementing-plan-phases-scripts`; `git rev-parse --abbrev-ref --symbolic-full-name @{u}` exits non-zero (no upstream); `git push -u origin <branch>` succeeds.
   - Canonical message tests:
     - `FEAT-027 1 "scripts scaffold"` → commit message `feat(FEAT-027): complete phase 1 - scripts scaffold`.
     - `CHORE-003 2 "update deps"` → commit message `chore(CHORE-003): complete phase 2 - update deps`.
     - `BUG-012 3 "fix null check"` → commit message `fix(BUG-012): complete phase 3 - fix null check`.
   - Upstream-detection tests:
     - No upstream → `git push -u origin <branch>` used.
     - Upstream already set → bare `git push` used.
   - Error tests:
     - Empty `git status` output (nothing to commit) → stderr `error: no changes to commit`, exit `1`.
     - `git commit` exits non-zero (hook rejection) → exit `1`, hook stderr surfaced.
     - `git push` exits non-zero → stderr includes `[error] push failed`, exit `1`.
     - Missing args → exit `2`.
     - Malformed `<FEAT-ID>` (e.g., `feat-027`, `FEATURE-001`) → exit `2`.
     - Non-positive `<phase-N>` → exit `2`.
     - Empty `<phase-name>` → exit `2`.
     - Whitespace-only `<phase-name>` → exit `2`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/verify-phase-deliverables.sh`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/commit-and-push-phase.sh`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/fixtures/verify-deliverables-plan.md`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/verify-phase-deliverables.bats`
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/commit-and-push-phase.bats`

---

### Phase 4: SKILL.md + References Rewrite (FR-7) + Caller Audit (FR-8) + Final Validation

**Feature:** [FEAT-027](../features/FEAT-027-implementing-plan-phases-scripts.md) | [#185](https://github.com/lwndev/lwndev-marketplace/issues/185)
**Status:** ✅ Complete
**Depends on:** Phases 1, 2, and 3

#### Rationale

The SKILL.md rewrite is the user-visible cutover: it switches `implementing-plan-phases` from a prose-implementation document (173 lines today) to a reference-and-pointer document. This phase must land last — after all six scripts and their fixtures exist and bats tests pass — for two reasons:

1. **Self-bootstrapping safety**: the `implementing-plan-phases` skill will be used to implement FEAT-027's own phases via the orchestrator. If the SKILL.md rewrite happened before the scripts existed, the skill would point at nonexistent scripts. Phases 1–3 ensure every script pointer in the rewritten SKILL.md is backed by a tested, working script at merge time.
2. **Pointer accuracy**: the rewritten SKILL.md references specific script paths and output shapes. Those shapes cannot be accurately described until the scripts are implemented and their contracts verified by bats tests.

The `step-details.md` rewrite and `workflow-example.md` audit are bundled here: they must stay in sync with SKILL.md and are also blocked on the scripts existing. The token-savings measurement (NFR-4) is gated here — it cannot be measured until the scripts are live and the SKILL.md actively delegates to them.

#### Implementation Steps

1. Rewrite `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`:
   - **Retain verbatim** (these are the public contract):
     - YAML frontmatter (`name`, `description`, `allowed-tools`, `argument-hint`).
     - `When to Use` section.
     - `Arguments` section.
     - `Quick Start` intro — update Step 2 pointer to say "Run `next-pending-phase.sh`" instead of prose; retain the remaining steps' structure.
     - `Output Style` section with all lite-narration rules, load-bearing carve-outs list, and fork-to-orchestrator return contract.
     - `Workflow` checklist block.
     - `Phase Structure` section.
     - `Branch Naming` section.
     - `Verification` section.
     - `References` section.
     - Step 4 (Branch Strategy) prose — already references `build-branch-name.sh` + `ensure-branch.sh`.
     - Step 5 (Load Steps into Todos) prose — TodoWrite usage is not a script candidate.
     - The TDD, Code Organization, Reusing Existing Code, and Following Code Organization prose inside Step 6 — model-reasoning concerns.
     - The "Push Failure Recovery" prose inside Step 8 — per FR-5, conflict resolution stays in prose. **Add a new paragraph** at the end of Push Failure Recovery documenting the do-not-re-run-the-script caller pattern per Edge Case 11: after `commit-and-push-phase.sh` exits `1` with a push-failure error, the caller resolves the conflict via `git fetch origin` + `git rebase origin/<branch>` + `git push` directly — NOT via re-running `commit-and-push-phase.sh`, because a clean tree after resolution would trip the script's "no changes to commit" sanity gate.
   - **Replace with script pointers** (one paragraph each, followed by the canonical invocation):
     - Step 2 "Identify Target Phase / Verify prerequisites" → pointer at `next-pending-phase.sh`. Document the four output shapes (happy path, all-complete, resume-in-progress, blocked) and how callers dispatch on them.
     - Step 3 "Update Implementation Doc Status → 🔄 In Progress" → pointer at `plan-status-marker.sh` with `<state>=in-progress`. Document `transitioned` / `already set` stdout and `1` exit on no matching phase.
     - Step 6 "check off each deliverable" sub-bullet → pointer at `check-deliverable.sh`. Document the two dispatch modes (numeric index vs. text substring) and the exit-code shape (`0`=checked/already-checked, `1`=not-found, `2`=ambiguous, `3`=missing-arg).
     - Step 7 "Run Tests / Build Project / Check Coverage / Verify Files Exist" → pointer at `verify-phase-deliverables.sh`. Document the JSON stdout shape and the aggregate exit code.
     - Step 8 "Stage Changed Files / Commit with Phase-Traceable Message / Push to Remote" → pointer at `commit-and-push-phase.sh`. Keep the Push Failure Recovery prose (with the new do-not-re-run paragraph).
     - Step 9 "Update Plan Status → ✅ Complete" → pointer at `plan-status-marker.sh` with `<state>=complete`.
     - Step 10 "Check All Phases Are Complete" sub-block → pointer at `verify-all-phases-complete.sh`. Keep the rest of Step 10 (Create Pull Request via `create-pr.sh`) unchanged.
   - **Net size target**: ≥ 20% line-count reduction from 173 lines (must reach ≤ 138 lines). The removals (Step 2 ~8 lines, Step 3 ~5 lines, Step 6 checkoff sub-bullet ~4 lines, Step 7 ~8 lines, Step 8 commit-push ~10 lines, Step 9 ~5 lines, Step 10 check ~4 lines) total ~44 lines of deletion vs. ~15 lines of pointer insertion for a net of ~29 lines — a ~17% reduction at minimum with conservative counting. The 20% target (~34 line reduction) is achievable by trimming any inline example code blocks that duplicate the script's own help output.
   - Run `npm run validate` to confirm `allowed-tools` list still passes.

2. Rewrite `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md`:
   - Apply the same retention rules as the SKILL.md rewrite: prose blocks for Steps 2 / 3 / 6-checkoff / 7 / 8-commit-push / 9 / 10-check collapse into script-pointer paragraphs with canonical invocation examples.
   - Retain the TDD, Code Organization, Reusing Existing Code, and Following Code Organization prose.
   - Retain the Push Failure Recovery prose (with the new do-not-re-run paragraph added per FR-7).
   - **Correct the pre-existing mislabel on current line 286**: `**Do not proceed to **Step 10 (Update Plan Status)**` → `**Do not proceed to **Step 9 (Update Plan Status)**`. (Step 10 is "Create Pull Request"; Step 9 is "Update Plan Status". The mislabel has been present since the Step 8/9 split and is not a FEAT-027 regression, but it lives inside prose this rewrite touches.)

3. Audit `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/workflow-example.md`:
   - Check whether the walkthrough example's Step 2 / 3 / 6 / 7 / 8 / 9 / 10 sections reproduce any of the mechanical prose that FR-7 removes. If they do, replace those inline recreations with a reference to the corresponding script. If the walkthrough does not touch those mechanical blocks (i.e., it only narrates decisions and outputs, not the prose mechanics), note "no changes required" in the PR body.

4. Caller audit (FR-8):
   - Confirm `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` and its references do not require changes — the orchestrator dispatches via `Agent` + SKILL.md fork prompts; no stale prose pointers expected.
   - Confirm no other skill SKILL.md files reference `implementing-plan-phases` prose blocks that FR-7 removes.

5. Run `npm test` — confirm all bats tests pass (covering all six scripts from Phases 1–3). Scope the run: `npm test -- --testPathPatterns=implementing-plan-phases | tail -60`.

6. Run `npm run validate` — confirm plugin validation passes.

7. Verify SKILL.md net reduction via `wc -l plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` — must be ≤ 138.

8. **Token-savings measurement (NFR-4)**: run a paired workflow comparison on a representative feature workflow (≥ 4 phases). Capture token counts from the Claude Code conversation state (same methodology as FEAT-022 NFR-5, FEAT-025 NFR-4, FEAT-026 NFR-4). Confirm the measured delta falls within ±30% of the ~6,900 tok/feature-workflow estimate. Document results in the PR body.

9. Manual smoke-test: invoke `/implementing-plan-phases <plan-file> 1` in standalone mode on a fresh fixture plan. Confirm:
   - FR-1 auto-selects Phase 1.
   - FR-2 transitions it to `🔄 In Progress`.
   - FR-3 flips each deliverable to `- [x]`.
   - FR-4 reports all checks passing.
   - FR-5 produces a commit with the canonical message format.
   - FR-2 transitions to `✅ Complete`.
   - FR-6 gates PR creation on all-complete status.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` (rewritten per FR-7; public contract retained; Steps 2/3/6-checkoff/7/8-commit-push/9/10-check replaced with script pointers; net line-count reduction ≥ 20%; Push Failure Recovery updated with do-not-re-run paragraph)
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` (same retention rules as SKILL.md rewrite; mislabel on line 286 corrected; do-not-re-run paragraph added to Push Failure Recovery)
- [x] `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/workflow-example.md` (audited; mechanical prose replaced with script references if applicable, else "no changes required" noted)
- [x] Caller audit complete: `orchestrating-workflows` confirmed no changes needed (no stale prose pointers)
- [x] Passing `npm test` (all bats tests pass)
- [x] Passing `npm run validate` (plugin validated)
- [x] SKILL.md line count verified via `wc -l` (≤ 138)
- [ ] Token-savings measurement per NFR-4 documented in PR body (within ±30% of ~6,900 tok/feature-workflow estimate) — deferred to post-PR (standard pattern)

---

## Shared Infrastructure

- **Skill-scoped scripts directory** — new `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/` and sibling `scripts/tests/` created in Phase 1. Structure mirrors `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/` exactly (FEAT-026 precedent).
- **Fixtures directory** — `scripts/tests/fixtures/` created in Phase 1 with plan-document fixtures, extended in Phases 2 and 3 with deliverable-list and deliverable-verification plan fixtures.
- **Fence-tracking pattern** — established in Phase 1 (for `**Status:**` lines) and reused by Phase 2 (`check-deliverable.sh` for `- [ ]` lines) and Phase 3 (`verify-phase-deliverables.sh` for path extraction). One implementation, tested in Phase 1, reused with confidence across the feature.
- **Block-boundary logic** — `### Phase <N>:` → next `### Phase` heading or EOF. Established in Phase 1 (`next-pending-phase.sh`, `plan-status-marker.sh`, `verify-all-phases-complete.sh`) and reused in Phases 2 and 3 without re-derivation.
- **`jq` vs. pure-bash fallback** — FR-1, FR-4, and FR-6 emit JSON; all three use `jq` when available and pure-bash `printf` otherwise. Consistent with FEAT-025 and FEAT-026 precedent. Declare `jq` as optional in each script's top-of-file comment block.
- **PATH-shadowing stub pattern** — Phase 3's bats fixtures stub `npm` (FR-4) and `git` (FR-5) via `PATH="${FIXTURE_DIR}/stubs:${PATH}"` inline on each `run` call. Per-test `setup()` / `teardown()` follows the exact hook names and invocation shape from `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/verify-references.bats` (FEAT-026), with no parent-shell PATH mutation. No stubs needed in Phases 1 and 2.
- **No new plugin-shared scripts** — all six FEAT-027 scripts are self-contained under `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/`. The plugin-shared `scripts/` directory is not modified. `check-deliverable.sh` is a skill-scoped sibling of the existing plugin-shared `check-acceptance.sh`, not a replacement.

## Testing Strategy

- **Unit tests (bats, Phases 1–3)** — one `.bats` file per script. Tests live under `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/`. Covers all valid input classes per FR, every documented exit code, graceful-degradation skip path (FR-4: `npm` absent), idempotent no-op paths (FR-2, FR-3), fence-awareness for all fence-sensitive scripts (FR-1, FR-2, FR-3, FR-6), and edge-case inputs (plan with no `### Phase` blocks, phase with no `**Status:**` line, `**Depends on:**` lines, duplicate phase numbers).
- **Fence-awareness coverage** — at least one bats fixture per fence-sensitive script (FR-1, FR-2, FR-3, FR-6) includes a fenced code block containing example `**Status:**` / `- [ ]` lines that MUST NOT be flipped or read as real status. The `fenced-status-plan.md` fixture (Phase 1) and the corresponding fenced section of `deliverables-plan.md` (Phase 2) serve this purpose.
- **String exactness** — bats tests assert `[warn]` / `[error]` stderr strings verbatim (same pattern as FEAT-026's `verify-references.bats` and `detect-review-mode.bats`).
- **Integration tests (live, per Testing Requirements)** — end-to-end invocation of `/implementing-plan-phases FEAT-027 1` against a fixture plan. Verifies FR-1 through FR-6 in the sequence the SKILL.md orchestrates: phase selection → in-progress transition → deliverable checkoff → verification → commit-push → complete transition → all-phases-complete gate. FR-6 is verified as a pre-PR gate: with one phase still Pending, `create-pr.sh` must not be called.
- **Token-savings measurement (NFR-4)** — pre- and post-feature paired workflow runs on a representative feature workflow (≥ 4 phases). Token counts captured from Claude Code conversation state. Target: measured delta within ±30% of ~6,900 tok/feature-workflow (~800 FR-1 + ~1,600 FR-2 + ~2,000 FR-3 + ~1,200 FR-4 + ~1,200 FR-5 + ~100 FR-6).
- **Manual E2E** — full standalone `/implementing-plan-phases` invocation confirming Step 10 (Create Pull Request) still runs after the final phase, and a push-failure recovery exercise confirming FR-5's fail-fast behavior and the do-not-re-run caller pattern.

## Dependencies and Prerequisites

- **Phase ordering**: Phase 2 depends on Phase 1 (block-boundary logic and fence-tracking pattern). Phase 3 depends on Phase 1 (block-boundary logic reused by FR-4). Phase 4 depends on Phases 1–3 (SKILL.md pointers must point at existing, tested scripts).
- **`build-branch-name.sh` + `ensure-branch.sh`** (plugin-shared) — already exist (`plugins/lwndev-sdlc/scripts/`). Used by Step 4 of the current SKILL.md; not called by any FEAT-027 script. Unchanged.
- **`check-acceptance.sh`** (plugin-shared) — already exists. Sibling to FR-3's `check-deliverable.sh`. Not modified by this feature; remains the correct choice for non-phase-scoped checkoff in other skills.
- **`create-pr.sh`** (plugin-shared) — already exists. Called by Step 10 of the current SKILL.md. Unchanged.
- **`resolve-requirement-doc.sh`** (plugin-shared) — already exists. Used by SKILL.md Step 1. Unchanged.
- **External tools**:
  - `git` — already required. Used by FR-5.
  - `npm` — already required as a project dependency. Used by FR-4. Gracefully degrades per NFR-1 if missing.
  - `jq` — optional. Used by FR-1, FR-4, FR-6 for JSON assembly; pure-bash fallback for all three.
  - `awk`, `sed`, `grep`, `tr` — POSIX baseline, available on every supported platform.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **Self-bootstrapping break**: SKILL.md rewrite (Phase 4) lands before scripts are tested, breaking live skill mid-workflow | High | Low | Phase 4 is strictly ordered after Phases 1–3. SKILL.md is only rewritten after all six scripts exist and bats tests pass. Phase 4 implementation steps include running `npm test` before committing the rewrite. |
| **SKILL.md line-count target missed (< 20% reduction)**: the rewritten SKILL.md ends up larger than expected | Low | Low | SKILL.md is currently 173 lines. The removal list sums to ~44 lines of deletion vs. ~15 lines of pointer insertion. Even conservative removal delivers ~17%; the 20% target has moderate margin. Verified via `wc -l` in Phase 4 step 7 before committing. |
| **`check-deliverable.sh` exit-code shape confusion**: callers branch on `2`=ambiguous / `3`=missing-arg (different from the rest of the feature's `2`=missing-arg convention) | Medium | Low | NFR-2 documents the one-off explicitly. The script's top-of-file comment block documents the exit-code shape prominently. Bats tests assert the exact exit codes for every error path including `2` (ambiguous) and `3` (missing-arg). |
| **`commit-and-push-phase.sh` trips "no changes to commit" on re-run after push failure**: callers that naively re-run the script after resolving a conflict will see exit `1` on a clean tree | Medium | Medium | FR-7 and Phase 4 step 1 require documenting the do-not-re-run caller pattern in both SKILL.md (Push Failure Recovery prose) and `step-details.md`. The error message `error: no changes to commit` in the script is distinctive, making the mistake diagnosable. |
| **`verify-phase-deliverables.sh` hangs on `npm test` or `npm run build`**: no built-in timeout | Low | Low | This matches the current SKILL.md behavior (also no timeout). A `--timeout <N>` flag is documented as a Future Enhancement in the requirements doc. Callers that need a timeout wrap the script in `timeout <N>`. |
| **`next-pending-phase.sh` two-tier dependency logic incorrectly classifies plans without `**Depends on:**` lines**: if sequential ordering is applied incorrectly, a plan with Phase 2 pending and Phase 1 complete would block indefinitely | Medium | Low | Bats tests cover the sequential ordering path explicitly (Phase 1 Complete, Phase 2 Pending → selects Phase 2). The `**Depends on:**` path is tested separately against the `multi-phase-plan.md` fixture with an explicit dependency line. |
| **Token-savings measurement unavailable at PR time**: NFR-4 requires the measured delta documented in the PR body | Low | Medium | Phase 4 step 8 explicitly gates the measurement as a deliverable checkbox. Missing measurement blocks AC sign-off on NFR-4. Standard deferred pattern per FEAT-025 and FEAT-026 precedent. |

## Success Criteria

- All six scripts (`next-pending-phase.sh`, `plan-status-marker.sh`, `check-deliverable.sh`, `verify-phase-deliverables.sh`, `commit-and-push-phase.sh`, `verify-all-phases-complete.sh`) implement their respective FRs and pass all bats tests.
- `plan-status-marker.sh` handles all three canonical states with correct emoji emission, is idempotent, and is fence-aware.
- `check-deliverable.sh` is phase-scoped, accepts both numeric index and text substring, and its exit-code shape matches `check-acceptance.sh`'s `0`/`1`/`2`(ambiguous)/`3`(missing-arg) convention.
- `verify-phase-deliverables.sh` gracefully degrades when `npm` is absent and aggregates all sub-check results into a single exit code.
- `commit-and-push-phase.sh` produces the canonical `<type>(<ID>): complete phase <N> - <name>` commit message, detects first-vs-subsequent-push, and fails fast on push error with `git` stderr surfaced verbatim.
- `verify-all-phases-complete.sh` correctly gates PR creation on all-phases-complete status.
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` is rewritten per FR-7; public contract retained; net line-count reduction ≥ 20% (≤ 138 lines).
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` is updated to match the SKILL.md rewrite; mislabel on line 286 corrected.
- FR-8 satisfied: no changes to orchestrator fork-invocation shape; no other skill files modified; `plugins/lwndev-sdlc/scripts/` directory unchanged.
- `npm test` and `npm run validate` pass on the release branch.
- Token-savings measurement within ±30% of ~6,900 tok/feature-workflow estimate.

## Code Organization

```
plugins/lwndev-sdlc/
└── skills/
    └── implementing-plan-phases/
        ├── SKILL.md                                    # REWRITTEN (Phase 4): reference-and-pointer doc
        ├── assets/
        │   └── pr-template.md                         # UNCHANGED
        ├── references/
        │   ├── step-details.md                        # REWRITTEN (Phase 4): same script pointers
        │   └── workflow-example.md                    # AUDITED (Phase 4): mechanical prose replaced if present
        └── scripts/                                   # NEW directory (Phase 1)
            ├── next-pending-phase.sh                  # NEW (Phase 1): FR-1
            ├── plan-status-marker.sh                  # NEW (Phase 1): FR-2
            ├── verify-all-phases-complete.sh          # NEW (Phase 1): FR-6
            ├── check-deliverable.sh                   # NEW (Phase 2): FR-3
            ├── verify-phase-deliverables.sh           # NEW (Phase 3): FR-4
            ├── commit-and-push-phase.sh               # NEW (Phase 3): FR-5
            └── tests/                                 # NEW directory (Phase 1)
                ├── fixtures/                          # NEW directory (Phase 1, extended Phases 2-3)
                │   ├── minimal-plan.md                # Phase 1: two-phase plan fixture
                │   ├── multi-phase-plan.md            # Phase 1: four-phase plan with mixed statuses and Depends-on
                │   ├── fenced-status-plan.md          # Phase 1: plan with Status lines in fenced blocks
                │   ├── deliverables-plan.md           # Phase 2: plan with deliverable lines for checkoff tests
                │   └── verify-deliverables-plan.md    # Phase 3: plan for verify-phase-deliverables tests
                ├── next-pending-phase.bats            # NEW (Phase 1)
                ├── plan-status-marker.bats            # NEW (Phase 1)
                ├── verify-all-phases-complete.bats    # NEW (Phase 1)
                ├── check-deliverable.bats             # NEW (Phase 2)
                ├── verify-phase-deliverables.bats     # NEW (Phase 3)
                └── commit-and-push-phase.bats         # NEW (Phase 3)
```
