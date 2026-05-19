// BUG-020 / AC6 — documentation invariants for the pause-step hardening:
//
//   (a) `step-execution-details.md` "### Pause Steps" section contains all
//       four load-bearing substrings (`load-bearing`, `HALT`,
//       `surface the pause artifact`, `work without stopping`).
//   (b) SKILL.md `:89` Load-bearing carve-out paragraph (the bullet starting
//       with `**Workflow-defined approval gates override`) contains the
//       substring `step-execution-details.md` (cross-link to the procedure).
//   (c) Each of the three Finalize fork-step blocks (Feature, Chore, Bug)
//       in `step-execution-details.md` contains the literal substring
//       `set-gate {ID} merge-approval`.
//
// Grep-style assertions over Markdown — no behavior coupling.

import { describe, it, expect, beforeAll } from 'vitest';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/orchestrating-workflows';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const STEP_EXECUTION_DETAILS_PATH = join(SKILL_DIR, 'references', 'step-execution-details.md');

describe('BUG-020 pause-step documentation invariants', () => {
  let skillMd: string;
  let stepDetails: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    stepDetails = await readFile(STEP_EXECUTION_DETAILS_PATH, 'utf-8');
  });

  describe('AC6(a) — Pause Steps section contains reaction-protocol tokens', () => {
    // Slice from the first `### Pause Steps` heading through the next `##`
    // heading (or EOF if no following heading). The section MUST contain the
    // four load-bearing substrings — case-sensitive on `HALT` and
    // `load-bearing` since those are the load-bearing tokens.
    let pauseStepsSection: string;

    beforeAll(() => {
      const headingIdx = stepDetails.indexOf('### Pause Steps');
      expect(headingIdx).toBeGreaterThanOrEqual(0);
      // Find the next `##`-or-`###`-or-deeper heading AFTER the heading line.
      // Use the `\n##` boundary; allow the section to extend to EOF.
      const afterHeading = headingIdx + '### Pause Steps'.length;
      const nextSectionIdx = stepDetails.indexOf('\n## ', afterHeading);
      pauseStepsSection =
        nextSectionIdx >= 0
          ? stepDetails.slice(headingIdx, nextSectionIdx)
          : stepDetails.slice(headingIdx);
    });

    it('contains the substring `load-bearing` (case-sensitive)', () => {
      expect(pauseStepsSection).toContain('load-bearing');
    });

    it('contains the substring `HALT` (case-sensitive)', () => {
      expect(pauseStepsSection).toContain('HALT');
    });

    it('contains the substring `surface the pause artifact`', () => {
      expect(pauseStepsSection).toContain('surface the pause artifact');
    });

    it('contains the substring `work without stopping`', () => {
      expect(pauseStepsSection).toContain('work without stopping');
    });
  });

  describe('AC6(b) — SKILL.md `:89` carve-out cross-links to step-execution-details.md', () => {
    it('the Load-bearing carve-out paragraph contains `step-execution-details.md`', () => {
      // Locate the bullet starting with `**Workflow-defined approval gates override`
      // and extract the paragraph (a single bullet line in the carve-out list).
      const bulletMarker = '**Workflow-defined approval gates override';
      const startIdx = skillMd.indexOf(bulletMarker);
      expect(startIdx).toBeGreaterThanOrEqual(0);
      // Paragraph ends at the next bullet (`\n- `) or the next blank line
      // separating list items / sections. Use the first sentinel that appears.
      const candidates = [
        skillMd.indexOf('\n- ', startIdx + bulletMarker.length),
        skillMd.indexOf('\n\n', startIdx + bulletMarker.length),
      ].filter((idx) => idx >= 0);
      const endIdx = candidates.length > 0 ? Math.min(...candidates) : skillMd.length;
      const carveOutParagraph = skillMd.slice(startIdx, endIdx);
      expect(carveOutParagraph).toContain('step-execution-details.md');
    });
  });

  describe('AC6(c) — Finalize fork-step blocks contain `set-gate {ID} merge-approval`', () => {
    it('the literal substring appears at least three times in step-execution-details.md', () => {
      // One occurrence per chain (Feature, Chore, Bug). Use a global regex
      // match so partial overlaps are caught explicitly.
      const target = 'set-gate {ID} merge-approval';
      const matches = stepDetails.split(target).length - 1;
      expect(matches).toBeGreaterThanOrEqual(3);
    });

    it('the substring appears within the Feature Chain Finalize block', () => {
      // Feature chain finalize block is anchored by the Feature-chain heading
      // and the Chore-chain heading further down the file.
      const featureHeadingIdx = stepDetails.indexOf(
        '### Feature Chain Step-Specific Fork Instructions'
      );
      const choreHeadingIdx = stepDetails.indexOf(
        '### Chore Chain Step-Specific Fork Instructions'
      );
      expect(featureHeadingIdx).toBeGreaterThanOrEqual(0);
      expect(choreHeadingIdx).toBeGreaterThan(featureHeadingIdx);
      const featureBlock = stepDetails.slice(featureHeadingIdx, choreHeadingIdx);
      expect(featureBlock).toContain('set-gate {ID} merge-approval');
    });

    it('the substring appears within the Chore Chain Finalize block', () => {
      const choreHeadingIdx = stepDetails.indexOf(
        '### Chore Chain Step-Specific Fork Instructions'
      );
      const bugMainHeadingIdx = stepDetails.indexOf('### Bug Chain Main-Context Steps');
      expect(choreHeadingIdx).toBeGreaterThanOrEqual(0);
      expect(bugMainHeadingIdx).toBeGreaterThan(choreHeadingIdx);
      const choreBlock = stepDetails.slice(choreHeadingIdx, bugMainHeadingIdx);
      expect(choreBlock).toContain('set-gate {ID} merge-approval');
    });

    it('the substring appears within the Bug Chain Finalize block', () => {
      const bugForkHeadingIdx = stepDetails.indexOf(
        '### Bug Chain Step-Specific Fork Instructions'
      );
      const pauseStepsHeadingIdx = stepDetails.indexOf('### Pause Steps');
      expect(bugForkHeadingIdx).toBeGreaterThanOrEqual(0);
      expect(pauseStepsHeadingIdx).toBeGreaterThan(bugForkHeadingIdx);
      const bugBlock = stepDetails.slice(bugForkHeadingIdx, pauseStepsHeadingIdx);
      expect(bugBlock).toContain('set-gate {ID} merge-approval');
    });
  });
});
