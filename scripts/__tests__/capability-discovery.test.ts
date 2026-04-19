import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const SCRIPT = join(
  process.cwd(),
  'plugins/lwndev-sdlc/skills/documenting-qa/scripts/capability-discovery.sh'
);

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

function runScript(repoRoot: string, id?: string): CapabilityReport {
  const args = id ? [repoRoot, id] : [repoRoot];
  const out = execFileSync('bash', [SCRIPT, ...args], {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return JSON.parse(out) as CapabilityReport;
}

function writeJson(path: string, value: unknown): void {
  writeFileSync(path, JSON.stringify(value, null, 2));
}

let repo: string;

beforeEach(() => {
  repo = mkdtempSync(join(tmpdir(), 'cap-disc-'));
});

afterEach(() => {
  rmSync(repo, { recursive: true, force: true });
});

describe('capability-discovery.sh', () => {
  describe('vitest detection', () => {
    it('detects vitest via devDependencies + package-lock + scripts.test', () => {
      writeJson(join(repo, 'package.json'), {
        name: 'fixture',
        scripts: { test: 'vitest run' },
        devDependencies: { vitest: '^1.0.0' },
      });
      writeFileSync(join(repo, 'package-lock.json'), '{}');
      // Create a __tests__ directory so no "no test directory" note appears.
      mkdirSync(join(repo, '__tests__'), { recursive: true });

      const report = runScript(repo, 'FEAT-001');

      expect(report.id).toBe('FEAT-001');
      expect(report.mode).toBe('test-framework');
      expect(report.framework).toBe('vitest');
      expect(report.packageManager).toBe('npm');
      expect(report.testCommand).toBe('npm test');
      expect(report.language).toBe('javascript');
      expect(report.notes).toEqual([]);

      // Also writes a sidecar file at /tmp/qa-capability-{ID}.json
      const sidecar = `/tmp/qa-capability-FEAT-001.json`;
      expect(existsSync(sidecar)).toBe(true);
      const parsed = JSON.parse(readFileSync(sidecar, 'utf-8'));
      expect(parsed.framework).toBe('vitest');
      rmSync(sidecar, { force: true });
    });
  });

  describe('vitest config-file detection', () => {
    it('detects vitest via vitest.config.ts when no package.json dep is listed', () => {
      writeFileSync(join(repo, 'vitest.config.ts'), 'export default {};\n');
      const report = runScript(repo);
      expect(report.framework).toBe('vitest');
      expect(report.mode).toBe('test-framework');
    });
  });

  describe('jest detection', () => {
    it('detects jest via jest.config.js', () => {
      writeFileSync(join(repo, 'jest.config.js'), 'module.exports = {};\n');
      const report = runScript(repo);
      expect(report.framework).toBe('jest');
      expect(report.testCommand).toBe('npx jest');
    });

    it('detects jest via package.json dependency with yarn.lock', () => {
      writeJson(join(repo, 'package.json'), {
        devDependencies: { jest: '^29.0.0' },
        scripts: { test: 'jest' },
      });
      writeFileSync(join(repo, 'yarn.lock'), '');
      const report = runScript(repo);
      expect(report.framework).toBe('jest');
      expect(report.packageManager).toBe('yarn');
      expect(report.testCommand).toBe('yarn test');
    });
  });

  describe('pytest detection', () => {
    it('detects pytest via pytest.ini', () => {
      writeFileSync(join(repo, 'pytest.ini'), '[pytest]\n');
      mkdirSync(join(repo, 'tests'), { recursive: true });
      const report = runScript(repo);
      expect(report.framework).toBe('pytest');
      expect(report.language).toBe('python');
      expect(report.testCommand).toBe('pytest');
      expect(report.packageManager).toBeNull();
    });

    it('detects pytest via pyproject.toml containing pytest', () => {
      writeFileSync(
        join(repo, 'pyproject.toml'),
        '[tool.pytest.ini_options]\nminversion = "7.0"\n'
      );
      mkdirSync(join(repo, 'tests'), { recursive: true });
      const report = runScript(repo);
      expect(report.framework).toBe('pytest');
    });

    it('detects pytest via tests/test_*.py presence', () => {
      mkdirSync(join(repo, 'tests'), { recursive: true });
      writeFileSync(join(repo, 'tests', 'test_foo.py'), 'def test_x(): pass\n');
      const report = runScript(repo);
      expect(report.framework).toBe('pytest');
    });
  });

  describe('go-test detection', () => {
    it('detects go-test via go.mod + *_test.go', () => {
      writeFileSync(join(repo, 'go.mod'), 'module example.com/x\n\ngo 1.21\n');
      mkdirSync(join(repo, 'pkg'), { recursive: true });
      writeFileSync(join(repo, 'pkg', 'foo_test.go'), 'package pkg\n');
      const report = runScript(repo);
      expect(report.framework).toBe('go-test');
      expect(report.language).toBe('go');
      expect(report.testCommand).toBe('go test ./...');
    });
  });

  describe('package-manager detection', () => {
    it('prefers npm (package-lock.json) over yarn/pnpm when multiple lockfiles are present', () => {
      writeJson(join(repo, 'package.json'), {
        devDependencies: { vitest: '^1.0.0' },
        scripts: { test: 'vitest run' },
      });
      writeFileSync(join(repo, 'package-lock.json'), '{}');
      writeFileSync(join(repo, 'yarn.lock'), '');
      writeFileSync(join(repo, 'pnpm-lock.yaml'), '');
      const report = runScript(repo);
      expect(report.packageManager).toBe('npm');
      expect(report.testCommand).toBe('npm test');
    });

    it('detects pnpm via pnpm-lock.yaml when neither npm nor yarn lockfiles are present', () => {
      writeJson(join(repo, 'package.json'), {
        devDependencies: { jest: '^29.0.0' },
        scripts: { test: 'jest' },
      });
      writeFileSync(join(repo, 'pnpm-lock.yaml'), '');
      const report = runScript(repo);
      expect(report.packageManager).toBe('pnpm');
      expect(report.testCommand).toBe('pnpm test');
    });
  });

  describe('no-framework fallback', () => {
    it('emits exploratory-only mode when no detection signals are present', () => {
      const report = runScript(repo);
      expect(report.mode).toBe('exploratory-only');
      expect(report.framework).toBeNull();
      expect(report.packageManager).toBeNull();
      expect(report.testCommand).toBeNull();
      expect(report.language).toBeNull();
      expect(report.notes.some((n) => n.includes('No supported framework detected'))).toBe(true);
    });

    it('omits the id field when no ID argument is provided', () => {
      const report = runScript(repo);
      expect('id' in report).toBe(false);
    });
  });

  describe('multi-framework detection — edge case 1', () => {
    it('picks the first framework by precedence and emits a warning note', () => {
      writeJson(join(repo, 'package.json'), {
        devDependencies: { vitest: '^1.0.0', jest: '^29.0.0' },
        scripts: { test: 'vitest run' },
      });
      writeFileSync(join(repo, 'package-lock.json'), '{}');
      mkdirSync(join(repo, '__tests__'), { recursive: true });
      const report = runScript(repo);
      expect(report.framework).toBe('vitest');
      const hasWarning = report.notes.some(
        (n) => /multiple frameworks detected/i.test(n) && /vitest/.test(n) && /jest/.test(n)
      );
      expect(hasWarning).toBe(true);
    });
  });

  describe('no test-script fallback — edge case 2', () => {
    it('falls back to default runner command when scripts.test is absent', () => {
      writeJson(join(repo, 'package.json'), {
        devDependencies: { vitest: '^1.0.0' },
      });
      writeFileSync(join(repo, 'package-lock.json'), '{}');
      mkdirSync(join(repo, '__tests__'), { recursive: true });
      const report = runScript(repo);
      expect(report.testCommand).toBe('npx vitest run');
      expect(report.notes.some((n) => /no scripts\.test entry/.test(n))).toBe(true);
    });
  });

  describe('no test directory — edge case 6', () => {
    it('appends a note when jest is detected but no __tests__ directory exists', () => {
      writeJson(join(repo, 'package.json'), {
        devDependencies: { jest: '^29.0.0' },
        scripts: { test: 'jest' },
      });
      writeFileSync(join(repo, 'package-lock.json'), '{}');
      const report = runScript(repo);
      expect(report.framework).toBe('jest');
      expect(report.notes.some((n) => /no test directory found/.test(n))).toBe(true);
    });
  });

  describe('large repo — edge case 10', () => {
    it('completes quickly with bounded find depth on a large tree', () => {
      writeJson(join(repo, 'package.json'), {
        devDependencies: { vitest: '^1.0.0' },
        scripts: { test: 'vitest run' },
      });
      writeFileSync(join(repo, 'package-lock.json'), '{}');
      mkdirSync(join(repo, '__tests__'), { recursive: true });

      // Create a deeply-nested directory beyond maxdepth 5 with a bunch of siblings.
      for (let i = 0; i < 50; i++) {
        mkdirSync(join(repo, `pkg-${i}`, 'a', 'b', 'c', 'd', 'e'), { recursive: true });
      }

      const start = Date.now();
      const report = runScript(repo);
      const elapsed = Date.now() - start;

      expect(report.framework).toBe('vitest');
      expect(elapsed).toBeLessThan(5000);
    });
  });
});
