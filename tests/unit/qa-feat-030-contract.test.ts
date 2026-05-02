// QA test file for FEAT-030 — written by executing-qa.
//
// Scenario provenance: covers a focused subset of P0/P1 scenarios from
// qa/test-plans/QA-plan-FEAT-030.md that are NOT already covered by the
// 149 bats tests shipped in Phases 2-5 and the 6 regression vitest tests
// shipped in Phase 6. Each test names the dimension and scenario it covers.
//
// The plan's other scenarios are covered by:
//   - bats fixtures under plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/
//   - bats fixtures under plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/
//   - scripts/__tests__/feat-030-executing-qa.test.ts (regression vitest)

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const PLUGIN_ROOT = join(process.cwd(), 'plugins/lwndev-sdlc');
const SCRIPTS = join(PLUGIN_ROOT, 'skills/executing-qa/scripts');
const ORCHESTRATOR_SCRIPTS = join(PLUGIN_ROOT, 'skills/orchestrating-workflows/scripts');

function runBash(script: string, args: string[] = [], opts: { input?: string; cwd?: string } = {}) {
  try {
    const stdout = execFileSync('bash', [script, ...args], {
      encoding: 'utf-8',
      input: opts.input,
      cwd: opts.cwd ?? process.cwd(),
    });
    return { exitCode: 0, stdout, stderr: '' };
  } catch (e) {
    const err = e as { status?: number; stdout?: string | Buffer; stderr?: string | Buffer };
    return {
      exitCode: err.status ?? 1,
      stdout: err.stdout?.toString() ?? '',
      stderr: err.stderr?.toString() ?? '',
    };
  }
}

describe('FEAT-030 QA: Inputs dimension', () => {
  // P0: orchestrator parses a final-message line with extra whitespace
  // (test plan: scenario "orchestrator parses a final-message line with extra whitespace")
  it('parse-qa-return.sh REJECTS extra whitespace in final-message line (regex anchored)', () => {
    const r = runBash(join(ORCHESTRATOR_SCRIPTS, 'parse-qa-return.sh'), [
      'Verdict:   ISSUES-FOUND  | Passed: 15 | Failed: 3 | Errored: 0',
    ]);
    expect(r.exitCode).toBe(1);
    expect(r.stderr).toContain('contract mismatch');
  });

  // P0: render-qa-results.sh receives an unrecognized verdict value
  // (test plan: scenario "render-qa-results.sh receives an unrecognized verdict value")
  it('render-qa-results.sh exits 1 on invalid verdict "BROKEN"', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'qa-render-'));
    try {
      const cap = join(tmp, 'cap.json');
      const exec = join(tmp, 'exec.json');
      writeFileSync(cap, JSON.stringify({ mode: 'test-framework', framework: 'vitest', testCommand: 'npm test' }));
      writeFileSync(exec, JSON.stringify({ total: 1, passed: 1, failed: 0, errored: 0, exitCode: 0 }));
      const r = runBash(join(SCRIPTS, 'render-qa-results.sh'), ['FEAT-X', 'BROKEN', cap, exec]);
      expect(r.exitCode).toBe(1);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  // P1: orchestrator parses a final-message line where Verdict appears twice — LAST line wins
  // (test plan: scenario "Verdict appears twice (once in mid-text, once at end)")
  it('parse-qa-return.sh --stdin matches the LAST contract line in multi-line input', () => {
    const fakeResponse = [
      'Some narrative...',
      'Verdict: ERROR | Passed: 0 | Failed: 0 | Errored: 1',
      'More narrative...',
      'Verdict: PASS | Passed: 5 | Failed: 0 | Errored: 0',
    ].join('\n');
    const r = runBash(join(ORCHESTRATOR_SCRIPTS, 'parse-qa-return.sh'), ['--stdin'], { input: fakeResponse });
    expect(r.exitCode).toBe(0);
    const parsed = JSON.parse(r.stdout);
    expect(parsed.verdict).toBe('PASS');
    expect(parsed.passed).toBe(5);
  });
});

