// QA tests for CHORE-036 — adversarial probing of the three new shared scripts.
// These tests run the actual scripts via execSync against temp directories so the
// real requirements/ tree is never touched. Test root: vitest under scripts/__tests__/.
// Verdict source: each test asserts the runner's actual exit code / stdout / stderr.

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execSync, type ExecSyncOptionsWithBufferEncoding } from 'node:child_process';
import {
  mkdtempSync,
  rmSync,
  mkdirSync,
  writeFileSync,
  existsSync,
  readdirSync,
  readFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { isAbsolute, join } from 'node:path';

const REPO_ROOT = process.cwd();
const PLUGIN_ROOT = join(REPO_ROOT, 'plugins', 'lwndev-sdlc');
const NEW_REQUIREMENT = join(PLUGIN_ROOT, 'scripts', 'new-requirement.sh');
const VALIDATE_CATEGORIES = join(PLUGIN_ROOT, 'scripts', 'validate-categories.sh');
const VALIDATE_RC = join(
  PLUGIN_ROOT,
  'skills',
  'documenting-bugs',
  'scripts',
  'validate-rc-traceability.sh'
);
const FEATURE_TEMPLATE = join(
  PLUGIN_ROOT,
  'skills',
  'documenting-features',
  'assets',
  'feature-requirements.md'
);
const CHORE_TEMPLATE = join(
  PLUGIN_ROOT,
  'skills',
  'documenting-chores',
  'assets',
  'chore-document.md'
);
const BUG_TEMPLATE = join(PLUGIN_ROOT, 'skills', 'documenting-bugs', 'assets', 'bug-document.md');

interface RunResult {
  status: number;
  stdout: string;
  stderr: string;
}

function run(cmd: string, cwd: string, env: Record<string, string> = {}): RunResult {
  const opts: ExecSyncOptionsWithBufferEncoding = {
    cwd,
    env: { ...process.env, ...env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    encoding: 'buffer',
    stdio: ['ignore', 'pipe', 'pipe'],
  };
  try {
    const stdout = execSync(cmd, opts);
    return { status: 0, stdout: stdout.toString('utf-8'), stderr: '' };
  } catch (err: unknown) {
    const e = err as { status?: number; stdout?: Buffer; stderr?: Buffer };
    return {
      status: e.status ?? -1,
      stdout: e.stdout?.toString('utf-8') ?? '',
      stderr: e.stderr?.toString('utf-8') ?? '',
    };
  }
}

function setupTempRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), 'qa-chore-036-'));
  // Initialise an empty git repo for the new-requirement.sh git-remote-parsing tests.
  execSync('git init --quiet --initial-branch=main', { cwd: dir });
  execSync('git config user.email "qa@example.com"', { cwd: dir });
  execSync('git config user.name "qa"', { cwd: dir });
  // Seed the templates the script reads — copy from the real plugin so the
  // tests exercise the real placeholder substitution without modifying them.
  for (const tmpl of [FEATURE_TEMPLATE, CHORE_TEMPLATE, BUG_TEMPLATE]) {
    expect(existsSync(tmpl), `template missing: ${tmpl}`).toBe(true);
  }
  return dir;
}

function resolveScriptPath(emitted: string, baseCwd: string): string {
  return isAbsolute(emitted) ? emitted : join(baseCwd, emitted);
}

function cleanupTempRepo(dir: string): void {
  // Restore write perms in case a test chmod'd them away, then remove.
  try {
    execSync(`chmod -R u+w "${dir}"`);
  } catch {
    /* best-effort */
  }
  rmSync(dir, { recursive: true, force: true });
}

