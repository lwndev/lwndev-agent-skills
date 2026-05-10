<!--
Version history: version-1 artifacts have no frontmatter `version` field and
live unmodified under `qa/test-results/QA-results-*.md` (pre-redesign
format, 34 files preserved per NFR-3). Any parser MUST treat the absence of
the `version` field as version 1. New runs under the FEAT-018 redesign
produce version 2 using this template.

This template is consumed by the executing-qa skill (FR-5 / FR-9). The
stop hook at plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh
validates the structural rules below:
  - Frontmatter MUST have `version: 2` and `verdict: PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY`.
  - For PASS/ISSUES-FOUND: `## Execution Results` MUST have Total/Passed/Failed/Errored + `Exit code` lines.
  - For PASS: `Failed: 0` (the verdict must be consistent with the counts).
  - For ISSUES-FOUND: `## Findings` MUST list at least one failing test name.
  - For ERROR: a stack trace MUST appear somewhere in the artifact.
  - For EXPLORATORY-ONLY: `## Exploratory Mode` MUST be present with a `Reason:` line.
-->

---
id: FEAT-XXX
version: 2
timestamp: 2026-04-19T14:22:00Z
verdict: PASS
persona: qa
---

## Summary

{One-line summary of the run}

## Capability Report

- Mode: test-framework | exploratory-only
- Framework: vitest | jest | pytest | go-test | none
- Package manager: npm | yarn | pnpm | none
- Test command: <string> | none
- Language: typescript | javascript | python | go | none

## Execution Results

- Total: 0
- Passed: 0
- Failed: 0
- Errored: 0
- Exit code: 0
- Duration: 0s
- Test files: []

## Scenarios Run

| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|

## Findings

{Per finding: severity | dimension | title | reproduction | evidence.
 For ISSUES-FOUND verdict, at least one entry listing a failing test name is
 required. For ERROR verdict, include the stack trace here or in
 `## Execution Results`.

 Each finding under ISSUES-FOUND MUST include a `## Reproduction` block
 (FEAT-032 FR-2) embedding the QA test source as a language-aware fenced
 code block with a single-line path-comment header naming the relative
 source path:
   - `.ts` / `.tsx`  -> ```typescript fence + `// path/to/file.ts` header
   - `.js`           -> ```javascript fence + `// path/to/file.js` header
   - `.bats` / `.sh` -> ```bash       fence + `# path/to/file.bats` header
   - `.py`           -> ```python     fence + `# path/to/file.py` header
   - `.go`           -> ```go         fence + `// path/to/file.go` header
 The embedded source is the load-bearing input for the
 `addressing-qa-findings` fix phase.}

### Example finding (shape)

#### Finding: tests/unit/qa-input-validation.test.ts > rejects empty input

##### Reproduction

```typescript
// tests/unit/qa-input-validation.test.ts
import { validate } from '../../src/buggy-fn';
import { describe, it, expect } from 'vitest';

describe('validate', () => {
  it('rejects empty input', () => {
    expect(() => validate('')).toThrow();
  });
});
```

## Reconciliation Delta

### Coverage beyond requirements
- {scenario X — not mentioned in spec}

### Coverage gaps
- {FR-N / AC — no corresponding scenario in plan}

### Summary
- coverage-surplus: 0
- coverage-gap: 0

## Exploratory Mode

{Only populated for EXPLORATORY-ONLY runs. MUST contain a `Reason:` line
 explaining why the run fell back to exploratory mode (framework not
 detected, no executable tests could be written, etc.). The stop hook
 rejects EXPLORATORY-ONLY artifacts without a `Reason:` line.}

Reason: <reason the run is exploratory-only>
Dimensions covered: inputs, state-transitions, environment, dependency-failure, cross-cutting
