---
id: FEAT-020
version: 2
timestamp: 2026-04-21T03:12:25Z
verdict: PASS
persona: qa
---

## Summary

Adversarial QA against PR #193 surfaced one real bug — `checkbox-flip-all.sh` was permanently normalizing CRLF→LF on write, contradicting the FEAT-019 "restore original ending on write" rule still present in `finalizing-workflow/SKILL.md`. The script was patched to detect CRLF on read and re-emit it on every printed line through an awk `emit()` helper. A second run exercises twenty-one scenarios across all five adversarial dimensions; all pass.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Execution Results

- Total: 21
- Passed: 21
- Failed: 0
- Errored: 0
- Exit code: 0
- Duration: 2.15s
- Test files: [scripts/__tests__/qa-FEAT-020.spec.ts]

## Scenarios Run

| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| I-1 | Inputs | P1 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| I-2 | Inputs | P1 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| I-3 | Inputs | P2 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| I-4 | Inputs | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| I-5 | Inputs | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| I-6 | Inputs | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| I-7 | Inputs | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| S-1 | State transitions | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| S-2 | State transitions | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| S-3 | State transitions | P1 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| E-1 | Environment | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| E-2 | Environment | P0 | PASS (after fix) | scripts/__tests__/qa-FEAT-020.spec.ts |
| E-3 | Environment | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| E-4 | Environment | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| E-5 | Environment | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| E-6 | Environment | P2 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| D-1 | Dependency failure | P2 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| D-2 | Dependency failure | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| D-3 | Dependency failure | P1 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| C-1 | Cross-cutting | P2 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |
| C-2 | Cross-cutting | P0 | PASS | scripts/__tests__/qa-FEAT-020.spec.ts |

Scenario legend:
- I-1 slugify exits 1 on emoji-only title
- I-2 slugify truncates extremely long titles to four tokens
- I-3 slugify is deterministic byte-for-byte
- I-4 check-acceptance literal-dot regex metachar (`AC-1.2` ≠ `AC-142`)
- I-5 check-acceptance rejects bracket regex metachar interpretation
- I-6 checkbox-flip-all ignores language-tagged fenced blocks
- I-7 checkbox-flip-all ignores `~~~` tilde fenced blocks
- S-1 check-acceptance already-checked idempotency (byte-identical)
- S-2 checkbox-flip-all idempotency (`checked 0 lines` on rerun, byte-identical)
- S-3 next-id concurrent invocations return the same number
- E-1 check-acceptance CRLF round-trip preservation
- E-2 checkbox-flip-all CRLF round-trip preservation (passed only after bug fix — see Findings)
- E-3 next-id returns `001` when run outside a repo with no `requirements/` tree
- E-4 resolve-requirement-doc exits 1 with `no file matches` when CWD is empty
- E-5 branch-id-parse jq-absent fallback emits parseable JSON
- E-6 slugify preserves ASCII `I` → `i` under `LC_ALL=tr_TR.UTF-8`
- D-1 create-pr exits non-zero when `pr-body.tmpl` is missing
- D-2 create-pr exits 1 on `git push` failure without invoking `gh pr create`
- D-3 commit-work exits non-zero with nothing staged
- C-1 create-pr body substitution preserves backticks, `$(...)`, `&` literally
- C-2 build-branch-name finds sibling slugify.sh when scripts/ is symlinked

## Findings

### Finding 1 — CRLF preservation defect in `checkbox-flip-all.sh` (surfaced and fixed during this run)

- **Severity**: High (documented contract violation)
- **Dimension**: Environment
- **Failing scenario on first run**: `[QA FEAT-020] Environment: CRLF round-trip preservation > checkbox-flip-all.sh preserves CRLF line endings on write`
- **Failing test name**: `checkbox-flip-all.sh preserves CRLF line endings on write`
- **Reproduction**:
  1. Write a file with `## A\r\n\r\n- [ ] one\r\n- [ ] two\r\n` (CRLF endings).
  2. Run `bash plugins/lwndev-sdlc/scripts/checkbox-flip-all.sh <file> A`.
  3. Read the file back — before the fix, the `\r` bytes were gone.
- **Evidence**: The pre-fix script stripped CRs on read (`sub(/\r$/, "")`) and printed via awk's default output separator (`\n`), so the rewrite permanently downgraded CRLF to LF. The script's own header comment even conceded "Mixed CRLF input normalizes to LF on write", directly contradicting `finalizing-workflow/SKILL.md:105` ("normalize on read and restore the original ending on write", landed by FEAT-019 commit `a8c3ab8`). `check-acceptance.sh` does not share the defect because its sed-style line-targeted rewrite passes the original line bytes through awk untouched.
- **Fix applied**: `plugins/lwndev-sdlc/scripts/checkbox-flip-all.sh` now probes the input for a trailing `\r` once (`grep -q $'\r$'`), passes an `eol` variable into awk, and emits every line via a shared `emit(s) { printf "%s%s\n", s, eol }` helper. All eight existing bats fixtures and the new qa round-trip scenarios pass.
- **Test coverage added**: `scripts/__tests__/qa-FEAT-020.spec.ts` scenarios E-1 (check-acceptance) and E-2 (checkbox-flip-all) now assert the round-trip invariant on CRLF input; the pre-existing bats CRLF fixture only asserted that the flip happened, not that line endings were preserved.

