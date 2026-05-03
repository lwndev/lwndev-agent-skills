import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, rm, cp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import {
  classifyPath,
  ALLOWED_FIXTURE_PATHS,
  RULE_TS_OUTSIDE_TESTS_UNIT,
  RULE_SPEC_EXTENSION_DISALLOWED,
  RULE_BATS_OUTSIDE_TESTS_BATS,
} from '../../scripts/test-layout-rules.js';

const REPO_ROOT = resolve(__dirname, '..', '..');
const VALIDATOR = resolve(REPO_ROOT, 'scripts', 'validate-test-layout.ts');
const TEST_LAYOUT_RULES = resolve(REPO_ROOT, 'scripts', 'test-layout-rules.ts');

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

/**
 * Builds a synthetic worktree under a tmp dir that mirrors the WALK_ROOTS the
 * validator scans. The validator and its rule module are copied in so the
 * `tsx` process can resolve the import relative to the script being run.
 */
async function buildWorktree(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), 'validate-test-layout-'));
  await mkdir(join(dir, 'scripts'), { recursive: true });
  await mkdir(join(dir, 'plugins'), { recursive: true });
  await mkdir(join(dir, 'tests', 'unit'), { recursive: true });
  await mkdir(join(dir, 'tests', 'bats', 'shared'), { recursive: true });
  // Copy the validator + its sibling rule module so the relative import works.
  await cp(VALIDATOR, join(dir, 'scripts', 'validate-test-layout.ts'));
  await cp(TEST_LAYOUT_RULES, join(dir, 'scripts', 'test-layout-rules.ts'));
  return dir;
}

describe('classifyPath (rule module)', () => {
  it('returns null for non-test paths', () => {
    expect(classifyPath('scripts/build.ts')).toBeNull();
    expect(classifyPath('README.md')).toBeNull();
    expect(classifyPath('plugins/foo/skills/bar/SKILL.md')).toBeNull();
    expect(classifyPath('')).toBeNull();
  });

  it('fires ts-outside-tests-unit for *.test.ts outside tests/unit/', () => {
    expect(classifyPath('scripts/foo.test.ts')).toEqual({
      rule: RULE_TS_OUTSIDE_TESTS_UNIT,
    });
    expect(classifyPath('plugins/lwndev-sdlc/foo.test.ts')).toEqual({
      rule: RULE_TS_OUTSIDE_TESTS_UNIT,
    });
    expect(classifyPath('tests/integration/foo.test.ts')).toEqual({
      rule: RULE_TS_OUTSIDE_TESTS_UNIT,
    });
  });

  it('passes *.test.ts under tests/unit/', () => {
    expect(classifyPath('tests/unit/foo.test.ts')).toBeNull();
    expect(classifyPath('tests/unit/nested/dir/foo.test.ts')).toBeNull();
  });

  it('fires spec-extension-disallowed for any *.spec.ts not in allow-rule', () => {
    expect(classifyPath('tests/unit/foo.spec.ts')).toEqual({
      rule: RULE_SPEC_EXTENSION_DISALLOWED,
    });
    expect(classifyPath('scripts/__tests__/foo.spec.ts')).toEqual({
      rule: RULE_SPEC_EXTENSION_DISALLOWED,
    });
  });

  it('honors the feat-030-known-buggy allow-rule', () => {
    expect(ALLOWED_FIXTURE_PATHS).toContain(
      'scripts/__tests__/fixtures/feat-030-known-buggy/__tests__/qa-buggy.spec.ts'
    );
    for (const allowed of ALLOWED_FIXTURE_PATHS) {
      expect(classifyPath(allowed)).toBeNull();
    }
  });

  it('fires bats-outside-tests-bats for *.bats outside tests/bats/', () => {
    expect(classifyPath('plugins/lwndev-sdlc/scripts/tests/foo.bats')).toEqual({
      rule: RULE_BATS_OUTSIDE_TESTS_BATS,
    });
    expect(classifyPath('scripts/foo.bats')).toEqual({
      rule: RULE_BATS_OUTSIDE_TESTS_BATS,
    });
  });

  it('passes *.bats under tests/bats/', () => {
    expect(classifyPath('tests/bats/shared/foo.bats')).toBeNull();
    expect(classifyPath('tests/bats/skills/foo/bar.bats')).toBeNull();
  });

  it('normalizes leading ./ and back-slashes', () => {
    expect(classifyPath('./scripts/foo.test.ts')).toEqual({
      rule: RULE_TS_OUTSIDE_TESTS_UNIT,
    });
    expect(classifyPath('tests\\unit\\foo.test.ts')).toBeNull();
  });
});

