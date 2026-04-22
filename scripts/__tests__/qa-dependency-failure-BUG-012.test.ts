import { describe, it, expect } from 'vitest';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import semver from 'semver';

const ROOT = join(__dirname, '..', '..');
const INTEGRATION_TEST = join(ROOT, 'scripts/__tests__/qa-integration.test.ts');
const ROOT_VITEST_BIN = join(ROOT, 'node_modules/.bin/vitest');
const FIXTURE_PACKAGE_JSON = join(ROOT, 'scripts/__tests__/fixtures/qa-fixture/package.json');
const CAPABILITY_DISCOVERY_SH = join(
  ROOT,
  'plugins/lwndev-sdlc/skills/executing-qa/scripts/capability-discovery.sh'
);
const QA_FIXTURE_DIR = join(ROOT, 'scripts/__tests__/fixtures/qa-fixture');

const VULNERABLE_WINDOWS = ['<=0.0.125', '>=1.0.0 <1.6.1', '>=2.0.0 <2.1.9', '>=3.0.0 <3.0.5'];

// Future-version candidates covering minor and patch drift within the pinned
// major; each must be accepted by the declared range AND fall outside every
// vulnerable window.
const FUTURE_CANDIDATES = ['3.2.3', '3.2.99', '3.3.0', '3.99.0'];

describe('BUG-012 — dependency-failure dimension', () => {
  it('[P0] qa-integration test prerequisites still hold (file, root vitest bin, fixture detection)', () => {
    // Static prerequisites: the integration test file and the root-level vitest
    // binary it shells into must both exist. Without either one, scenario 4
    // would have collapsed silently.
    expect(existsSync(INTEGRATION_TEST)).toBe(true);
    expect(existsSync(ROOT_VITEST_BIN)).toBe(true);

    // Source-level sanity: the integration test references the root vitest
    // path and the updated fixture. A rename of either would invalidate the
    // end-to-end assertion chain.
    const src = readFileSync(INTEGRATION_TEST, 'utf8');
    expect(src).toContain('node_modules/.bin/vitest');
    expect(src).toContain('fixtures/qa-fixture');

    // Dynamic prerequisite: the same capability-discovery invocation the
    // integration test relies on still resolves the fixture as vitest after
    // the devDep pin. This is the load-bearing end-to-end signal short of
    // spawning nested vitest-in-vitest.
    const raw = execFileSync('bash', [CAPABILITY_DISCOVERY_SH, QA_FIXTURE_DIR, 'BUG-012'], {
      encoding: 'utf8',
      timeout: 30_000,
    });
    const report = JSON.parse(raw) as { framework: string; testCommand: string };
    expect(report.framework).toBe('vitest');
    expect(report.testCommand).toBe('npm test');
  });

  it('[P1] declared range accepts future vitest 3.x releases and excludes every vulnerable window', () => {
    const manifest = JSON.parse(readFileSync(FIXTURE_PACKAGE_JSON, 'utf8')) as {
      devDependencies?: { vitest?: string };
    };
    const declaredRange = manifest.devDependencies?.vitest;
    expect(declaredRange).toBeDefined();

    for (const candidate of FUTURE_CANDIDATES) {
      expect(
        semver.satisfies(candidate, declaredRange!),
        `declared range "${declaredRange}" must accept future candidate ${candidate}`
      ).toBe(true);
    }

    for (const window of VULNERABLE_WINDOWS) {
      expect(
        semver.intersects(declaredRange!, window),
        `declared range "${declaredRange}" must NOT intersect vulnerable window "${window}"`
      ).toBe(false);
    }
  });
});
