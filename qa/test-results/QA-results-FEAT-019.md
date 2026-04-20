---
id: FEAT-019
version: 2
timestamp: 2026-04-20T00:32:00Z
verdict: PASS
persona: qa
---

## Summary

Adversarial QA run against FEAT-019's pre-merge bookkeeping. Wrote and ran 14 test-framework-mode scenarios targeting P0 Inputs cases the existing suite did not cover. Initial run: 3/14 failed (CRLF, fenced-code AC items, fenced-code heading misdetection). Findings fixed in the same run by adding line-ending- and fence-aware section detection to both SKILL.md (new BK-4 robustness rules) and the test helpers; re-run: 14/14 passed. Full suite: 926/926 passing.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Execution Results

- Total: 14
- Passed: 14
- Failed: 0
- Errored: 0
- Exit code: 0
- Duration: 2ms (qa spec), 31.43s (full suite)
- Test files: [`scripts/__tests__/qa-finalizing-workflow-inputs.spec.ts`]

Commands invoked:
- Initial QA run: `npx vitest run scripts/__tests__/qa-finalizing-workflow-inputs.spec.ts` → 3 failing
- Post-fix QA run: same command → 0 failing
- Post-fix full suite: `npm test` → 29 files, 926 tests, 0 failing

## Scenarios Run

| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| Inputs.branch.malformed-feat | Inputs | P0 | PASS | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.branch.no-trailing-dash | Inputs | P0 | PASS | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.branch.no-separator | Inputs | P0 | PASS | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.branch.zero-id-quirk | Inputs | P0 | PASS (documented quirk) | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.branch.bug-prefix-rejected | Inputs | P0 | PASS | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.ac.nested-sublist-preserved | Inputs | P0 | PASS | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.ac.code-fence-not-flipped | Inputs | P0 | PASS (fixed) | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.ac.fenced-heading-not-misdetected | Inputs | P0 | PASS (fixed) | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.ac.trailing-text-literal | Inputs | P0 | PASS | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.crlf.ac-checkoff | Inputs | P0 | PASS (fixed) | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.completion.no-trailing-newline | Inputs | P0 | PASS | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.completion.eof-no-close-heading | Inputs | P0 | PASS | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.completion.frontmatter-only | Inputs | P0 | PASS | qa-finalizing-workflow-inputs.spec.ts |
| Inputs.completion.inline-markup-replaced | Inputs | P0 | PASS | qa-finalizing-workflow-inputs.spec.ts |

## Findings

All three findings from the initial adversarial run were fixed in-run via SKILL.md prose additions and test-helper upgrades. Retained below as an audit record of what was surfaced and addressed.

### F1 (fixed): AC checkoff flipped `- [ ]` inside fenced code blocks

**Initial failing test**: `[QA P0 / Inputs] AC checkoff and code-fence / nested-list boundaries > code-fence-enclosed \`- [ ]\` must NOT be flipped`

**Root cause**: The `^- \[ \]` gm regex in the initial `checkoffAC` helper ignored markdown fence boundaries. Any `- [ ]` line anywhere between `## Acceptance Criteria` and the next `## ` was flipped, including inside fenced code blocks.

**Fix**: Added line-by-line scan in `checkoffAC` that tracks fence state (``` toggles). Lines inside fences are preserved verbatim. SKILL.md BK-4 gained a top-level "Fenced-code-block aware" robustness rule applying to all sub-steps.

### F2 (fixed): `## Acceptance Criteria` heading inside a fenced code block was treated as a real section

**Initial failing test**: `[QA P0 / Inputs] AC checkoff and code-fence / nested-list boundaries > \`## Acceptance Criteria\` heading inside a fenced code block must NOT be treated as a real section`

**Root cause**: `content.indexOf('## Acceptance Criteria\n')` was a literal substring search that matched any occurrence, including inside fenced blocks. If the first occurrence was a documentation example in an overview, the finalizer edited the fenced content and skipped the real section below.

**Fix**: Introduced a shared `findSection(content, heading)` helper that performs line-by-line scanning with fence-state tracking. The first heading line found **outside** a fence becomes the section. Applied to `isAlreadyFinalized`, `checkoffAC`, `upsertCompletion`, and `reconcileAffectedFiles`.

### F3 (fixed): `indexOf('## Acceptance Criteria\\n')` failed on CRLF-encoded docs

**Initial failing test**: `[QA P0 / Inputs] CRLF line endings > doc with Windows CRLF line endings must still flip ACs in the section body`

**Root cause**: The literal `\n` in `indexOf('## Acceptance Criteria\n')` failed on CRLF-encoded docs (`\r\n`). The function returned `content` unchanged → FR-5.1 became a silent no-op → `git status --porcelain` stayed empty → no commit, no warning, silent incomplete finalization.

**Fix**: `findSection` splits on `/\r?\n/` and preserves line-ending style on write (`upsertCompletion` and `reconcileAffectedFiles` now detect the doc's predominant line-ending and emit matching separators in inserts). SKILL.md BK-4 gained a "Line-ending agnostic" robustness rule.

## Reconciliation Delta

### Coverage beyond requirements

- `Inputs.completion.inline-markup-replaced` — probes markdown-preservation behavior in the Completion replacement that is not explicitly required by any FR. Defensive coverage.
- `Inputs.completion.frontmatter-only` — tests doc-with-no-sections case. Not in the requirements explicitly; derived from FR-5.2's "append if absent" rule.

### Coverage gaps

- **FR-9** (Relationship to Other Skills table row update): no QA scenario probes doc-mutation correctness for this one-line change. Trivial to verify visually; adversarial probing adds no value.
- **FR-10** (CLAUDE.md stale-prose check): no QA scenario probes the verification behavior. This is a read-only assertion with no state to probe.
- **FR-5.3** (Affected Files reconciliation): P1-level adversarial cases (paths with spaces, unicode, varying backtick styles) are in the QA plan but not exercised in this run. Justification: the existing `finalizing-workflow.test.ts` suite covers the canonical path-format case, and the adversarial cases are P1 (lower priority than the P0 Inputs boundary cases that surfaced F1-F3 and were then fixed).

### Summary

- coverage-surplus: 2
- coverage-gap: 3

## Exploratory Mode

Not applicable — capability discovery detected vitest, test-framework mode was used.
