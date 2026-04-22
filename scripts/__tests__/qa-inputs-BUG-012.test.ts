import { describe, it, expect } from 'vitest';
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import semver from 'semver';

const ROOT = join(__dirname, '..', '..');
const FIXTURE_PACKAGE_JSON = join(ROOT, 'scripts/__tests__/fixtures/qa-fixture/package.json');
const CAPABILITY_DISCOVERY_SH = join(
  ROOT,
  'plugins/lwndev-sdlc/skills/executing-qa/scripts/capability-discovery.sh'
);
const QA_FIXTURE_DIR = join(ROOT, 'scripts/__tests__/fixtures/qa-fixture');

// GHSA-9crc-q9x8-hgqq / CVE-2025-24964 — advisory's vulnerable ranges
// transcribed as semver-compatible range strings (coerced to lowercase-only
// operator forms that node-semver accepts).
const VULNERABLE_WINDOWS = ['<=0.0.125', '>=1.0.0 <1.6.1', '>=2.0.0 <2.1.9', '>=3.0.0 <3.0.5'];

describe('BUG-012 — inputs dimension', () => {
  it('[P0] capability-discovery resolves the updated fixture as framework "vitest"', () => {
    const raw = execFileSync('bash', [CAPABILITY_DISCOVERY_SH, QA_FIXTURE_DIR, 'BUG-012'], {
      encoding: 'utf8',
      timeout: 30_000,
    });
    const report = JSON.parse(raw) as {
      framework: string;
      mode: string;
      testCommand: string;
    };
    // Primary detection signal must keep working after the pin.
    expect(report.framework).toBe('vitest');
    expect(report.mode).toBe('test-framework');
  });

  it('[P1] wildcard regression guard — fixture package.json has no bare "*" vitest range', () => {
    const contents = readFileSync(FIXTURE_PACKAGE_JSON, 'utf8');
    // Accept any whitespace between the key and the value; reject only the
    // unbounded "*" form. This catches an accidental revert.
    expect(contents).not.toMatch(/"vitest"\s*:\s*"\*"/);
  });

  it('[P1] declared vitest range does not intersect any advisory vulnerable window', () => {
    const manifest = JSON.parse(readFileSync(FIXTURE_PACKAGE_JSON, 'utf8')) as {
      devDependencies?: { vitest?: string };
    };
    const declaredRange = manifest.devDependencies?.vitest;
    expect(declaredRange).toBeDefined();
    expect(declaredRange).not.toBe('*');

    // Sanity: the pin keeps the devDep present (required by AC-1 to preserve
    // capability-discovery's pkg_has_dep detection path).
    expect(existsSync(FIXTURE_PACKAGE_JSON)).toBe(true);

    for (const window of VULNERABLE_WINDOWS) {
      expect(
        semver.intersects(declaredRange!, window),
        `declared range "${declaredRange}" must NOT intersect vulnerable window "${window}"`
      ).toBe(false);
    }
  });
});
