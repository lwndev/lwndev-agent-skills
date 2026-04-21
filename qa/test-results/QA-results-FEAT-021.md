---
id: FEAT-021
version: 2
timestamp: 2026-04-21T12:50:00Z
verdict: PASS
persona: qa
---

## Summary

39 new vitest scenarios in `scripts/__tests__/qa-FEAT-021.spec.ts` probed failure modes beyond the authoring bats fixture — all 39 passed. Two non-blocking findings are documented as explicit FINDING assertions so future regressions are caught: `chmod 0400` on the state file does not write-protect the audit trail (atomic-rename bypass); and the `CLAUDE_PLUGIN_ROOT` fallback is not symlink-aware.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

Note: the code under test is Bash (`plugins/lwndev-sdlc/scripts/prepare-fork.sh`). The authoring team's primary unit tests live in bats fixtures at `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` (25 cases, all green). This QA run adds a vitest spec that spawns the same script via `spawnSync('bash', ...)` — the harness choice follows the repo's QA-precedent set by `scripts/__tests__/qa-FEAT-020.spec.ts`, which likewise targets Bash code from vitest.

## Execution Results

- Total: 39
- Passed: 39
- Failed: 0
- Errored: 0
- Exit code: 0
- Duration: 3.93s
- Test files: [`scripts/__tests__/qa-FEAT-021.spec.ts`]

Aggregate context:
- Full repo vitest suite post-commit: 1046 passed / 0 failed across 32 files (42.43s).
- Authoring bats fixture post-commit: 25 passed / 0 failed.

## Scenarios Run

| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| malformed-id-matrix (×6) | Inputs | P0 | passed | qa-FEAT-021.spec.ts |
| non-numeric-stepIndex-matrix (×6) | Inputs | P0 | passed | qa-FEAT-021.spec.ts |
| unknown-skill-name-typos (×5) | Inputs | P0 | passed | qa-FEAT-021.spec.ts |
| argv-injection-payloads (×4) | Inputs | P0 | passed | qa-FEAT-021.spec.ts |
| help-precedence-over-mutex | Inputs | P1 | passed | qa-FEAT-021.spec.ts |
| oversized-stepIndex-round-trip | Inputs | P1 | passed | qa-FEAT-021.spec.ts |
| repeated-invocation-distinct-startedAt | State transitions | P1 | passed | qa-FEAT-021.spec.ts |
| invocation-when-paused | State transitions | P1 | passed | qa-FEAT-021.spec.ts |
| retry-audit-trail-distinct-tiers | State transitions | P2 | passed | qa-FEAT-021.spec.ts |
| read-only-state-file-FINDING | Environment | P0 | passed (finding) | qa-FEAT-021.spec.ts |
| bogus-CLAUDE_PLUGIN_ROOT | Environment | P0 | passed | qa-FEAT-021.spec.ts |
| symlink-invocation-FINDING | Environment | P0 | passed (finding) | qa-FEAT-021.spec.ts |
| symlink-with-env-var | Environment | P1 | passed | qa-FEAT-021.spec.ts |
| cwd-sensitive-state-resolution | Environment | P1 | passed | qa-FEAT-021.spec.ts |
| non-utf8-locale-em-dash | Environment | P2 | passed | qa-FEAT-021.spec.ts |
| resolve-tier-multi-line-garbage | Dependency failure | P0 | passed | qa-FEAT-021.spec.ts |
| step-baseline-locked-wrong-case | Dependency failure | P0 | passed | qa-FEAT-021.spec.ts |
| step-baseline-returns-complexity-label | Dependency failure | P0 | passed | qa-FEAT-021.spec.ts |
| script-without-exec-bit | Cross-cutting | P0 | passed | qa-FEAT-021.spec.ts |
| concurrent-different-ids | Cross-cutting | P0 | passed | qa-FEAT-021.spec.ts |
| skill-md-parent-dir-0000 | Cross-cutting | P1 | passed | qa-FEAT-021.spec.ts |
| workflows-dir-not-writable | Cross-cutting | P1 | passed | qa-FEAT-021.spec.ts |

## Findings

Two non-blocking findings are documented as explicit `FINDING:` comments in the test file. Neither blocks shipping — both describe divergences between the QA plan's spec-level expectation and the script's current (atomic-rename / non-symlink-aware) behavior. Both are captured as passing assertions so that a future fix would surface as a regression.

