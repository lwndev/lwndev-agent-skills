import { describe, it, expect, beforeAll, afterEach } from 'vitest';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  mkdtempSync,
  rmSync,
  mkdirSync,
  writeFileSync,
  cpSync,
  existsSync,
  readFileSync,
} from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

// Phase 8 — end-to-end fixture-based QA integration.
//
// These tests exercise the complete path that the redesigned executing-qa
// skill takes when invoked against a consumer repo: capability discovery →
// test-file write → runner execution → verdict. The two fixtures cover the
// two operating modes:
//
//   * qa-fixture/       : vitest-based consumer with a deliberate off-by-one
//                         bug in src/add.ts. Writing a correctness test and
//                         running vitest MUST produce a non-zero exit and a
//                         failing-test name — i.e., an ISSUES-FOUND-shaped
//                         result.
//
//   * qa-fixture-empty/ : no framework signals. capability-discovery.sh MUST
//                         emit mode: exploratory-only so the skill can fall
//                         through to the structured-review path.
//
// The integration test does NOT invoke the executing-qa skill itself (that
// requires a Claude Code agent session); it simulates the write-and-run
// loop with direct shell calls so the full write → run → verdict path is
// exercised and observable in CI. The fixtures themselves are small enough
// to live alongside the unit-test fixtures (see `scripts/__tests__/fixtures/`).

const ROOT = process.cwd();
const CAPABILITY_DISCOVERY_SCRIPT = join(
  ROOT,
  'plugins/lwndev-sdlc/skills/documenting-qa/scripts/capability-discovery.sh'
);
const EXECUTING_QA_STOP_HOOK = join(
  ROOT,
  'plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh'
);
const QA_FIXTURE_SRC = join(ROOT, 'scripts/__tests__/fixtures/qa-fixture');
const QA_FIXTURE_EMPTY_SRC = join(ROOT, 'scripts/__tests__/fixtures/qa-fixture-empty');
const ROOT_VITEST_BIN = join(ROOT, 'node_modules/.bin/vitest');

type CapabilityReport = {
  id?: string;
  timestamp: string;
  mode: 'test-framework' | 'exploratory-only';
  framework: 'vitest' | 'jest' | 'pytest' | 'go-test' | null;
  packageManager: 'npm' | 'yarn' | 'pnpm' | null;
  testCommand: string | null;
  language: 'typescript' | 'javascript' | 'python' | 'go' | null;
  notes: string[];
};