describe('FEAT-030 QA: State transitions dimension', () => {
  // P0: workflow-state.sh record-findings --type qa rejects stepIndex pointing to a non-QA step
  // (test plan: scenario "stepIndex pointing to a non-QA step")
  it('record-findings --type qa rejects when step is not the executing-qa step', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'qa-state-'));
    try {
      const cwd = tmp;
      mkdirSync(join(cwd, '.sdlc/workflows'), { recursive: true });
      writeFileSync(
        join(cwd, '.sdlc/workflows/FEAT-Y.json'),
        JSON.stringify({
          id: 'FEAT-Y',
          type: 'feature',
          currentStep: 0,
          status: 'in-progress',
          steps: [
            { name: 'Document feature requirements', skill: 'documenting-features', context: 'main', status: 'complete' },
            { name: 'Review requirements', skill: 'reviewing-requirements', context: 'fork', status: 'pending' },
          ],
          phases: { total: 0, completed: 0 },
          modelSelections: [],
        }),
      );
      const r = runBash(join(ORCHESTRATOR_SCRIPTS, 'workflow-state.sh'), [
        'record-findings',
        '--type', 'qa',
        'FEAT-Y', '1', 'PASS', '1', '0', '0', 'should reject',
      ], { cwd });
      expect(r.exitCode).not.toBe(0);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe('FEAT-030 QA: Cross-cutting (i18n, concurrency)', () => {
  // P0: qa-reconcile-delta.sh runs against requirements doc with CJK in FR descriptions
  // (test plan: scenario "qa-reconcile-delta.sh runs against requirements doc containing CJK")
  it('qa-reconcile-delta.sh preserves UTF-8 (CJK) end-to-end', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'qa-cjk-'));
    try {
      const reqDoc = join(tmp, 'req.md');
      const resDoc = join(tmp, 'res.md');
      writeFileSync(
        reqDoc,
        [
          '# Requirements',
          '## Functional Requirements',
          '### FR-1: 日本語サポート',
          'The system shall support 日本語 input.',
          '## Acceptance Criteria',
          '- [ ] 日本語 input round-trips through the parser',
        ].join('\n'),
      );
      writeFileSync(
        resDoc,
        [
          '# Results',
          '## Scenarios Run',
          '- 日本語 input round-trip test',
          '## Findings',
          '- (none)',
        ].join('\n'),
      );
      const r = runBash(join(SCRIPTS, 'qa-reconcile-delta.sh'), [resDoc, reqDoc]);
      expect(r.exitCode).toBe(0);
      // CJK preserved verbatim in the output
      expect(r.stdout).toContain('日本語');
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  // P0: orchestrator's parse path runs concurrently against different workflow IDs
  // (test plan: scenario "orchestrator's parse path runs concurrently with another orchestrator instance")
  it('record-findings --type qa for different IDs do not cross-contaminate', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'qa-conc-'));
    try {
      const cwd = tmp;
      mkdirSync(join(cwd, '.sdlc/workflows'), { recursive: true });
      const makeWorkflow = (id: string) =>
        JSON.stringify({
          id,
          type: 'feature',
          currentStep: 0,
          status: 'in-progress',
          steps: [{ name: 'Execute QA', skill: 'executing-qa', context: 'main', status: 'pending' }],
          phases: { total: 0, completed: 0 },
          modelSelections: [],
        });
      writeFileSync(join(cwd, '.sdlc/workflows/FEAT-A.json'), makeWorkflow('FEAT-A'));
      writeFileSync(join(cwd, '.sdlc/workflows/FEAT-B.json'), makeWorkflow('FEAT-B'));

      // Persist findings for A — should NOT touch B
      const r = runBash(join(ORCHESTRATOR_SCRIPTS, 'workflow-state.sh'), [
        'record-findings', '--type', 'qa',
        'FEAT-A', '0', 'PASS', '5', '0', '0', 'a summary',
      ], { cwd });
      expect(r.exitCode).toBe(0);

      // Read B back; must lack the findings block
      const rb = execFileSync('jq', ['-r', '.steps[0].findings // "no findings"', join(cwd, '.sdlc/workflows/FEAT-B.json')], { encoding: 'utf-8' });
      expect(rb.trim()).toBe('no findings');
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe('FEAT-030 QA: Dependency failure dimension', () => {
  // P1: orchestrator parse path against response missing the final-message line
  // (test plan: scenario "executing-qa response missing the final-message line entirely")
  it('parse-qa-return.sh --stdin emits contract-mismatch when no Verdict line present', () => {
    const fakeResponse = [
      'A response with no contract line.',
      'Just narrative all the way down.',
    ].join('\n');
    const r = runBash(join(ORCHESTRATOR_SCRIPTS, 'parse-qa-return.sh'), ['--stdin'], { input: fakeResponse });
    expect(r.exitCode).toBe(1);
    expect(r.stderr).toContain('contract mismatch');
  });
});