### F-1 (low severity) | Environment | `chmod 0400` on state file does not write-protect audit trail

**Scenario**: `[QA FEAT-021] Environment — read-only state file > still writes audit entry because atomic-rename bypasses file mode`

**Reproduction**:
1. Seed `.sdlc/workflows/FEAT-TEST.json` with a valid v2 state.
2. `chmod 0400 .sdlc/workflows/FEAT-TEST.json` — file appears read-only.
3. Run `bash prepare-fork.sh FEAT-TEST 1 reviewing-requirements --mode standard`.

**Evidence**: `record-model-selection` uses the `jq … > "${file}.tmp" && mv "${file}.tmp" "$file"` atomic-rename pattern throughout `workflow-state.sh` (19 occurrences). Rename only needs the parent directory writable; the target file's mode bits are irrelevant. Script exits `0`; `modelSelections.length` goes from `0` to `1` despite the 0400 chmod.

**Impact**: An operator who sets `chmod 0400` on a state file expecting tamper-evidence or write-protection will be surprised. The audit trail still receives entries. This is a known-by-spec consequence of atomic-rename semantics, not a correctness bug — no partial corruption occurs. Flagged for documentation in a follow-up if state-file tamper-evidence becomes a requirement.

**Finding is asserted** as a passing test (`expect(r.status).toBe(0)` + `modelSelections.length === 1` under 0400) so that a future change to direct-write (which *would* respect 0400) surfaces here as a deliberate regression for review.

### F-2 (low severity) | Environment | Fallback `CLAUDE_PLUGIN_ROOT` derivation is not symlink-aware

**Scenario**: `[QA FEAT-021] Environment — script invoked via symlink > FINDING: fails with exit 3 when invoked via symlink without CLAUDE_PLUGIN_ROOT`

**Reproduction**:
1. Create `symlink -> /path/to/real/prepare-fork.sh` somewhere in a test directory.
2. Invoke `bash /path/to/test/dir/symlink FEAT-TEST 2 reviewing-requirements --mode standard` **without** `CLAUDE_PLUGIN_ROOT` set.
3. Script fails with exit 3 and `Error: SKILL.md for 'reviewing-requirements' cannot be read…`.

**Evidence**: The fallback derivation at `prepare-fork.sh:214` is `CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`. `dirname` + `cd` do not resolve symlinks — `BASH_SOURCE[0]` points at the symlink path, so the derived root lands at the symlink's parent's parent, not at the real plugin tree. SKILL.md lookup then misses.

**Impact**: Non-operational in practice. The orchestrator always invokes `prepare-fork.sh` by its absolute real path (`bash ${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh`), and `CLAUDE_PLUGIN_ROOT` is always set by the orchestrator context. The symlink-without-env-var scenario does not occur on any production path. A `realpath` / `readlink -f` fix is feasible but deferred — the companion test (`symlink-with-env-var`) confirms that symlink invocation works correctly when `CLAUDE_PLUGIN_ROOT` is set, which is the only invocation pattern the orchestrator uses.

**Finding is asserted** as a passing test (`expect(r.status).toBe(3)`) so a future `realpath`-based fix surfaces as a regression for deliberate consideration.

## Reconciliation Delta

### Coverage beyond requirements

Scenarios in this run that do not map to a specific FR / NFR / AC / edge case in FEAT-021's requirements doc. Not automatically bad — most represent adversarial breadth beyond the spec's single-case-per-error shape.

