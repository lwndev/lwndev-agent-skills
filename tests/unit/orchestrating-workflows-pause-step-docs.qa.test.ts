// QA adversarial fixture for BUG-020 — Environment dimension doc invariants.
//
// Independent re-verification of P0/P1 doc-invariant scenarios from
// qa/test-plans/QA-plan-BUG-020.md (Environment dimension):
//   * Pause Steps section in step-execution-details.md contains all four
//     load-bearing substrings.
//   * Each of the three Finalize fork-step blocks contains the literal
//     substring `set-gate {ID} merge-approval`.
//   * SKILL.md `:89` Load-bearing carve-out paragraph contains the
//     `step-execution-details.md` cross-link.
//   * The carve-out enumerates all five gate identifiers.

import { describe, it, expect, beforeAll } from 'vitest';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/orchestrating-workflows';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const STEP_EXECUTION_DETAILS_PATH = join(SKILL_DIR, 'references', 'step-execution-details.md');

let skillMd = '';
let stepDetails = '';

beforeAll(async () => {
  skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
  stepDetails = await readFile(STEP_EXECUTION_DETAILS_PATH, 'utf-8');
});

describe('QA / BUG-020 / Environment — doc invariants', () => {
  it('[P0] Pause Steps section names load-bearing, HALT, surface the pause artifact, work without stopping', () => {
    const headingIdx = stepDetails.indexOf('### Pause Steps');
    expect(headingIdx).toBeGreaterThanOrEqual(0);
    const afterHeading = headingIdx + '### Pause Steps'.length;
    const nextSectionIdx = stepDetails.indexOf('\n## ', afterHeading);
    const section =
      nextSectionIdx >= 0
        ? stepDetails.slice(headingIdx, nextSectionIdx)
        : stepDetails.slice(headingIdx);
    expect(section).toContain('load-bearing');
    expect(section).toContain('HALT');
    expect(section).toContain('surface the pause artifact');
    expect(section).toContain('work without stopping');
  });

  it('[P0] step-execution-details.md contains the literal `set-gate {ID} merge-approval` at least three times (Feature, Chore, Bug Finalize blocks)', () => {
    const needle = 'set-gate {ID} merge-approval';
    const occurrences = stepDetails.split(needle).length - 1;
    expect(occurrences).toBeGreaterThanOrEqual(3);
  });

  it('[P0] SKILL.md carve-out (Workflow-defined approval gates override) cross-links to step-execution-details.md', () => {
    const carveOutIdx = skillMd.indexOf('**Workflow-defined approval gates override');
    expect(carveOutIdx).toBeGreaterThanOrEqual(0);
    const nextNewlineIdx = skillMd.indexOf('\n\n', carveOutIdx);
    const paragraph =
      nextNewlineIdx >= 0 ? skillMd.slice(carveOutIdx, nextNewlineIdx) : skillMd.slice(carveOutIdx);
    expect(paragraph).toContain('step-execution-details.md');
  });

  it('[P1] SKILL.md carve-out enumerates all five gate identifiers (plan-approval, pr-review, findings-decision, review-findings, merge-approval)', () => {
    const carveOutIdx = skillMd.indexOf('**Workflow-defined approval gates override');
    expect(carveOutIdx).toBeGreaterThanOrEqual(0);
    const nextNewlineIdx = skillMd.indexOf('\n\n', carveOutIdx);
    const paragraph =
      nextNewlineIdx >= 0 ? skillMd.slice(carveOutIdx, nextNewlineIdx) : skillMd.slice(carveOutIdx);
    for (const id of [
      'plan-approval',
      'pr-review',
      'findings-decision',
      'review-findings',
      'merge-approval',
    ]) {
      expect(paragraph).toContain(id);
    }
  });
});

describe('QA / BUG-020 / Dependency failure — plan structural conformance', () => {
  it('[P1] qa/test-plans/QA-plan-BUG-020.md retains v2 frontmatter and capability/scenarios sections', async () => {
    const planPath = 'qa/test-plans/QA-plan-BUG-020.md';
    const planText = await readFile(planPath, 'utf-8');
    expect(planText).toMatch(/^---\nid: BUG-020\nversion: 2\n/);
    expect(planText).toContain('## Capability Report');
    expect(planText).toContain('## Scenarios (by dimension)');
    expect(planText).toContain('## Non-applicable dimensions');
  });
});
