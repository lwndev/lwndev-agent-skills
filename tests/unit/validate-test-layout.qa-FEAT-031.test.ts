/**
 * Adversarial QA coverage for FEAT-031 (consolidate test layout).
 *
 * Covers the P0/P1 scenarios from qa/test-plans/QA-plan-FEAT-031.md that are
 * NOT exercised by the existing tests/unit/validate-test-layout.test.ts and
 * tests/bats/shared/hooks/validate-test-layout-hook.bats suites.
 *
 * Dimensions:
 *   - Inputs: pathological filenames (spaces, parens, quotes, Unicode), deep
 *     nesting, .test.tsx (which must NOT be classified).
 *   - Cross-cutting: validator and hook share the same rule module — single
 *     source of truth for rule IDs, allow-rule, and CANONICAL_DESTINATIONS.
 *   - Environment / Dependency failure: bats devDep present in package.json,
 *     pinned in the 1.x range so a future major bump cannot be silently picked
 *     up.
 */

import { describe, it, expect } from 'vitest';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { mkdtemp, mkdir, writeFile, rm, cp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import {
  classifyPath,
  ALLOWED_FIXTURE_PATHS,
  CANONICAL_DESTINATIONS,
  RULE_TS_OUTSIDE_TESTS_UNIT,
  RULE_SPEC_EXTENSION_DISALLOWED,
  RULE_BATS_OUTSIDE_TESTS_BATS,
} from '../../scripts/test-layout-rules.js';

const REPO_ROOT = resolve(__dirname, '..', '..');
const VALIDATOR = resolve(REPO_ROOT, 'scripts', 'validate-test-layout.ts');
const HOOK = resolve(REPO_ROOT, 'scripts', 'hooks', 'validate-test-layout-hook.ts');
const TEST_LAYOUT_RULES = resolve(REPO_ROOT, 'scripts', 'test-layout-rules.ts');
const VALIDATOR_SOURCE = readFileSync(VALIDATOR, 'utf-8');
const HOOK_SOURCE = readFileSync(HOOK, 'utf-8');

interface RunResult {
  status: number | null;
  stdout: string;
  stderr: string;
}

function runValidator(cwd: string): RunResult {
  const res = spawnSync('npx', ['tsx', VALIDATOR], {
    cwd,
    encoding: 'utf-8',
    env: { ...process.env, NODE_NO_WARNINGS: '1' },
  });
  return { status: res.status, stdout: res.stdout, stderr: res.stderr };
}

function fireHook(filePath: string, cwd: string = REPO_ROOT): RunResult {
  const payload = JSON.stringify({ tool_name: 'Write', tool_input: { file_path: filePath } });
  const res = spawnSync('npx', ['tsx', HOOK], {
    cwd,
    encoding: 'utf-8',
    input: payload,
    env: { ...process.env, NODE_NO_WARNINGS: '1' },
  });
  return { status: res.status, stdout: res.stdout, stderr: res.stderr };
}

async function buildWorktree(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), 'qa-FEAT-031-'));
  await mkdir(join(dir, 'scripts'), { recursive: true });
  await mkdir(join(dir, 'plugins'), { recursive: true });
  await mkdir(join(dir, 'tests', 'unit'), { recursive: true });
  await mkdir(join(dir, 'tests', 'bats', 'shared'), { recursive: true });
  await cp(VALIDATOR, join(dir, 'scripts', 'validate-test-layout.ts'));
  await cp(TEST_LAYOUT_RULES, join(dir, 'scripts', 'test-layout-rules.ts'));
  return dir;
}