function runCapabilityDiscovery(repoRoot: string, id?: string): CapabilityReport {
  const args = id ? [repoRoot, id] : [repoRoot];
  const out = execFileSync('bash', [CAPABILITY_DISCOVERY_SCRIPT, ...args], {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return JSON.parse(out) as CapabilityReport;
}

function copyFixture(srcDir: string, destParent: string): string {
  const dest = join(destParent, 'repo');
  cpSync(srcDir, dest, { recursive: true });
  return dest;
}

describe('QA integration (fixture-based)', () => {
  let workdir: string;

  beforeAll(() => {
    // Sanity: root vitest binary must be present — we invoke it against the
    // fixture so the fixture does not need its own node_modules install.
    expect(existsSync(ROOT_VITEST_BIN)).toBe(true);
  });

  afterEach(() => {
    if (workdir) rmSync(workdir, { recursive: true, force: true });
  });

  describe('qa-fixture (test-framework mode with deliberate bug)', () => {
    it('capability-discovery detects vitest and resolves testCommand to npm test', () => {
      workdir = mkdtempSync(join(tmpdir(), 'qa-integ-'));
      const repo = copyFixture(QA_FIXTURE_SRC, workdir);
      // Simulate a package-lock so package-manager resolves to npm (matches
      // the typical consumer-repo shape for vitest-based projects).
      writeFileSync(join(repo, 'package-lock.json'), '{}');
      // Pre-create __tests__ so no "no test directory" note is added.
      mkdirSync(join(repo, '__tests__'), { recursive: true });

      const report = runCapabilityDiscovery(repo);

      expect(report.mode).toBe('test-framework');
      expect(report.framework).toBe('vitest');
      expect(report.language).toBe('typescript');
      expect(report.packageManager).toBe('npm');
      expect(report.testCommand).toBe('npm test');
      expect(report.notes).toEqual([]);
    });

    it('writing a correctness test that calls add(1,2) and asserts toBe(3) produces non-zero exit and a failing test name', () => {
      workdir = mkdtempSync(join(tmpdir(), 'qa-integ-'));
      const repo = copyFixture(QA_FIXTURE_SRC, workdir);

      // Write the adversarial test exactly as the executing-qa skill would:
      // a boundary / correctness scenario targeting the add() API.
      const testsDir = join(repo, '__tests__');
      mkdirSync(testsDir, { recursive: true });
      const testFile = join(testsDir, 'qa-boundary.spec.ts');
      writeFileSync(
        testFile,
        `import { describe, it, expect } from 'vitest';\n` +
          `import { add } from '../src/add';\n` +
          `\n` +
          `describe('qa-boundary: add() correctness', () => {\n` +
          `  it('add(1, 2) should equal 3', () => {\n` +
          `    expect(add(1, 2)).toBe(3);\n` +
          `  });\n` +
          `});\n`
      );

      // Run vitest against the fixture using the root-level vitest binary
      // (the fixture itself has no node_modules — equivalent to the skill
      // running the consumer's testCommand after ensuring the runner is on
      // PATH).
      const result = spawnSync(
        ROOT_VITEST_BIN,
        ['run', '--root', repo, '--config', join(repo, 'vitest.config.ts')],
        { encoding: 'utf-8', cwd: repo }
      );

      expect(result.status).not.toBe(0);

      const combined = `${result.stdout || ''}\n${result.stderr || ''}`;
      expect(combined).toMatch(/qa-boundary/);
      // Vitest prints "FAIL" for the failing file and "add(1, 2) should equal 3"
      // for the failing test. Assert the failing-test marker is observable.
      expect(combined).toMatch(/add\(1, 2\) should equal 3/);
    });

    it('executing-qa stop-hook accepts a hand-built v2 ISSUES-FOUND artifact that matches the observed failure', () => {
      workdir = mkdtempSync(join(tmpdir(), 'qa-integ-'));
      // Simulate the repo layout the stop hook expects (active file +
      // qa/test-results/ artifact + FR-10 baseline marker).
      const repo = workdir;
      mkdirSync(join(repo, '.sdlc', 'qa'), { recursive: true });
      writeFileSync(join(repo, '.sdlc', 'qa', '.executing-active'), '');
      // FR-10: write a dummy baseline marker so the diff guard does not fail
      // closed. The temp dir is not a git repo, so git diff returns empty
      // (no offending files) once the marker exists.
      writeFileSync(
        join(repo, '.sdlc', 'qa', '.executing-qa-baseline-FIXTURE'),
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
      );
      mkdirSync(join(repo, 'qa', 'test-results'), { recursive: true });
      const artifactPath = join(repo, 'qa', 'test-results', 'QA-results-FIXTURE.md');
      writeFileSync(
        artifactPath,
        `---
id: FIXTURE
version: 2
timestamp: 2026-04-19T14:22:00Z
verdict: ISSUES-FOUND
persona: qa
---

## Summary
Adversarial correctness test revealed an off-by-one in add().

## Capability Report
- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Execution Results
- Total: 1
- Passed: 0
- Failed: 1
- Errored: 0
- Exit code: 1
- Duration: 1s
- Test files: [__tests__/qa-boundary.spec.ts]

## Scenarios Run
| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| 1  | Inputs    | P0       | FAIL   | __tests__/qa-boundary.spec.ts |

## Findings
- __tests__/qa-boundary.spec.ts: failing test "add(1, 2) should equal 3" — expected 3, received 4 (off-by-one in src/add.ts)

## Reconciliation Delta
### Coverage beyond requirements
### Coverage gaps
### Summary
- coverage-surplus: 0
- coverage-gap: 0
`
      );

      const result = spawnSync('bash', [EXECUTING_QA_STOP_HOOK], {
        cwd: repo,
        input: JSON.stringify({
          last_assistant_message: `Results saved to qa/test-results/QA-results-FIXTURE.md`,
        }),
        encoding: 'utf-8',
      });

      expect(result.status).toBe(0);
      // Hook deletes the active file on success.
      expect(existsSync(join(repo, '.sdlc', 'qa', '.executing-active'))).toBe(false);
    });
  });

  describe('qa-fixture-empty (no-framework → exploratory-only)', () => {
    it('capability-discovery emits exploratory-only when no framework signals are present', () => {
      workdir = mkdtempSync(join(tmpdir(), 'qa-integ-'));
      const repo = copyFixture(QA_FIXTURE_EMPTY_SRC, workdir);

      const report = runCapabilityDiscovery(repo);

      expect(report.mode).toBe('exploratory-only');
      expect(report.framework).toBeNull();
      expect(report.testCommand).toBeNull();
      expect(report.language).toBeNull();
      expect(report.packageManager).toBeNull();
      expect(report.notes.join(' ')).toMatch(/No supported framework detected/);
    });

    it('executing-qa stop-hook accepts a v2 EXPLORATORY-ONLY artifact for a no-framework target', () => {
      workdir = mkdtempSync(join(tmpdir(), 'qa-integ-'));
      const repo = workdir;
      mkdirSync(join(repo, '.sdlc', 'qa'), { recursive: true });
      writeFileSync(join(repo, '.sdlc', 'qa', '.executing-active'), '');
      // FR-10: write a dummy baseline marker so the diff guard does not fail
      // closed. EXPLORATORY-ONLY → no framework → diff guard skips by design,
      // but the marker is still required by the fail-closed check.
      writeFileSync(
        join(repo, '.sdlc', 'qa', '.executing-qa-baseline-EMPTY'),
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
      );
      mkdirSync(join(repo, 'qa', 'test-results'), { recursive: true });
      const artifactPath = join(repo, 'qa', 'test-results', 'QA-results-EMPTY.md');
      writeFileSync(
        artifactPath,
        `---
id: EMPTY
version: 2
timestamp: 2026-04-19T14:22:00Z
verdict: EXPLORATORY-ONLY
persona: qa
---

## Summary
No test framework detected; falling back to structured exploratory review.

## Capability Report
- Mode: exploratory-only
- Framework: none
- Package manager: none
- Test command: none
- Language: none

## Scenarios Run
| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|

## Findings

## Reconciliation Delta
### Summary
Reconciliation delta skipped: no requirements doc for EMPTY

## Exploratory Mode
Reason: capability-discovery detected no vitest/jest/pytest/go-test signals in the target repo.
Dimensions covered: inputs, state-transitions, environment, dependency-failure, cross-cutting
`
      );

      const result = spawnSync('bash', [EXECUTING_QA_STOP_HOOK], {
        cwd: repo,
        input: JSON.stringify({
          last_assistant_message: `Results saved to qa/test-results/QA-results-EMPTY.md`,
        }),
        encoding: 'utf-8',
      });

      expect(result.status).toBe(0);
    });
  });

  describe('NFR-5 smoke artifact validation', () => {
    it('the committed FEAT-017 smoke artifact is accepted by the executing-qa stop-hook', () => {
      const smokeArtifactRepoPath = join(
        ROOT,
        'qa',
        'test-results',
        'QA-results-FEAT-017-smoke.md'
      );
      expect(existsSync(smokeArtifactRepoPath)).toBe(true);

      // Run the stop hook against the repo root so the artifact-discovery
      // path references the real committed file.
      workdir = mkdtempSync(join(tmpdir(), 'qa-integ-smoke-'));
      const repo = workdir;
      mkdirSync(join(repo, '.sdlc', 'qa'), { recursive: true });
      writeFileSync(join(repo, '.sdlc', 'qa', '.executing-active'), '');
      // FR-10: write a dummy baseline marker so the diff guard does not fail
      // closed. The temp dir is not a git repo, so git diff returns empty.
      writeFileSync(
        join(repo, '.sdlc', 'qa', '.executing-qa-baseline-FEAT-017-smoke'),
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
      );
      mkdirSync(join(repo, 'qa', 'test-results'), { recursive: true });
      // Copy the committed artifact into the temp repo so we do not need to
      // mutate the real .sdlc state during the test.
      const smokeCopyPath = join(repo, 'qa', 'test-results', 'QA-results-FEAT-017-smoke.md');
      writeFileSync(smokeCopyPath, readFileSync(smokeArtifactRepoPath, 'utf-8'));

      const result = spawnSync('bash', [EXECUTING_QA_STOP_HOOK], {
        cwd: repo,
        input: JSON.stringify({
          last_assistant_message: `Smoke-run results saved to qa/test-results/QA-results-FEAT-017-smoke.md`,
        }),
        encoding: 'utf-8',
      });

      expect(result.status).toBe(0);

      // Verify the verdict is one of the non-PASS options (NFR-5 evidence).
      const content = readFileSync(smokeArtifactRepoPath, 'utf-8');
      const verdictMatch = content.match(/^verdict:\s*(\S+)/m);
      expect(verdictMatch).not.toBeNull();
      expect(verdictMatch![1]).toMatch(/^(ISSUES-FOUND|ERROR|EXPLORATORY-ONLY)$/);
    });
  });
});
