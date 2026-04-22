import { describe, it, expect } from 'vitest';
import { mkdtempSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

// FEAT-022 adversarial QA — probes failure modes the authoring bats fixtures
// did not cover. Organised by the five adversarial dimensions from the test
// plan at qa/test-plans/QA-plan-FEAT-022.md. Independent of the existing
// plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/*.bats suite;
// the bats suite covers the primary happy-path matrix and declared error
// taxonomy. This spec probes trust-boundary behaviour (shell-metachar
// injection, unicode-lookalike regex rejection, non-ASCII content bytes,
// PR-number boundary matching, prUrl-as-literal) against the real scripts.

const REPO_ROOT = process.cwd();
const BRANCH_ID_PARSE = join(REPO_ROOT, 'plugins/lwndev-sdlc/scripts/branch-id-parse.sh');
const CHECK_IDEMPOTENT = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/check-idempotent.sh'
);
const COMPLETION_UPSERT = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/completion-upsert.sh'
);
const RECONCILE_AFFECTED = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/reconcile-affected-files.sh'
);
const FINALIZE = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/finalize.sh'
);

function tmp(): string {
  return mkdtempSync(join(tmpdir(), 'qa-feat-022-'));
}

function run(script: string, args: string[], env: NodeJS.ProcessEnv = {}) {
  return spawnSync('bash', [script, ...args], {
    encoding: 'utf8',
    env: { ...process.env, ...env },
  });
}

// ---------------------------------------------------------------------------
// INPUTS dimension
// ---------------------------------------------------------------------------

describe('Inputs — branch-id-parse.sh', () => {
  it('[P0] shell-metachar branch name is treated as literal, no subshell', () => {
    const sentinel = join(tmp(), 'SENTINEL');
    // If the script evaluated the branch name, `touch SENTINEL` would fire.
    const malicious = `feat/FEAT-001-$(touch ${sentinel})-x`;
    const r = run(BRANCH_ID_PARSE, [malicious]);
    expect(existsSync(sentinel)).toBe(false);
    // The literal string contains the `$(...)` bytes; regex anchors still
    // extract FEAT-001 because `-` delimits and the rest is unmatched suffix.
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('"id":"FEAT-001"');
    expect(r.stdout).toContain('"type":"feature"');
  });

  it('[P0] unicode-lookalike release regex must be rejected (ASCII-only regex)', () => {
    // Cyrillic lowercase 'v' (U+0432) — visually indistinguishable but not ASCII.
    const cyrillicV = 'в';
    const branch = `release/plugin-${cyrillicV}1.0.0`;
    const r = run(BRANCH_ID_PARSE, [branch]);
    expect(r.status).toBe(1);
  });

  it('[P1] 1000-char branch name does not overflow or crash', () => {
    const branch = `feat/FEAT-001-${'x'.repeat(1000)}`;
    const r = run(BRANCH_ID_PARSE, [branch]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('"id":"FEAT-001"');
  });
});

describe('Inputs — check-idempotent.sh', () => {
  it('[P1] non-numeric prNumber rejected with exit 2', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    writeFileSync(doc, '# Doc\n');
    const r = run(CHECK_IDEMPOTENT, [doc, 'NaN']);
    expect(r.status).toBe(2);
  });

  it('[P1] prNumber with leading # rejected with exit 2', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    writeFileSync(doc, '# Doc\n');
    const r = run(CHECK_IDEMPOTENT, [doc, '#142']);
    expect(r.status).toBe(2);
  });

  it('[P2] PR-number prefix boundary: [#14] must NOT match prNumber 142', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    // All three conditions appear to hold EXCEPT PR number in completion is a
    // prefix of our target. The script's PR match MUST be boundary-anchored.
    writeFileSync(
      doc,
      [
        '# Feature FEAT-X',
        '',
        '## Acceptance Criteria',
        '- [x] Done',
        '',
        '## Completion',
        '',
        '**Status:** `Complete`',
        '',
        '**Completed:** 2026-04-22',
        '',
        '**Pull Request:** [#14](https://github.com/x/y/pull/14)',
        '',
      ].join('\n')
    );
    const r = run(CHECK_IDEMPOTENT, [doc, '142']);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('pr-line-mismatch');
  });

  it('[P2] PR-number exact match via /pull/N URL path', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    writeFileSync(
      doc,
      [
        '# Feature FEAT-X',
        '',
        '## Acceptance Criteria',
        '- [x] Done',
        '',
        '## Completion',
        '',
        '**Status:** `Complete`',
        '',
        '**Completed:** 2026-04-22',
        '',
        '**Pull Request:** see https://github.com/x/y/pull/142',
        '',
      ].join('\n')
    );
    const r = run(CHECK_IDEMPOTENT, [doc, '142']);
    expect(r.status).toBe(0);
  });
});

describe('Inputs — completion-upsert.sh', () => {
  it('[P1] prUrl containing backticks is written literally (no command execution)', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    writeFileSync(doc, '# Feature\n');
    const sentinel = join(dir, 'EVAL_SENTINEL');
    const evilUrl = `https://github.com/x/y/pull/1?q=\`touch ${sentinel}\``;
    const r = run(COMPLETION_UPSERT, [doc, '1', evilUrl]);
    expect(r.status).toBe(0);
    expect(existsSync(sentinel)).toBe(false);
    const body = readFileSync(doc, 'utf8');
    expect(body).toContain('`touch ');
    expect(body).toContain('[#1]');
  });

  it('[P1] non-ASCII content in existing Completion preserved byte-for-byte on upsert', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    const nonAscii = '# Feature with αβγ 🔧 عربى\n\n## Notes\n\nKeep: κάτι.\n';
    writeFileSync(doc, nonAscii, 'utf8');
    const r = run(COMPLETION_UPSERT, [doc, '42', 'https://github.com/x/y/pull/42']);
    expect(r.status).toBe(0);
    const after = readFileSync(doc, 'utf8');
    expect(after).toContain('αβγ');
    expect(after).toContain('🔧');
    expect(after).toContain('عربى');
    expect(after).toContain('κάτι');
  });
});