describe('QA-CHORE-036: new-requirement.sh inputs (P0)', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = setupTempRepo();
  });
  afterEach(() => cleanupTempRepo(tmp));

  it('rejects --severity for FEAT with exit 2', () => {
    const r = run(`bash "${NEW_REQUIREMENT}" FEAT "Sample Feature" --severity high`, tmp);
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/--severity only accepted for BUG/);
  });

  it('rejects --severity for CHORE with exit 2', () => {
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "Sample Chore" --severity high`, tmp);
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/--severity only accepted for BUG/);
  });

  it('rejects --category for FEAT with exit 2 and CLI-honesty error', () => {
    const r = run(`bash "${NEW_REQUIREMENT}" FEAT "Sample Feature" --category refactoring`, tmp);
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/--category not accepted for FEAT/);
  });

  it('rejects stopwords-only title (slug empty)', () => {
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "the of and"`, tmp);
    expect(r.status).not.toBe(0);
    expect(r.stderr).toMatch(/slug.*empty|empty.*slug/i);
    // No file should be written.
    const choreDir = join(tmp, 'requirements', 'chores');
    expect(existsSync(choreDir) && readdirSync(choreDir).length > 0).toBe(false);
  });

  it('rejects BUG with chore-only category (cross-enum)', () => {
    const r = run(`bash "${NEW_REQUIREMENT}" BUG "Sample Bug" --category cleanup`, tmp);
    expect(r.status).toBe(2);
    // The bug enum must be listed
    expect(r.stderr).toMatch(/runtime-error/);
    expect(r.stderr).toMatch(/regression/);
  });

  it('does not execute shell metacharacters in title', () => {
    const sentinel = join(tmp, 'BREACH');
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE 'fix $(touch ${sentinel}) bug'`, tmp);
    // Whether the script succeeds or fails on this title, the sentinel must not exist.
    expect(existsSync(sentinel)).toBe(false);
    if (r.status === 0) {
      // If a file was written, its name must not contain '$' or parens.
      const written = r.stdout.trim();
      expect(written).not.toMatch(/[$()]/);
    }
  });

  it('rejects empty category string for CHORE via validate-categories.sh', () => {
    // Direct call to validate-categories.sh; --category="" through new-requirement.sh
    // would be parsed as an arg.
    const r = run(`bash "${VALIDATE_CATEGORIES}" CHORE ""`, tmp);
    expect(r.status).toBe(2);
  });
});

describe('QA-CHORE-036: new-requirement.sh state transitions (P0)', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = setupTempRepo();
  });
  afterEach(() => cleanupTempRepo(tmp));

  it('two consecutive invocations allocate two distinct IDs (monotonic)', () => {
    const r1 = run(`bash "${NEW_REQUIREMENT}" CHORE "first task"`, tmp);
    expect(r1.status).toBe(0);
    const path1 = r1.stdout.trim();
    expect(existsSync(resolveScriptPath(path1, tmp))).toBe(true);

    const r2 = run(`bash "${NEW_REQUIREMENT}" CHORE "second task"`, tmp);
    expect(r2.status).toBe(0);
    const path2 = r2.stdout.trim();
    expect(existsSync(resolveScriptPath(path2, tmp))).toBe(true);

    expect(path1).not.toBe(path2);
    // First file untouched (filenames differ → no overwrite is possible)
    const id1 = path1.match(/CHORE-(\d{3})/)?.[1];
    const id2 = path2.match(/CHORE-(\d{3})/)?.[1];
    expect(id1).toBeDefined();
    expect(id2).toBeDefined();
    expect(parseInt(id2!, 10)).toBe(parseInt(id1!, 10) + 1);
  });

  it('respects pre-existing high IDs (CHORE-099 → CHORE-100)', () => {
    const choresDir = join(tmp, 'requirements', 'chores');
    mkdirSync(choresDir, { recursive: true });
    writeFileSync(join(choresDir, 'CHORE-099-existing.md'), '# placeholder\n');

    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "next task"`, tmp);
    expect(r.status).toBe(0);
    const path = r.stdout.trim();
    expect(path).toMatch(/CHORE-100-/);
    expect(existsSync(join(choresDir, 'CHORE-099-existing.md'))).toBe(true);
  });
});

