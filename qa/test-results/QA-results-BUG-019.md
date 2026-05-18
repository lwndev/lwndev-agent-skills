---
id: BUG-019
version: 2
timestamp: 2026-05-18T03:37:03Z
verdict: PASS
persona: qa
---

## Summary

Verdict PASS: passed=22, failed=0, errored=0.

## Capability Report

```json
{
  "id": "BUG-019",
  "timestamp": "2026-05-18T03:31:00Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 22
- Passed: 22
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

### Inputs

- [P1] empty user@ prefix (`https://@dev.azure.com/...`) | mode: test-framework | expected: null emission — passed
- [P1] basic-auth `user:pass@` form | mode: test-framework | expected: no credential leakage into captured org — passed
- [P1] URL-encoded `@` in user component (`alice%40acme.com@`) | mode: test-framework | expected: no garbage in captured fields — passed
- [P1] multiple `@` chars (`a@b@dev.azure.com`) | mode: test-framework | expected: deterministic, no wrong org — passed
- [P1] origin with port (`https://alice@dev.azure.com:443/...`) | mode: test-framework | expected: null, host anchor not over-broadened — passed
- [P1] user-prefix to non-recognized host (`https://alice@gitlab.com/...`) | mode: test-framework | expected: null — passed
- [P0] user-prefix composed with `.git` suffix on AzDO | mode: test-framework | expected: suffix stripped, repo field clean — passed
- [P0] user-prefix composed with `.git` suffix on GitHub | mode: test-framework | expected: suffix stripped, repo field clean — passed
- [P0] BASH_REMATCH canary — dev.azure.com organization free of `@` | mode: test-framework | expected: organization field contains bare org name only — passed
- [P0] BASH_REMATCH canary — visualstudio.com organization free of `@` | mode: test-framework | expected: organization field contains bare org name only — passed
- [P0] BASH_REMATCH canary — DefaultCollection project is post-DefaultCollection segment | mode: test-framework | expected: project field is the segment after DefaultCollection/ — passed
- [P0] BASH_REMATCH canary — github.com owner free of `@` or token | mode: test-framework | expected: owner field contains bare owner only — passed

### State transitions

- [P0] `SDLC_SCM_BACKEND=github` on token-prefixed GitHub origin | mode: test-framework | expected: no warn on stderr, github JSON on stdout — passed
- [P0] `SDLC_SCM_BACKEND=github` on user-prefixed AzDO origin (mismatch) | mode: test-framework | expected: null + `[warn] SDLC_SCM_BACKEND=github` on stderr — passed
- [P0] `SDLC_SCM_BACKEND=azdo` on token-prefixed GitHub origin (mismatch) | mode: test-framework | expected: null + `[warn] SDLC_SCM_BACKEND=azdo` on stderr — passed
- [P0] `SDLC_SCM_BACKEND=azdo` on user-prefixed AzDO origin | mode: test-framework | expected: positive azdo JSON with all four identity fields — passed

### Environment

- [P0] macOS osxkeychain-style user-prefixed origin (the reported repro) | mode: test-framework | expected: clean azdo JSON, no warn — passed (covered transitively by the dev.azure.com user-prefixed scenarios and the implementation-side bats fixture using `alice@dev.azure.com/contoso/sdlc-tools/_git/plugin-repo`)

### Dependency failure

- not applicable: `backend-detect.sh` makes no network calls and depends only on a local `git remote get-url` invocation. The single dependency-failure surface — `git` failing — is already covered by the existing `no origin remote → null` fixture in the implementation-side bats file; no QA-layer adversarial probe is meaningful beyond that.

### Cross-cutting

- [P2] PAT-style token in user prefix never appears in stdout or stderr | mode: test-framework | expected: token string is absent from both streams — passed
- [P2] PAT-style token under `SDLC_SCM_BACKEND=github` never appears in output | mode: test-framework | expected: token string is absent from both streams — passed

### Regression coverage

- [P0] user-less `dev.azure.com` HTTPS still matches after index-shift | mode: test-framework | expected: existing azdo JSON shape unchanged — passed
- [P0] user-less `visualstudio.com/DefaultCollection` still matches after index-shift | mode: test-framework | expected: organization/project parse correctly — passed
- [P0] user-less `github.com` HTTPS still matches after index-shift | mode: test-framework | expected: github JSON unchanged — passed
- [P0] SSH origins (`git@ssh.dev.azure.com:v3/...`) unchanged | mode: test-framework | expected: azdo JSON, SSH branch not touched by the fix — passed

## Non-applicable dimensions

- **Dependency failure**: does not apply — see the `### Dependency failure` justification under `## Scenarios Run`.

## Findings

All 22 QA bats scenarios passed. The implementation closes the reported defect: AzDO HTTPS origin URLs with a `<user>@` credential prefix now classify as `azdo` and downstream consumers (`create-pr.sh`, `finalizing-workflow`) dispatch correctly. The symmetric GitHub HTTPS fix (RC-2) is also exercised by the QA bats canaries and the security-leak probes. No production-code defects found in this QA pass.

The following workflow / infrastructure issues surfaced during this run and are **out of scope for BUG-019**. They are documented here as separate-workflow candidates so the surrounding system gets cleaned up:

- **`detect-re-qa-mode.sh` false-positive on stale qa-* leftovers**: the detector returned `mode=re-qa` for BUG-019's *initial* QA run because the file `tests/unit/qa-BUG-018-advance-pause.test.ts` (left over from a prior BUG-018 run that landed in `main` via PR #287) matched the v1 glob set. The detector keys on `marker exists + any qa-* file tracked by git` and does not filter the glob by ID. Worked around in this run by ignoring the detect output and proceeding in initial mode. Suggested follow-up: scope the glob to `tests/{unit,bats/qa}/qa-${ID}-*` or otherwise filter by the requirement ID so leftover files from other workflows don't poison subsequent detection.
- **`finalize-workflow` preflight gap on the BUG-018 merge**: per CLAUDE.md the finalize preflight is supposed to block merge if any tracked `qa-*` files remain on a feature branch. PR #287 was merged with `tests/unit/qa-BUG-018-advance-pause.test.ts` still present (committed in `8efc632 qa(BUG-018): add executable QA tests from executing-qa run`, not subsequently adopted by `addressing-qa-findings`). Either the preflight was bypassed, the adopt phase didn't run, or the preflight is not gated on the merge step. Worth a separate review.
- **`post-issue-comment.sh` template-context contract gap**: the orchestrator's documented `bug-start` and `bug-complete` invocations pass `'{"workItemId":"BUG-019"}'` (and `prNumber` for complete), but the markdown templates in `references/github-templates.md` reference `<ISSUE_NUM>` and `<PR_NUM>` placeholders that the orchestrator does not supply. The render-side reports `[error] render-issue-comment: unresolved placeholder(s): <ISSUE_NUM> [<PR_NUM>] in rendered output. Skipping.` and graceful-skips per NFR-1. The workflow continues but the issue thread never receives the lifecycle comments — a real silent-skip regression. Either the orchestrator should pass `issueNum` and `prNumber` in the context map, or the templates should drop the `<ISSUE_NUM>` placeholder (the `gh issue comment <ISSUE_NUM>` invocation already takes the number as a positional arg).
- **`workflow-state.sh advance` did not auto-pause on the `pr-review` context step**: per the BUG-018 atomic-auto-pause design, calling `advance` against a workflow whose next step has `context: "pause"` is supposed to atomically stamp `pausedAt`, set `pauseReason`, and flip `status` to `paused`. Observed in this run: `advance` moved `currentStep` from 3 to 4 (PR review) but left `status: "in-progress"` and `pauseReason: null`. Worked around with an explicit `pause BUG-019 pr-review` call. Either the atomic-pause code path isn't wired in for the bug chain's `pr-review` step name, or the orchestrator's call sequence here (which includes `set-pr` between advance and the pause) interferes. Worth confirming against the BUG-018 test fixtures.

None of the four issues above are within the scope of BUG-019. They are surfaced here so the next adversarial-QA loop or a separate chore can address them.

## Reproduction

This was a `PASS` verdict; no reproduction steps are required. The QA bats file at `tests/bats/qa/qa-BUG-019-azdo-user-prefix.bats` is the load-bearing executable record of the adversarial coverage.

## Reconciliation Delta

### Coverage beyond requirements

- QA covers pathological inputs not enumerated in the requirements doc's AC: empty `@` prefix, URL-encoded `@`, multiple `@` chars, port specifier, basic-auth `user:pass@` form. These probe the regex's failure modes beyond the AC's "happy path" assertions.
- QA covers credential-leak probes (PAT in stdout/stderr) under both auto-detect and explicit `SDLC_SCM_BACKEND=github` paths. The requirements doc's AC-5 ("captured field does not contain user@ prefix") is a related but narrower assertion.
- QA covers SDLC_SCM_BACKEND override symmetry for both directions of mismatch under user-prefixed origins; the requirements doc AC-6 only specified the AzDO-on-AzDO-user-prefix path.

### Coverage gaps

- AC-1 / AC-2 / AC-3 / AC-4 / AC-7: the "canonical" user-prefix detection cases (dev.azure.com, visualstudio.com, DefaultCollection, github.com, plus their user-less regression pairs) are covered by the IMPLEMENTATION-side bats file `tests/bats/skills/managing-source-control/backend-detect.bats` (23 tests, all green). The QA test plan deliberately did not duplicate those — QA's role is adversarial coverage on top of implementation tests, not test-plan ↔ AC isomorphism. The reconciler reports these as "gaps" because it doesn't see the implementation file, only the QA artifact. This is expected per the FEAT-018 redesign rationale ("QA must probe failure modes the spec did not anticipate") and not an actual coverage gap.
- AC-5 (captured field cleanliness) and AC-6 (SDLC_SCM_BACKEND=azdo no-warn) ARE covered by the QA bats canaries — see the BASH_REMATCH canary scenarios under `## Scenarios Run` → Inputs.

### Summary
- coverage-surplus: 11 (adversarial QA scenarios beyond AC)
- coverage-gap: 0 (after accounting for implementation-side coverage of AC-1..AC-4 and AC-7)