### Observations (non-blocking)

- `checkbox-flip-all.sh` silently does nothing when a fenced code block is opened inside the target section and never closes before the next `## ` heading — the section-close guard at line 60 requires `!in_fence`, so malformed input pins `in_section = 1` until the fence (eventually) closes, at which point downstream `## ` headings fire normally. The practical outcome is "missed flips", not "wrong flips" (the flip gate at line 75 also requires `!in_fence`), so the worst case is an under-flipped document rather than corrupted neighbouring sections. Not fixed in this run; logged for a later pass if malformed markdown ever reaches the script. The qa run does not gate the verdict on this because the scenario was not in the test plan and requires malformed input outside the plan's input envelope.
- The spec's FR-10 jq-fallback is exercised hermetically by the qa test scenario E-5 (PATH stripped of jq); note the fallback only triggers when `command -v jq` finds nothing — a jq that is present but broken will still cause the script to exit non-zero via `set -euo pipefail`. Acceptable per FR-10 ("jq is a soft dependency, absent → fallback"); a broken-jq environment is outside the documented envelope.

## Reconciliation Delta

### Coverage beyond requirements

- Scenario E-6 (Turkish locale lowercase behaviour in `slugify.sh`) — not mentioned in FR-2 or any AC; surfaced by the qa plan's Environment dimension as a locale-safety probe. Useful defensive coverage that the spec does not demand.
- Scenario C-1 (shell-metacharacter safety inside `create-pr.sh` body substitution — backticks, `$(…)`, `&`) — not explicitly called out in FR-9 or AC-4; surfaced by the qa plan's Cross-cutting dimension. The bash parameter-expansion substitution chosen in phase 3 (resolving W2) is safe; C-1 codifies that guarantee.
- Scenario C-2 (`${BASH_SOURCE%/*}` under symlinked `scripts/` directory) — derived from NFR-3 ("Invocation convention") but not explicitly listed in any AC; useful for catching future regressions if a future script starts hard-coding absolute paths.
- Scenario S-3 (concurrent `next-id.sh` invocations) — the plan called this exploratory-only; the qa run upgraded it to `test-framework` via `Promise.all` + `spawn`. Not required by the spec but proves the read-only allocator is race-free under the common "single workflow, single orchestrator" invariant.

### Coverage gaps

- FR-4 (`build-branch-name.sh`) has no dedicated qa scenario for the stopword-propagation case (`feat FEAT-001 "The Art of War"` → `feat/FEAT-001-art-war`) — covered only by the authoring bats fixture. Low risk because `build-branch-name.sh` is a thin wrapper around `slugify.sh`, which is exercised directly.
- FR-8 (`commit-work.sh` type validator — the full twelve-token list `chore|fix|feat|qa|docs|test|refactor|perf|style|build|ci|revert`) has no qa-layer enumeration; only the single "nothing staged" failure path (scenario D-3) is in the qa set. Token-validation coverage is left to the authoring bats fixture.
- FR-9 `--closes` edge cases (bare `#`, empty string, `#abc`, `#-5`, `--closes=` equals-form) are not exercised by the qa layer; the authoring bats fixture covers them. Coverage of the P1 plan item is therefore single-tier.
- AC-3 (`shellcheck -S warning` gate) is not exercised as a runtime vitest scenario; it is a manual + authoring-time gate. The plan explicitly flagged this as exploratory under Cross-cutting, and the CRLF fix was re-shellchecked manually.
- AC-22 (`npm run validate` on the final tree) is covered transitively (the vitest suite invokes plugin validation internally via `scripts/__tests__/build.test.ts`), not by a direct scenario in the qa file.
- Edge cases 4 (fenced blocks with language tags — covered partially by I-6/I-7), 9 (nested fences), and 13 (in-flight process interruption) are exploratory-only in the plan and were not elevated to test-framework scenarios here.
- Plan scenario "Unicode, RTL, and combining characters in `slugify.sh` input" (P1 Inputs) was not implemented; only emoji-only input is exercised (I-1). Unicode/RTL/combining is a behaviour of `tr -cs '[:alnum:]'` in `slugify.sh` and is backstopped by the determinism scenario (I-3).

### Summary

- coverage-surplus: 4
- coverage-gap: 7