describe('QA-CHORE-036: new-requirement.sh environment (P0)', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = setupTempRepo();
  });
  afterEach(() => cleanupTempRepo(tmp));

  it('creates requirements/<type>/ when missing', () => {
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "fresh start"`, tmp);
    expect(r.status).toBe(0);
    expect(existsSync(join(tmp, 'requirements', 'chores'))).toBe(true);
    const path = r.stdout.trim();
    expect(existsSync(resolveScriptPath(path, tmp))).toBe(true);
  });

  it('parses an SSH GitHub remote into <org>/<repo> URL', () => {
    execSync('git remote add origin git@github.com:lwndev/lwndev-marketplace.git', { cwd: tmp });
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "ssh remote test" --issue 188`, tmp);
    expect(r.status).toBe(0);
    const path = resolveScriptPath(r.stdout.trim(), tmp);
    const content = readFileSync(path, 'utf-8');
    expect(content).toMatch(
      /\[#188\]\(https:\/\/github\.com\/lwndev\/lwndev-marketplace\/issues\/188\)/
    );
  });

  it('parses an HTTPS GitHub remote into <org>/<repo> URL', () => {
    execSync('git remote add origin https://github.com/lwndev/lwndev-marketplace.git', {
      cwd: tmp,
    });
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "https remote test" --issue 42`, tmp);
    expect(r.status).toBe(0);
    const path = resolveScriptPath(r.stdout.trim(), tmp);
    const content = readFileSync(path, 'utf-8');
    expect(content).toMatch(
      /\[#42\]\(https:\/\/github\.com\/lwndev\/lwndev-marketplace\/issues\/42\)/
    );
  });

  it('falls back to bare #N when there is no origin remote', () => {
    // Tmp repo has no origin set yet.
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "no remote test" --issue 99`, tmp);
    expect(r.status).toBe(0);
    const path = resolveScriptPath(r.stdout.trim(), tmp);
    const content = readFileSync(path, 'utf-8');
    // Must contain the issue ref...
    expect(content).toMatch(/#99/);
    // ...but NOT a github.com URL pointing at the missing org/repo.
    expect(content).not.toMatch(/https:\/\/github\.com\/[^/]+\/[^/]+\/issues\/99/);
  });

  it('falls back when the origin is a non-GitHub host', () => {
    execSync('git remote add origin https://gitlab.com/foo/bar.git', { cwd: tmp });
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "non-github remote" --issue 7`, tmp);
    expect(r.status).toBe(0);
    const path = resolveScriptPath(r.stdout.trim(), tmp);
    const content = readFileSync(path, 'utf-8');
    // gitlab.com URL must NOT be promoted to a github.com link.
    expect(content).not.toMatch(/https:\/\/github\.com\/foo\/bar\/issues\/7/);
  });
});

describe('QA-CHORE-036: validate-categories.sh inputs', () => {
  it('accepts the five chore categories', () => {
    for (const cat of [
      'dependencies',
      'documentation',
      'refactoring',
      'configuration',
      'cleanup',
    ]) {
      const r = run(`bash "${VALIDATE_CATEGORIES}" CHORE "${cat}"`, REPO_ROOT);
      expect(r.status, `chore category ${cat} should be accepted`).toBe(0);
    }
  });

  it('accepts the six bug categories', () => {
    for (const cat of [
      'runtime-error',
      'logic-error',
      'ui-defect',
      'performance',
      'security',
      'regression',
    ]) {
      const r = run(`bash "${VALIDATE_CATEGORIES}" BUG "${cat}"`, REPO_ROOT);
      expect(r.status, `bug category ${cat} should be accepted`).toBe(0);
    }
  });

  it('exits 0 silently for FEAT with any category (lower-level no-op)', () => {
    const r = run(`bash "${VALIDATE_CATEGORIES}" FEAT "anything"`, REPO_ROOT);
    expect(r.status).toBe(0);
    expect(r.stdout).toBe('');
  });

  it('rejects an unknown chore category with the allowed list on stderr', () => {
    const r = run(`bash "${VALIDATE_CATEGORIES}" CHORE "totally-bogus"`, REPO_ROOT);
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/totally-bogus/);
    expect(r.stderr).toMatch(/dependencies/);
  });

  it('rejects an unknown bug category with the allowed list on stderr', () => {
    const r = run(`bash "${VALIDATE_CATEGORIES}" BUG "ux-issue"`, REPO_ROOT);
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/ux-issue/);
    expect(r.stderr).toMatch(/runtime-error/);
  });

  it('rejects an invalid type', () => {
    const r = run(`bash "${VALIDATE_CATEGORIES}" SPEC "anything"`, REPO_ROOT);
    expect(r.status).toBe(2);
  });
});

describe('QA-CHORE-036: validate-rc-traceability.sh', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = setupTempRepo();
  });
  afterEach(() => cleanupTempRepo(tmp));

  function writeBugDoc(name: string, body: string): string {
    const path = join(tmp, name);
    writeFileSync(path, body);
    return path;
  }

  it('exits 0 when round-trip is satisfied', () => {
    const path = writeBugDoc(
      'bug-ok.md',
      [
        '# Bug: example',
        '',
        '## Root Cause(s)',
        '',
        'RC-1: cause one.',
        'RC-2: cause two.',
        '',
        '## Acceptance Criteria',
        '',
        '- [ ] First criterion (RC-1)',
        '- [ ] Second criterion (RC-2)',
        '',
      ].join('\n')
    );
    const r = run(`bash "${VALIDATE_RC}" "${path}"`, tmp);
    expect(r.status).toBe(0);
    const json = JSON.parse(r.stdout);
    expect(json.missingRCs).toEqual([]);
    expect(json.untaggedACs).toEqual([]);
  });

  it('reports missingRCs for an unreferenced root cause', () => {
    const path = writeBugDoc(
      'bug-missing.md',
      [
        '# Bug: missing rc',
        '',
        '## Root Cause(s)',
        '',
        'RC-1: cause one.',
        'RC-2: cause two.',
        '',
        '## Acceptance Criteria',
        '',
        '- [ ] Only references RC-1 (RC-1)',
        '',
      ].join('\n')
    );
    const r = run(`bash "${VALIDATE_RC}" "${path}"`, tmp);
    expect(r.status).toBe(1);
    const json = JSON.parse(r.stdout);
    expect(json.missingRCs).toContain('RC-2');
    expect(json.untaggedACs).toEqual([]);
  });

  it('reports untaggedACs for AC lines without (RC-N) tags', () => {
    const path = writeBugDoc(
      'bug-untagged.md',
      [
        '# Bug: untagged',
        '',
        '## Root Cause(s)',
        '',
        'RC-1: cause one.',
        '',
        '## Acceptance Criteria',
        '',
        '- [ ] AC referenced (RC-1)',
        '- [ ] AC without any tag at all',
        '',
      ].join('\n')
    );
    const r = run(`bash "${VALIDATE_RC}" "${path}"`, tmp);
    expect(r.status).toBe(1);
    const json = JSON.parse(r.stdout);
    expect(json.untaggedACs.length).toBeGreaterThan(0);
    expect(json.untaggedACs.join(' ')).toMatch(/without any tag/);
  });

  it('exits 2 when the Root Cause section is missing entirely', () => {
    const path = writeBugDoc(
      'bug-no-rc.md',
      ['# Bug: missing section', '', '## Acceptance Criteria', '- [ ] Some AC', ''].join('\n')
    );
    const r = run(`bash "${VALIDATE_RC}" "${path}"`, tmp);
    expect(r.status).toBe(2);
  });

  it('exits 2 when the Acceptance Criteria section is missing entirely', () => {
    const path = writeBugDoc(
      'bug-no-ac.md',
      ['# Bug: missing section', '', '## Root Cause(s)', '', 'RC-1: cause.', ''].join('\n')
    );
    const r = run(`bash "${VALIDATE_RC}" "${path}"`, tmp);
    expect(r.status).toBe(2);
  });

  it('exits 2 when the file is unreadable', () => {
    const r = run(`bash "${VALIDATE_RC}" "/nonexistent/path/to/bug.md"`, tmp);
    expect(r.status).toBe(2);
  });

  it('exits 2 with no args (usage error)', () => {
    const r = run(`bash "${VALIDATE_RC}"`, tmp);
    expect(r.status).toBe(2);
  });
});

describe('QA-CHORE-036: dependency failure (P0)', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = setupTempRepo();
  });
  afterEach(() => cleanupTempRepo(tmp));

  it('propagates validate-categories rejection: no file written when --category is invalid', () => {
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "valid title" --category bogus`, tmp);
    expect(r.status).not.toBe(0);
    const choreDir = join(tmp, 'requirements', 'chores');
    if (existsSync(choreDir)) {
      expect(readdirSync(choreDir)).toEqual([]);
    }
  });

  it('propagates slugify failure: no file written when title slugifies empty', () => {
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "the and or"`, tmp);
    expect(r.status).not.toBe(0);
    const choreDir = join(tmp, 'requirements', 'chores');
    if (existsSync(choreDir)) {
      expect(readdirSync(choreDir)).toEqual([]);
    }
  });
});

describe('QA-CHORE-036: cross-cutting / i18n', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = setupTempRepo();
  });
  afterEach(() => cleanupTempRepo(tmp));

  it('rejects non-Latin titles that strip to empty (Cyrillic only)', () => {
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "привет мир"`, tmp);
    expect(r.status).not.toBe(0);
    expect(r.stderr).toMatch(/slug.*empty|empty.*slug/i);
  });

  it('strips non-ASCII and keeps mixed-script titles when ASCII tokens remain', () => {
    const r = run(`bash "${NEW_REQUIREMENT}" CHORE "привет hello world fix"`, tmp);
    // Either the script accepts and writes a file with an ASCII-only slug, or
    // it rejects — both are defensible. Whatever it does, no command exec should occur
    // and no Cyrillic should appear in the filename.
    if (r.status === 0) {
      const path = r.stdout.trim();
      expect(path).toMatch(/CHORE-\d{3}-[a-z0-9-]+\.md$/);
      expect(path).not.toMatch(/[А-я]/);
    } else {
      expect(r.status).toBe(1);
    }
  });
});