// ---------------------------------------------------------------------------
// STATE TRANSITIONS dimension
// ---------------------------------------------------------------------------

describe('State transitions — idempotency', () => {
  it('[P0] re-running completion-upsert on already-populated doc yields upserted (not a second append)', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    writeFileSync(doc, '# F\n');
    const first = run(COMPLETION_UPSERT, [doc, '1', 'https://github.com/x/y/pull/1']);
    expect(first.status).toBe(0);
    expect(first.stdout.trim()).toBe('appended');
    const second = run(COMPLETION_UPSERT, [doc, '1', 'https://github.com/x/y/pull/1']);
    expect(second.status).toBe(0);
    expect(second.stdout.trim()).toBe('upserted');
    const after = readFileSync(doc, 'utf8');
    // Exactly one `## Completion` heading — no duplication.
    const matches = after.match(/^## Completion$/gm);
    expect(matches?.length ?? 0).toBe(1);
  });

  it('[P0] reconcile-affected-files: idempotent annotation (no double "planned" suffix)', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    writeFileSync(
      doc,
      [
        '## Affected Files',
        '',
        '- `a.md` (planned but not modified)',
        '- `b.md`',
        '',
      ].join('\n')
    );
    // Stub gh via PATH
    const stubDir = join(dir, 'stub');
    const { mkdirSync } = require('node:fs');
    mkdirSync(stubDir, { recursive: true });
    writeFileSync(
      join(stubDir, 'gh'),
      `#!/usr/bin/env bash\n# Stub: only b.md is in the PR.\nif [[ "$*" == *"--json files"* ]]; then\n  echo "b.md"\nfi\nexit 0\n`
    );
    require('node:fs').chmodSync(join(stubDir, 'gh'), 0o755);
    const r = run(RECONCILE_AFFECTED, [doc, '42'], {
      PATH: `${stubDir}:${process.env.PATH}`,
    });
    expect(r.status).toBe(0);
    // Already annotated — should not re-annotate.
    const after = readFileSync(doc, 'utf8');
    const doubles = after.match(/\(planned but not modified\) \(planned but not modified\)/g);
    expect(doubles).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// ENVIRONMENT dimension
// ---------------------------------------------------------------------------

describe('Environment — locale and line-ending preservation', () => {
  it('[P1] LANG=C locale does not garble existing non-ASCII doc content', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    writeFileSync(doc, '# 🔧 Title\n\n## Notes\n\nπολύ.\n', 'utf8');
    const r = run(COMPLETION_UPSERT, [doc, '1', 'https://github.com/x/y/pull/1'], {
      LANG: 'C',
      LC_ALL: 'C',
    });
    expect(r.status).toBe(0);
    const after = readFileSync(doc, 'utf8');
    expect(after).toContain('🔧');
    expect(after).toContain('πολύ');
  });

  it('[P1] CRLF line endings preserved end-to-end across completion-upsert', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    // Author with CRLF throughout.
    writeFileSync(doc, '# Feature\r\n\r\n## Notes\r\n\r\nkeep\r\n', 'utf8');
    const r = run(COMPLETION_UPSERT, [doc, '1', 'https://github.com/x/y/pull/1']);
    expect(r.status).toBe(0);
    const after = readFileSync(doc, 'utf8');
    // Existing CRLF lines retained.
    expect(after).toMatch(/keep\r\n/);
  });
});

// ---------------------------------------------------------------------------
// DEPENDENCY FAILURE dimension
// ---------------------------------------------------------------------------

describe('Dependency failure — gh failure is non-fatal in reconcile-affected-files', () => {
  it('[P2] gh returning non-zero exits reconcile with exit 1 and [warn] prefix', () => {
    const dir = tmp();
    const doc = join(dir, 'doc.md');
    writeFileSync(doc, '## Affected Files\n\n- `a.md`\n', 'utf8');
    const stubDir = join(dir, 'stub');
    require('node:fs').mkdirSync(stubDir, { recursive: true });
    writeFileSync(
      join(stubDir, 'gh'),
      `#!/usr/bin/env bash\necho "gh: API unavailable" >&2\nexit 1\n`
    );
    require('node:fs').chmodSync(join(stubDir, 'gh'), 0o755);
    const r = run(RECONCILE_AFFECTED, [doc, '42'], {
      PATH: `${stubDir}:${process.env.PATH}`,
    });
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('[warn] reconcile-affected-files');
  });
});

// ---------------------------------------------------------------------------
// CROSS-CUTTING dimension
// ---------------------------------------------------------------------------

describe('Cross-cutting — finalize.sh trust boundary', () => {
  it('[P0] finalize.sh missing branch arg exits 2 with usage', () => {
    const r = run(FINALIZE, []);
    expect(r.status).toBe(2);
    expect(r.stderr).toContain('usage');
  });

  it('[P0] finalize.sh empty branch arg exits 2', () => {
    const r = run(FINALIZE, ['']);
    expect(r.status).toBe(2);
  });
});
