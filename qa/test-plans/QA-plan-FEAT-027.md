---
id: FEAT-027
version: 2
timestamp: 2026-04-23T12:50:00Z
persona: qa
---

## User Summary

`implementing-plan-phases` will ship six new skill-scoped shell scripts (phase selection, status marker, deliverable checkoff, deliverable verification, commit-and-push, all-phases-complete check) plus a SKILL.md + references rewrite that replaces ~1,500 tokens of per-phase prose with single script calls. The per-phase workflow contract stays unchanged for callers; the orchestrator and standalone users invoke the same skill and get the same artifacts. Judgment work (writing the implementation, TDD sequencing, merge-conflict resolution) stays in prose. The feature mirrors the pattern FEAT-026 shipped for `reviewing-requirements`.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs

- [P0] Plan file containing zero `### Phase` blocks | mode: test-framework | expected: next-pending-phase, plan-status-marker, verify-phase-deliverables, verify-all-phases-complete all exit `1` with `[error]` to stderr; no partial edits to the file
- [P0] Plan file with a phase block whose `**Status:**` line is missing entirely | mode: test-framework | expected: next-pending-phase treats the phase as if it had no status and exits `1`; plan-status-marker targeting that phase exits `1` with `[error] phase <N> has no **Status:** line`
- [P0] Plan file where `**Status:**` appears only inside a fenced code block (documentation example, not a real phase status) | mode: test-framework | expected: all fence-aware scripts (plan-status-marker, check-deliverable, verify-all-phases-complete) ignore the fenced line; no writes inside the fence
- [P0] plan-status-marker invoked with unknown state token (e.g. `Done`, `In Progress` without emoji, `complete ` with trailing space) | mode: test-framework | expected: exit `2` with a usage error listing the three canonical tokens; file unchanged
- [P0] check-deliverable numeric index `0` | mode: test-framework | expected: exit `1` with out-of-range error; `0` is not a valid 1-based index
- [P0] check-deliverable numeric index that exactly equals the deliverable count | mode: test-framework | expected: exit `0` — boundary case where idx equals count must succeed, not fail with off-by-one
- [P0] check-deliverable index exceeding the phase's deliverable count (e.g. `<count>+1`) | mode: test-framework | expected: exit `1` with `error: deliverable index <N> out of range (phase has <M> deliverables)` including the exact counts
- [P1] check-deliverable text matcher that hits one `- [ ]` and one `- [x]` in the same phase | mode: test-framework | expected: exit `0` with `checked`; the sole `- [ ]` is flipped; the pre-existing `- [x]` is not touched
- [P1] check-deliverable text matcher matching zero `- [ ]` but N `- [x]` lines | mode: test-framework | expected: exit `0` with `already checked` (idempotent); file unchanged
- [P1] check-deliverable called with an empty-string matcher (`""`) | mode: test-framework | expected: exit `3` (arg error) or exit `2` (ambiguous — every `- [ ]` line would match). Stop-hook friendly: whichever the script picks, the behavior must be documented and not silently flip the first deliverable it finds
- [P1] plan file with CRLF line endings (Windows-authored) | mode: test-framework | expected: all scripts handle CRLF; write-back preserves CRLF; no `^M` artifacts injected into the document
- [P1] plan file with UTF-8 BOM at start of file | mode: test-framework | expected: scripts ignore the BOM during parsing; write-back preserves the BOM or documents its removal
- [P1] `**Status:**` line with a typo (extra space, missing emoji, mixed case) | mode: test-framework | expected: regex matcher does NOT silently match a drifted status; either exact-match (preserve existing file's drift) or fail explicitly — not both
- [P1] phase number parsed from `### Phase 01:` (leading zero) vs `### Phase 1:` | mode: test-framework | expected: documented normalization; if `01` is treated as phase `1` for lookup, plan-status-marker writes back as the original form; no silent re-write of the heading
- [P1] Plan with duplicate `### Phase 1:` headings (malformed) | mode: test-framework | expected: `[warn] duplicate phase 1 detected; using first occurrence` to stderr; scripts target first occurrence; second occurrence untouched
- [P2] `<FEAT-ID>` arg with lowercase prefix (`feat-027`) | mode: test-framework | expected: commit-and-push-phase exits `2` with arg-shape error; the canonical regex is `^(FEAT|CHORE|BUG)-[0-9]+$`
- [P2] `<FEAT-ID>` arg for a numeric-only ID (`FEAT-001`) that exists in the repo but is not the current feature | mode: test-framework | expected: commit-and-push-phase does not validate against the filesystem; it accepts any syntactically valid ID. The canonical message format is the only contract
- [P2] `<phase-N>` arg of `1.5` (decimal) | mode: test-framework | expected: commit-and-push-phase exits `2`; `<phase-N>` must match `^[1-9][0-9]*$`
- [P2] `<phase-name>` arg containing backticks, backslashes, or quotes | mode: test-framework | expected: commit message is constructed safely (no shell injection); the resulting commit subject contains the literal characters

### State transitions

- [P0] Two orchestrator processes invoke check-deliverable on the same plan file for different deliverables concurrently | mode: exploratory | expected: document whether the scripts are safe for concurrent writes or rely on the orchestrator to sequence them; if concurrent use is unsafe, the SKILL.md must say so. Surprise interleaving must not silently lose a checkoff
- [P0] commit-and-push-phase SIGINT between `git commit` success and `git push` | mode: exploratory | expected: local commit exists, remote does not, script exit is non-zero. Re-invocation trips the "no changes to commit" gate and exits `1` — the user must invoke `git push` directly per Edge Case 11. Verify the documented recovery pattern actually works
- [P0] plan-status-marker called twice with the same state (`complete` → `complete`) | mode: test-framework | expected: first call emits `transitioned`, second call emits `already set` and exits `0` without re-writing. No duplicate emoji insertion
- [P1] verify-phase-deliverables invoked mid-phase while source files are still being written | mode: exploratory | expected: file-existence check reports `ok` for partially-written files (it only checks existence); `npm test` may fail against incomplete code. The graceful-degradation path is separate from partial-write detection
- [P1] plan file is edited externally (e.g. a human edits the plan) between `plan-status-marker in-progress` and `plan-status-marker complete` | mode: exploratory | expected: the script re-reads the file on the second call; stale state from the first call does not clobber the human edit. Document via bats fixture
- [P1] check-deliverable invoked twice in sequence with the same matcher | mode: test-framework | expected: first call emits `checked`, second emits `already checked`. Both exit `0`. Idempotency invariant holds across invocations
- [P2] next-pending-phase finds a phase marked `🔄 In Progress` — interpreted as "resume this phase" | mode: test-framework | expected: stdout emits `{"phase":N,"name":"...","reason":"resume-in-progress"}` and exit `0`; the orchestrator picks up the same phase rather than skipping to the next `Pending`. Verify the orchestrator's post-fork parser honors the `reason` field
- [P2] next-pending-phase sees explicit `**Depends on:** Phase 3` on Phase 2 and Phase 3 is Pending while Phase 2 is Pending | mode: test-framework | expected: stdout emits `{"phase":null,"reason":"blocked","blockedOn":[3]}`; the orchestrator surfaces this to the user rather than silently selecting Phase 2 in violation of its declared dependency
- [P2] Plan file where Phase 2 has `**Depends on:** Phase 5` (forward dependency, pathological case) | mode: test-framework | expected: next-pending-phase flags as blocked and emits `blockedOn:[5]`; no crash; no silent success

### Environment

- [P0] commit-and-push-phase executed offline (no network) | mode: exploratory | expected: `git commit` succeeds locally, `git push` fails, script exits `1` with git's stderr. Local commit is preserved. Retry after network recovery must work via direct `git push` (not by re-running the script)
- [P0] verify-phase-deliverables executed when `npm` is absent from PATH | mode: test-framework | expected: `[warn] verify-phase-deliverables: npm not found; skipping test/build/coverage checks.` to stderr; `test/build/coverage: "skipped"`; file existence check still runs; aggregate exit depends only on `files.missing`
- [P1] plan file stored on a read-only filesystem | mode: test-framework | expected: plan-status-marker and check-deliverable fail fast with filesystem-error stderr; no partial writes via `mv` on a read-only target
- [P1] `git commit` pre-commit hook rejects the commit (e.g. lint failure) | mode: test-framework | expected: commit-and-push-phase exits `1` with hook stderr verbatim; no push attempt; local tree remains staged but uncommitted
- [P1] `git push` rejected because remote is ahead | mode: exploratory | expected: exit `1` with git's "rejected — non-fast-forward" stderr; recovery requires `git fetch origin` + `git rebase` + direct `git push`. Re-running the script on the resolved tree trips the "no changes to commit" gate (Edge Case 11 verified here)
- [P1] `npm run test:coverage` does not exist in package.json (but capability discovery says vitest is configured) | mode: test-framework | expected: verify-phase-deliverables detects the missing script either by its own detection heuristic or by `npm`'s exit code and emits `"coverage":"skipped"`. Does not treat this as a hard failure
- [P2] verify-phase-deliverables on a phase deliverable path containing spaces or `$` characters | mode: test-framework | expected: `[ -e "$path" ]` handles quoting; no word-splitting; path with `$FOO` substring is not expanded
- [P2] Timezone shift between `classify-post-plan` run and `commit-and-push-phase` run (local TZ change) | mode: exploratory | expected: commit timestamps reflect local `git` config; no script-side timestamp injection

### Dependency failure

- [P0] `npm test` returns exit 0 but `npm run build` returns exit 1 | mode: test-framework | expected: verify-phase-deliverables aggregates — `test: "pass"`, `build: "fail"`, aggregate exit `1`. Build-failure tail is included in `output.build`; test-pass tail is NOT included
- [P0] `npm test` hangs indefinitely (documented edge case 12, no timeout) | mode: exploratory | expected: script hangs with it; Future Enhancements documents a `--timeout` flag. Manual test runs through `timeout 2m bash ...` and confirms the outer timeout is the only mitigation
- [P1] `gh pr create` (inside create-pr.sh, called by the skill after all phases complete) fails because `gh` is unauthenticated | mode: exploratory | expected: NOT in FEAT-027 scope (create-pr.sh is plugin-shared, FEAT-020); but the skill's verify-all-phases-complete should have already succeeded by that point. The failure path is: verify-all-phases-complete returns `all phases complete` → create-pr.sh fails → skill reports failure to orchestrator
- [P1] `jq` is not installed; scripts declare it optional | mode: test-framework | expected: pure-bash fallback paths for next-pending-phase / verify-phase-deliverables / verify-all-phases-complete produce identical JSON shapes. bats fixtures verify both code paths
- [P2] commit-and-push-phase executed with `git` older than the version that supports `--porcelain=v1` | mode: exploratory | expected: script fails fast with git's stderr; documented minimum git version in the plugin README

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] Concurrency — the orchestrator forks phase 1 and phase 2 simultaneously | mode: exploratory | expected: this MUST NOT happen per the feature-chain step sequence (phases execute sequentially, not in parallel). If a future orchestrator enables parallel phase execution, all six scripts must be re-audited for concurrent-write safety
- [P1] Permissions — plan file owned by a different user than the invoker | mode: test-framework | expected: plan-status-marker's write step fails with a filesystem permission error; no partial write; exit `1`. Idempotency does NOT mean "silently ignore permission errors"
- [P1] Unicode in phase name — e.g. `Phase 3: 性能优化` (Chinese) | mode: test-framework | expected: commit-and-push-phase constructs the commit subject with the literal bytes; `git` handles UTF-8 commit messages; no mojibake. bats fixture includes one non-ASCII phase name
- [P2] Deliverable path containing a `)` or `(` character | mode: test-framework | expected: FR-4's file-existence check quotes properly; no shell-glob expansion; `[ -e "path(with-parens)" ]` succeeds
- [P2] Plan file with mixed tab/space indentation inside the deliverables list | mode: test-framework | expected: check-deliverable's regex matches `- [ ]` regardless of preceding whitespace character; no missed matches on tab-indented lines

## Non-applicable dimensions

- a11y: the feature has no UI surface — scripts run server-side / inside the orchestrator fork context. Accessibility does not apply to shell scripts emitting JSON to stdout.
- i18n (user-facing strings): error messages are intentionally English-only per the plugin's existing precedent (`check-acceptance.sh`, `prepare-fork.sh`, `workflow-state.sh` all emit English-only stderr). Scenario output JSON carries structural data that callers translate if needed. Unicode passthrough in phase names / deliverable paths IS covered under Cross-cutting above.
