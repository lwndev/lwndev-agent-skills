# FEAT-030 Known-Buggy Regression Fixture

Minimal vitest project used by `scripts/__tests__/feat-030-executing-qa.test.ts` to prove that the post-FEAT-030 `executing-qa` skill is **report-only** (FR-2) and that its scripted producers emit a contract-shaped artifact when the production code under test is broken.

## Layout

| Path                         | Role                                                                                                                                                                     |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `package.json`               | Declares `vitest` as devDep; `npm test` -> `vitest run`.                                                                                                                 |
| `vitest.config.ts`           | Plain-object config. Loadable without local `node_modules`.                                                                                                              |
| `tsconfig.json`              | TypeScript settings for the fixture sources.                                                                                                                             |
| `src/buggy.ts`               | **Deliberately buggy** production file. `classifyNumber()` inverts the sign. Do NOT fix.                                                                                 |
| `__tests__/qa-buggy.spec.ts` | Adversarial correctness test. Asserts `classifyNumber(5) === 'positive'` and `classifyNumber(-3) === 'negative'`. Fails because of the inverted sign in `src/buggy.ts`.  |
| `capability.json`            | Pre-built capability JSON the regression test passes to `run-framework.sh` and `render-qa-results.sh` (avoids re-running `capability-discovery.sh` against the fixture). |
| `QA-plan.md`                 | Version-2 QA plan with one P0 scenario in the Inputs dimension covering FR-1.                                                                                            |
| `requirements.md`            | Requirements doc with FR-1 + three AC entries matching the QA plan.                                                                                                      |

## Intended Verdict

`ISSUES-FOUND`. The buggy production code returns `'negative'` for positive inputs and `'positive'` for negative inputs.

## Expected Failing Test Names

The vitest run reports failures under the `qa-inputs: classifyNumber correctness` describe block:

- `classifyNumber(5) should equal positive`
- `classifyNumber(-3) should equal negative`

## Expected Workflow-State Findings Block

Per FR-1 / FR-11 (FEAT-030), `record-findings --type qa` persists this shape under `steps[<index>].findings` in the workflow state file:

```json
{
  "verdict": "ISSUES-FOUND",
  "passed": 0,
  "failed": 2,
  "errored": 0,
  "summary": "Adversarial correctness test revealed sign inversion in classifyNumber() (artifact: qa/test-results/QA-results-FEAT-030-FIXTURE.md)"
}
```

## What MUST NOT Happen

- `src/buggy.ts` is **never** modified during the regression run.
- The FR-10 stop-hook diff guard MUST block any attempt to edit `src/buggy.ts` during a QA run with the verbatim FR-10 error message naming the file.
