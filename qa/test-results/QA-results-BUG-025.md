---
id: BUG-025
version: 2
timestamp: 2026-06-02T01:55:28Z
verdict: PASS
persona: qa
---

## Summary

Verdict PASS: passed=12, failed=0, errored=0.

## Capability Report

```json
{
  "id": "BUG-025",
  "timestamp": "2026-06-02T01:02:19Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 12
- Passed: 12
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

QA tests are Bats cases graded on exit code (`npx bats` + exit code) because the SUT (`adopt-qa-test.sh`) is a Bash script and `run-framework.sh` parses vitest output only. All 12 cases passed (`1..12`, exit 0), committed at `tests/bats/qa/qa-BUG-025-adopt-multi-sut.bats`.

### Inputs
- [P0] 3 distinct SUTs each with a peer -> exit 0, picks lexicographically-first peer by full repo-relative path | mode: test-framework (RC-1)
- [P0] basename order opposite to full-path order -> full path wins | mode: test-framework (RC-1)
- [P0] imports SUTs with no peer anywhere -> exit 2, genuine no-peer guard intact | mode: test-framework (RC-1, RC-2)
- [P1] same SUT imported twice -> deduped to single peer, exit 0 | mode: test-framework (RC-1)
- [P1] `./foo` and `./foo.ts` mixed forms -> one peer after ext-strip, exit 0 | mode: test-framework (RC-1)

Justification: all Inputs scenarios passed; the multi-SUT tolerance and the preserved no-peer guard behave per RC-1/RC-2 with no defects.

### State transitions
- [P0] second adopt run after move -> exit 2 file not found; no partial state | mode: test-framework (RC-1)
- [P1] target `*.qa.test` sibling exists -> exit 1, no silent fallthrough pick | mode: test-framework (RC-1)
- [P1] multi-peer adoption routes through `git mv` -> original removed, sibling git-tracked (sole deleter) | mode: test-framework (RC-1)

Justification: idempotency, target-collision, and git-mv-as-deletion all hold; no partial-state defects observed.

### Environment
Justification: not applicable — `adopt-qa-test.sh` is a local `git mv` operation with no network, disk-pressure, or wrong-locale/timezone surface. Sort determinism is pinned via `LC_ALL=C` internally and is verified under Cross-cutting.

### Dependency failure
- [P2] single SUT base matches 2+ peers, no other singular -> exit 2 ambiguity reason verbatim | mode: test-framework (RC-1, RC-2)
- [P2] ambiguous SUT base + a second singular SUT -> exit 0, singular peer wins | mode: test-framework (RC-1)
- [P1] bats QA loads two scripts each with a `.bats` peer -> exit 0, lexicographically-first | mode: test-framework (RC-2)

Justification: framework-dispatch and `<<MULTI>>` ambiguity paths resolve deterministically; the restored multi-peer-specific exit-2 reason (commit 80653d1) is asserted verbatim. No defects.

### Cross-cutting
- [P1] identical multi-peer layout across two repos -> identical chosen sibling (determinism / reproducibility, locale-independent via `LC_ALL=C`) | mode: test-framework (RC-1)

Justification: the pick is reproducible across repos/runs; no locale or ordering nondeterminism found.

## Findings

## Reconciliation Delta

### Coverage beyond requirements
- Scenario "[P0] basename order opposite to full-path order -> full path wins | mode: test-framework (RC-1)" — not mentioned in spec

### Coverage gaps

### Summary
- coverage-surplus: 1
- coverage-gap: 0