- Malformed ID matrix (6 variants: empty, whitespace, prefix-only, lowercase, digits-only, unknown prefix). Spec FR-1 requires state-file-not-found for non-existent IDs but does not enumerate malformed-ID permutations.
- Non-numeric `stepIndex` matrix (6 variants: negative, decimal, scientific, hex, unicode digit, whitespace-wrapped). Spec FR-1 requires exit 2 on non-numeric but does not enumerate.
- Unknown skill-name typo matrix (5 variants: transposed, underscore, uppercase, whitespace-wrapped, trailing hyphen). Spec FR-1 requires exit 2 on any non-allowlist value.
- Argv-injection payloads into skill-name (4: semicolon, $( ), backticks, path traversal). Spec does not address shell-metacharacter safety; this is a security-adjacent dimension.
- `--help` precedence over `--mode` + `--phase` mutual exclusion. Spec FR-1 says help wins over positional-arg validation; extends that to flag mutual-exclusion validation.
- Oversized `stepIndex` preservation (2^63+). Spec does not address numeric overflow.
- Repeated invocation → distinct `startedAt` audit entries. Spec NFR-2 says non-idempotent; this verifies the observable distinction is `startedAt` (useful for retry-disambiguation per FR-11).
- Invocation when `status == "paused"`. Spec does not address gatekeeping; test documents that the script deliberately does NOT gate on status (the orchestrator is the gatekeeper).
- Retry audit-trail distinct-tiers verification. Edge Case 6 of spec covers `--cli-model-for` semantics; this extends to the full FR-11 retry-with-tier-upgrade audit-trail contract.
- `chmod 0400` atomic-rename bypass (F-1 finding). Not in spec.
- Symlink fallback derivation limitation (F-2 finding). Not in spec; Edge Case 10 addresses nested-shell invocation via zsh but not symlink PATH-entries.
- Byte-level em-dash preservation under `LANG=C`. Spec does not address locale byte preservation.
- Trust-boundary tests for child subcommand output quality (3 cases: multi-line garbage, wrong-case boolean, wrong-kind string). Spec defers validation of these to the child subcommand; this run documents what actually lands in the audit trail when the child misbehaves.
- Script without exec bit via `bash path/to/script.sh`. Implicit in Edge Case 10 but not explicitly asserted.
- Concurrent invocations against different IDs (no cross-contamination). Spec is silent on concurrency.
- SKILL.md parent-directory `chmod 0000` — a permission denial mode that the FR-2 Step 1 "collapse missing+unreadable" contract handles.
- `.sdlc/workflows/` directory `chmod 0555` — documents that directory-level write-denial propagates non-zero without corruption.

### Coverage gaps

Requirements / FR / NFR / AC items with no corresponding scenario in this run. Most are either out-of-scope for automated QA (doc changes, manual tests), covered by the authoring bats fixture and existing vitest suite, or deliberately deferred.

- **FR-3** (`workflow-state.sh step-baseline` / `step-baseline-locked` subcommands) — not directly tested in `qa-FEAT-021.spec.ts`. Covered by the existing `scripts/__tests__/workflow-state.test.ts` suite (18 tests match `step-baseline`). No gap in aggregate repo coverage; only in this spec file.
- **FR-4** (orchestrator prose replacement in SKILL.md) — doc-level change; not runtime-testable. Covered via code review at PR time.
- **FR-5** (downstream documentation updates in 4 files) — doc-level change; not runtime-testable. Covered via code review at PR time.
- **NFR-3** (performance target < 300 ms, follow-up threshold ~500 ms) — no timing assertion in this run. All observed scenarios complete in ≤ 70 ms per invocation based on test-runtime measurement, which is well under budget, but not asserted.
- **NFR-4** (Bash 3.2 compatibility cross-platform) — only exercised against the local Darwin Bash (macOS default is 3.2). No Linux Bash 3.2 container run and no explicit `bash -n` portability check in this spec. Existing CI on Linux Bash covers Bash 4+ via other tests.
- **NFR-6** (in-flight workflow compatibility with pre-FEAT-021 state files) — not tested. Requires a pre-FEAT-021 state fixture + resume through the orchestrator. Deferred to the existing `scripts/__tests__/workflow-state.test.ts` FR-13 migration cases, which cover the relevant schema-drift protections at the `workflow-state.sh` level; `prepare-fork.sh` writes the same schema.
- **Edge Case 8** (missing `complexity` field) — not directly tested. Existing `jq ... // "medium"` fallback is the authoritative check; covered by the authoring bats file's `seed_state` fixture which omits `complexity` implicitly in one of its paths.
- **Edge Case 10** (zsh caller) — authoring bats fixture tests `/bin/sh -c 'bash prepare-fork.sh ...'`; no explicit zsh invocation test in either place. The shebang line `#!/usr/bin/env bash` combined with the `bash $PREPARE_FORK` invocation pattern in every existing test makes the zsh-caller scenario structurally identical to the `/bin/sh` case. Low-risk gap.
- **AC-8, AC-9, AC-10** (manual tests: full-workflow happy path, CLI override manifests, kill+resume audit preservation) — manual by definition. Not automated in this run.
- **AC-12** (≥ 3000 tokens saved) — qualitative / measurement acceptance; not testable via assertion.

### Summary
- coverage-surplus: 18
- coverage-gap: 9