describe('FEAT-031 QA — Inputs dimension (pathological filenames)', () => {
  it('classifyPath: tolerates spaces in correctly-placed paths', () => {
    expect(classifyPath('tests/unit/foo bar.test.ts')).toBeNull();
    expect(classifyPath('tests/bats/shared/foo bar.bats')).toBeNull();
  });

  it('classifyPath: tolerates parentheses, single quotes, and Unicode in correctly-placed paths', () => {
    expect(classifyPath('tests/unit/résumé (final).test.ts')).toBeNull();
    expect(classifyPath("tests/unit/o'brien.test.ts")).toBeNull();
    expect(classifyPath('tests/unit/日本語.test.ts')).toBeNull();
  });

  it('classifyPath: still fires on misplaced paths with spaces / Unicode', () => {
    expect(classifyPath('scripts/foo bar.test.ts')).toEqual({
      rule: RULE_TS_OUTSIDE_TESTS_UNIT,
    });
    expect(classifyPath('scripts/résumé.test.ts')).toEqual({
      rule: RULE_TS_OUTSIDE_TESTS_UNIT,
    });
  });

  it('classifyPath: deeply-nested misplaced path is still flagged with full path preserved', () => {
    const deep = 'plugins/a/b/c/d/e/foo.test.ts';
    expect(classifyPath(deep)).toEqual({ rule: RULE_TS_OUTSIDE_TESTS_UNIT });
  });

  it('validator: deeply-nested misplaced path appears verbatim in FAIL line', async () => {
    const dir = await buildWorktree();
    try {
      await mkdir(join(dir, 'plugins', 'a', 'b', 'c', 'd', 'e'), { recursive: true });
      await writeFile(
        join(dir, 'plugins', 'a', 'b', 'c', 'd', 'e', 'deep.test.ts'),
        'import {} from "vitest";\n'
      );
      const r = runValidator(dir);
      expect(r.status).toBe(1);
      expect(r.stdout).toContain('plugins/a/b/c/d/e/deep.test.ts');
      expect(r.stdout).toContain(`rule=${RULE_TS_OUTSIDE_TESTS_UNIT}`);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  }, 30_000);

  it('classifyPath: .test.tsx is NOT classified (no .tsx test files in this repo)', () => {
    // The classifier deliberately matches only .test.ts (not .test.tsx). This
    // documents the boundary so a future .tsx test file would fall outside the
    // current rule and need explicit handling.
    expect(classifyPath('scripts/foo.test.tsx')).toBeNull();
    expect(classifyPath('plugins/bar/foo.test.tsx')).toBeNull();
    expect(classifyPath('tests/unit/foo.test.tsx')).toBeNull();
  });

  it('hook: rejects misplaced .test.ts with a Unicode filename', () => {
    const r = fireHook('scripts/résumé.test.ts');
    expect(r.status).toBe(1);
    expect(r.stdout).toContain(`violates ${RULE_TS_OUTSIDE_TESTS_UNIT}`);
    expect(r.stdout).toContain('résumé');
  }, 30_000);

  it('hook: accepts very long file paths (>1KB)', () => {
    // Build a path under tests/unit/ longer than 1KB. Must be allowed.
    const segment = 'a'.repeat(64);
    const longSegments = Array.from({ length: 16 }, () => segment).join('/');
    const longPath = `tests/unit/${longSegments}/foo.test.ts`;
    expect(longPath.length).toBeGreaterThan(1024);
    const r = fireHook(longPath);
    expect(r.status).toBe(0);
    expect(r.stdout).not.toMatch(/reject/);
  }, 30_000);
});

describe('FEAT-031 QA — Cross-cutting (single source of truth)', () => {
  it('validator imports classifyPath from the shared rule module', () => {
    expect(VALIDATOR_SOURCE).toMatch(/from\s+['"]\.\/test-layout-rules\.js['"]/);
    expect(VALIDATOR_SOURCE).toMatch(/import\s*\{\s*[^}]*classifyPath[^}]*\}/);
  });

  it('hook imports classifyPath and CANONICAL_DESTINATIONS from the shared rule module', () => {
    expect(HOOK_SOURCE).toMatch(/from\s+['"]\.\.\/test-layout-rules\.js['"]/);
    expect(HOOK_SOURCE).toMatch(/import\s*\{\s*[^}]*classifyPath[^}]*\}/);
    expect(HOOK_SOURCE).toMatch(/CANONICAL_DESTINATIONS/);
  });

  it('rule ID strings are not hardcoded as duplicates in either consumer', () => {
    // The literal rule strings must appear in the rule module, NOT redefined
    // inline in the validator or hook source. Each consumer should reference
    // the rule via the imported constant or via output rendering of the
    // classifier result — never via a string literal that could drift.
    const ruleStrings = [
      'ts-outside-tests-unit',
      'spec-extension-disallowed',
      'bats-outside-tests-bats',
    ];
    for (const rule of ruleStrings) {
      expect(VALIDATOR_SOURCE).not.toContain(rule);
      expect(HOOK_SOURCE).not.toContain(rule);
    }
  });

  it('validator and hook agree on the allow-rule fixture path', () => {
    // Both must produce the "allow" verdict for every entry in the allow-list.
    for (const allowed of ALLOWED_FIXTURE_PATHS) {
      // Static API: classifier returns null.
      expect(classifyPath(allowed)).toBeNull();
      // Hook spawn: exit 0, no rejection text.
      const r = fireHook(allowed);
      expect(r.status).toBe(0);
      expect(r.stdout).not.toMatch(/reject/);
    }
  }, 30_000);

  it('validator and hook agree on rule firings for every rule', () => {
    // Pair each known rule with a canonical "guaranteed misplaced" path and
    // assert (a) the classifier returns that rule, and (b) the hook rejects
    // with the same rule string in the rejection message.
    const cases: Array<{ path: string; rule: string }> = [
      { path: 'scripts/violator.test.ts', rule: RULE_TS_OUTSIDE_TESTS_UNIT },
      { path: 'scripts/violator.spec.ts', rule: RULE_SPEC_EXTENSION_DISALLOWED },
      { path: 'plugins/violator.bats', rule: RULE_BATS_OUTSIDE_TESTS_BATS },
    ];
    for (const c of cases) {
      const verdict = classifyPath(c.path);
      expect(verdict).toEqual({ rule: c.rule });
      const hookResult = fireHook(c.path);
      expect(hookResult.status).toBe(1);
      expect(hookResult.stdout).toContain(`violates ${c.rule}`);
    }
  }, 30_000);

  it('CANONICAL_DESTINATIONS covers every exported rule constant', () => {
    const allRules = [
      RULE_TS_OUTSIDE_TESTS_UNIT,
      RULE_SPEC_EXTENSION_DISALLOWED,
      RULE_BATS_OUTSIDE_TESTS_BATS,
    ];
    for (const rule of allRules) {
      expect(CANONICAL_DESTINATIONS[rule]).toBeDefined();
      expect(CANONICAL_DESTINATIONS[rule]).toMatch(/tests\//);
    }
  });
});

describe('FEAT-031 QA — Environment / Dependency failure (bats devDep)', () => {
  const pkg = JSON.parse(readFileSync(resolve(REPO_ROOT, 'package.json'), 'utf-8'));

  it('package.json declares bats as a devDependency', () => {
    expect(pkg.devDependencies).toBeDefined();
    expect(pkg.devDependencies.bats).toBeDefined();
  });

  it('bats devDep is pinned to the 1.x major (caret-1)', () => {
    // Caret-1 range — a future 2.x major release MUST NOT be silently picked
    // up. Accept any "^1.x" / "^1.x.y" form.
    const range: string = pkg.devDependencies.bats;
    expect(range).toMatch(/^\^1\./);
  });

  it('npm test script chains :unit && :bats so a Bats failure propagates', () => {
    // The && semantics are what the QA plan flags as a P0 risk. We assert the
    // script body so a future refactor that changes the chain (semicolon,
    // npm-run-all without --serial, etc.) breaks this test loudly.
    expect(pkg.scripts.test).toBe('npm run test:unit && npm run test:bats');
  });

  it('npm run validate runs the layout validator before the build step', () => {
    // The validator must run *first* so a misplaced test file fails the
    // pre-commit gate (npm run validate) before the build step ever runs.
    expect(pkg.scripts.validate).toMatch(/^tsx scripts\/validate-test-layout\.ts\s*&&/);
  });
});