describe('validate-test-layout.ts (script)', () => {
  let cleanTree: string;
  let dirtyTree: string;

  beforeAll(async () => {
    cleanTree = await buildWorktree();
    dirtyTree = await buildWorktree();

    // Clean tree: a file in each canonical leaf, plus a non-test file in
    // scripts/ to confirm the walker visits scripts/ but the classifier
    // ignores non-test paths.
    await writeFile(join(cleanTree, 'scripts', 'foo.ts'), '// non-test\n');
    await writeFile(join(cleanTree, 'tests', 'unit', 'good.test.ts'), 'import {} from "vitest";\n');
    await writeFile(
      join(cleanTree, 'tests', 'bats', 'shared', 'good.bats'),
      '#!/usr/bin/env bats\n'
    );

    // Dirty tree: one violation per rule + one allow-rule fixture path that
    // must NOT be flagged.
    await writeFile(join(dirtyTree, 'scripts', 'misplaced.test.ts'), 'import {} from "vitest";\n');
    await writeFile(join(dirtyTree, 'scripts', 'forbidden.spec.ts'), 'import {} from "vitest";\n');
    await mkdir(join(dirtyTree, 'plugins', 'foo'), { recursive: true });
    await writeFile(join(dirtyTree, 'plugins', 'foo', 'misplaced.bats'), '#!/usr/bin/env bats\n');
    // Allow-rule path: must pass even when the .spec.ts extension would
    // otherwise fire spec-extension-disallowed.
    const allowedDir = join(
      dirtyTree,
      'scripts',
      '__tests__',
      'fixtures',
      'feat-030-known-buggy',
      '__tests__'
    );
    await mkdir(allowedDir, { recursive: true });
    await writeFile(join(allowedDir, 'qa-buggy.spec.ts'), 'import {} from "vitest";\n');
  }, 30_000);

  afterAll(async () => {
    await rm(cleanTree, { recursive: true, force: true });
    await rm(dirtyTree, { recursive: true, force: true });
  });

  it('exits 0 with "0 violations" on a clean tree', () => {
    const r = runValidator(cleanTree);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('0 violations');
    expect(r.stdout).not.toMatch(/FAIL:/);
  });

  it('exits 1 and lists all three rule violations on a dirty tree', () => {
    const r = runValidator(dirtyTree);
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(
      /\[validate-test-layout\] FAIL: scripts\/misplaced\.test\.ts -> rule=ts-outside-tests-unit/
    );
    expect(r.stdout).toMatch(
      /\[validate-test-layout\] FAIL: scripts\/forbidden\.spec\.ts -> rule=spec-extension-disallowed/
    );
    expect(r.stdout).toMatch(
      /\[validate-test-layout\] FAIL: plugins\/foo\/misplaced\.bats -> rule=bats-outside-tests-bats/
    );
    expect(r.stdout).toContain('3 violations');
  });

  it('does not flag the feat-030-known-buggy allow-rule fixture', () => {
    const r = runValidator(dirtyTree);
    // The dirty tree includes the allow-rule fixture; the validator must NOT
    // emit a FAIL line for it.
    expect(r.stdout).not.toMatch(
      /scripts\/__tests__\/fixtures\/feat-030-known-buggy\/__tests__\/qa-buggy\.spec\.ts/
    );
  });

  it('emits the FR-9 output format (FAIL line + N violations summary)', () => {
    const r = runValidator(dirtyTree);
    const lines = r.stdout.trim().split('\n');
    const failLines = lines.filter((l) => l.startsWith('[validate-test-layout] FAIL:'));
    expect(failLines.length).toBe(3);
    expect(lines[lines.length - 1]).toBe('3 violations');
  });

  it('passes against the real repo tree (post-Phase-4 layout)', () => {
    const r = runValidator(REPO_ROOT);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('0 violations');
  }, 30_000);
});
