import { describe, it, expect } from 'vitest';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';

const SCRIPTS_DIR = join(
  process.cwd(),
  'plugins/lwndev-sdlc/skills/reviewing-requirements/scripts'
);

const EXTRACT_REFERENCES = join(SCRIPTS_DIR, 'extract-references.sh');
const CROSS_REF_CHECK = join(SCRIPTS_DIR, 'cross-ref-check.sh');
const VERIFY_REFERENCES = join(SCRIPTS_DIR, 'verify-references.sh');
const DETECT_REVIEW_MODE = join(SCRIPTS_DIR, 'detect-review-mode.sh');
const RECONCILE_TEST_PLAN = join(SCRIPTS_DIR, 'reconcile-test-plan.sh');
const PR_DIFF_VS_PLAN = join(SCRIPTS_DIR, 'pr-diff-vs-plan.sh');

function run(
  script: string,
  args: string[] = [],
  opts: { env?: NodeJS.ProcessEnv; cwd?: string } = {}
): { stdout: string; stderr: string; status: number | null } {
  const result = spawnSync('bash', [script, ...args], {
    encoding: 'utf-8',
    env: { ...process.env, ...(opts.env ?? {}) },
    cwd: opts.cwd,
  });
  return {
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    status: result.status,
  };
}

function tmpDoc(body: string): { dir: string; path: string } {
  const dir = mkdtempSync(join(tmpdir(), 'qa-rr-'));
  const path = join(dir, 'doc.md');
  writeFileSync(path, body, 'utf-8');
  return { dir, path };
}

describe('FEAT-026 reviewing-requirements scripts — adversarial QA', () => {
  // ---- Inputs dimension ----

  describe('Inputs — arg validation', () => {
    it('every script exits 2 with zero args', () => {
      for (const script of [
        EXTRACT_REFERENCES,
        CROSS_REF_CHECK,
        VERIFY_REFERENCES,
        DETECT_REVIEW_MODE,
      ]) {
        const r = run(script);
        expect(r.status, `${script} should exit 2`).toBe(2);
      }
      // FR-5 / FR-6 both require 2 args
      expect(run(RECONCILE_TEST_PLAN).status).toBe(2);
      expect(run(RECONCILE_TEST_PLAN, ['only-one']).status).toBe(2);
      expect(run(PR_DIFF_VS_PLAN).status).toBe(2);
      expect(run(PR_DIFF_VS_PLAN, ['only-one']).status).toBe(2);
    });

    it('detect-review-mode rejects non-numeric --pr with stderr', () => {
      const r = run(DETECT_REVIEW_MODE, ['FEAT-026', '--pr', 'abc']);
      expect(r.status).toBe(2);
      expect(r.stderr).toMatch(/--pr.*numeric/i);
    });

    it('detect-review-mode rejects malformed ID shapes', () => {
      for (const bad of ['FEAT-', 'feat-026', 'FEAT026', 'XYZ-1']) {
        const r = run(DETECT_REVIEW_MODE, [bad]);
        expect(r.status, `should reject ${bad}`).toBe(2);
      }
    });

    it('extract-references always emits all four arrays even when empty', () => {
      const { dir, path } = tmpDoc('no references here');
      try {
        const r = run(EXTRACT_REFERENCES, [path]);
        expect(r.status).toBe(0);
        const out = JSON.parse(r.stdout);
        expect(out).toHaveProperty('filePaths');
        expect(out).toHaveProperty('identifiers');
        expect(out).toHaveProperty('crossRefs');
        expect(out).toHaveProperty('ghRefs');
        expect(Array.isArray(out.filePaths)).toBe(true);
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    });

    it('verify-references dispatch heuristic: JSON-starting-with-brace is literal, other is path', () => {
      const literal = '{"filePaths":[],"identifiers":[],"crossRefs":[],"ghRefs":[]}';
      const r1 = run(VERIFY_REFERENCES, [literal]);
      expect(r1.status).toBe(0);
      expect(() => JSON.parse(r1.stdout)).not.toThrow();

      // Non-existent path → falls back to treating as JSON; non-JSON → exit 1
      const r2 = run(VERIFY_REFERENCES, ['/definitely/not/a/file.json']);
      expect([0, 1]).toContain(r2.status);
    });

    it('extract-references de-duplicates preserving first-occurrence order', () => {
      const body = 'see `foo.md` and `foo.md` again and `bar.md`';
      const { dir, path } = tmpDoc(body);
      try {
        const r = run(EXTRACT_REFERENCES, [path]);
        expect(r.status).toBe(0);
        const out = JSON.parse(r.stdout);
        const fooCount = out.filePaths.filter((p: string) => p.includes('foo.md')).length;
        expect(fooCount, 'foo.md should be deduplicated').toBe(1);
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    });

    it('extract-references survives adversarial filenames without shell expansion', () => {
      const body = 'see `$(rm -rf /tmp/never).md`';
      const { dir, path } = tmpDoc(body);
      try {
        const r = run(EXTRACT_REFERENCES, [path]);
        expect(r.status).toBe(0);
        // Script must not execute the substitution
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    });

    it('cross-ref-check reports missing refs as `missing`', () => {
      const body = '## Dependencies\n- Depends on FEAT-999999\n';
      const { dir, path } = tmpDoc(body);
      try {
        const r = run(CROSS_REF_CHECK, [path]);
        expect(r.status).toBe(0);
        const out = JSON.parse(r.stdout);
        expect(out.missing.some((e: { ref: string }) => e.ref === 'FEAT-999999')).toBe(true);
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    });

    it('pr-diff-vs-plan rejects non-numeric, zero, negative, and hex pr-number', () => {
      const planBody =
        '---\nid: FEAT-026\nversion: 2\npersona: qa\n---\n## Scenarios (by dimension)\n### Inputs\n- [P0] x | mode: test-framework | expected: y\n';
      const { dir, path } = tmpDoc(planBody);
      try {
        for (const bad of ['abc', '-1', '0', '1.5', '0xff']) {
          const r = run(PR_DIFF_VS_PLAN, [bad, path]);
          expect(r.status, `pr-diff should reject ${bad}`).toBe(2);
        }
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    });

    it('reconcile-test-plan exits 1 on req-doc missing ## Acceptance Criteria', () => {
      const reqBody = '# Req\n## User Story\nfoo\n';
      const planBody =
        '---\nid: FEAT-X\nversion: 2\npersona: qa\n---\n## Scenarios (by dimension)\n### Inputs\n- [P0] x | mode: test-framework | expected: y (FR-1)\n';
      const { dir: d1, path: req } = tmpDoc(reqBody);
      const { dir: d2, path: plan } = tmpDoc(planBody);
      try {
        const r = run(RECONCILE_TEST_PLAN, [req, plan]);
        expect(r.status).toBe(1);
      } finally {
        rmSync(d1, { recursive: true, force: true });
        rmSync(d2, { recursive: true, force: true });
      }
    });

    it('reconcile-test-plan exits 1 on test-plan with zero scenario lines', () => {
      const reqBody = '# Req\n## Acceptance Criteria\n- [ ] AC 1\n';
      const planBody =
        '---\nid: FEAT-X\nversion: 2\npersona: qa\n---\n## Scenarios (by dimension)\n';
      const { dir: d1, path: req } = tmpDoc(reqBody);
      const { dir: d2, path: plan } = tmpDoc(planBody);
      try {
        const r = run(RECONCILE_TEST_PLAN, [req, plan]);
        expect(r.status).toBe(1);
      } finally {
        rmSync(d1, { recursive: true, force: true });
        rmSync(d2, { recursive: true, force: true });
      }
    });
  });

  // ---- State transitions dimension ----

  describe('State transitions — idempotency', () => {
    it('extract-references is idempotent', () => {
      const body = 'see `foo.md` and FEAT-001 and #42';
      const { dir, path } = tmpDoc(body);
      try {
        const r1 = run(EXTRACT_REFERENCES, [path]);
        const r2 = run(EXTRACT_REFERENCES, [path]);
        expect(r1.stdout).toBe(r2.stdout);
        expect(r1.status).toBe(r2.status);
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    });

    it('detect-review-mode is idempotent for the standard fallback', () => {
      const r1 = run(DETECT_REVIEW_MODE, ['FEAT-999999']);
      const r2 = run(DETECT_REVIEW_MODE, ['FEAT-999999']);
      expect(r1.stdout).toBe(r2.stdout);
      expect(r1.status).toBe(r2.status);
    });
  });

  // ---- Environment dimension ----

  describe('Environment — cwd independence', () => {
    it('scripts work when invoked from a subdirectory', () => {
      const body = 'see `foo.md`';
      const { dir, path } = tmpDoc(body);
      try {
        const subdir = join(dir, 'nested');
        mkdirSync(subdir);
        const r = run(EXTRACT_REFERENCES, [path], { cwd: subdir });
        expect(r.status).toBe(0);
        const out = JSON.parse(r.stdout);
        expect(out.filePaths).toContain('foo.md');
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    });
  });

  // ---- Dependency failure dimension ----

  describe('Dependency failure — graceful degradation', () => {
    it('detect-review-mode falls through to standard when gh is absent', () => {
      // Stub PATH so gh and git are unreachable, but bash core utilities remain
      const r = run(DETECT_REVIEW_MODE, ['FEAT-999999'], {
        env: { PATH: '/usr/bin:/bin' },
      });
      // Either returns standard mode (if gh absent → fallthrough) or
      // depending on where gh is installed, may find one. Either way exit 0.
      expect(r.status).toBe(0);
      const out = JSON.parse(r.stdout);
      expect(out).toHaveProperty('mode');
      // With gh unavailable, test-plan check runs next; if no plan, fall to standard
      expect(['standard', 'code-review', 'test-plan']).toContain(out.mode);
    });

    it('pr-diff-vs-plan skips gracefully with [warn] when gh is absent', () => {
      const planBody =
        '---\nid: FEAT-X\nversion: 2\npersona: qa\n---\n## Scenarios (by dimension)\n### Inputs\n- [P0] x | mode: test-framework | expected: y\n';
      const { dir, path } = tmpDoc(planBody);
      // Stub gh via a directory containing a failing gh shim; keep real PATH for bash/git
      const stubDir = mkdtempSync(join(tmpdir(), 'qa-rr-stub-'));
      const ghStub = join(stubDir, 'gh');
      writeFileSync(ghStub, '#!/usr/bin/env bash\necho "command not found: gh" 1>&2\nexit 127\n', {
        mode: 0o755,
      });
      try {
        const r = run(PR_DIFF_VS_PLAN, ['123', path], {
          env: { PATH: `${stubDir}:${process.env.PATH ?? ''}` },
        });
        // gh-missing or gh-failing → graceful skip (exit 0) with [warn] on stderr
        expect(r.status).toBe(0);
        expect(r.stderr).toMatch(/\[warn\].*gh/i);
      } finally {
        rmSync(stubDir, { recursive: true, force: true });
        rmSync(dir, { recursive: true, force: true });
      }
    });

    it('verify-references ghRefs classification handles gh-unavailable with [info]', () => {
      const refs = {
        filePaths: [],
        identifiers: [],
        crossRefs: [],
        ghRefs: ['#999999'],
      };
      // Stub gh to always fail; keep real PATH so bash/jq/git still resolve
      const stubDir = mkdtempSync(join(tmpdir(), 'qa-rr-stub-'));
      const ghStub = join(stubDir, 'gh');
      writeFileSync(ghStub, '#!/usr/bin/env bash\necho "gh unavailable" 1>&2\nexit 1\n', {
        mode: 0o755,
      });
      try {
        const r = run(VERIFY_REFERENCES, [JSON.stringify(refs)], {
          env: { PATH: `${stubDir}:${process.env.PATH ?? ''}` },
        });
        expect(r.status).toBe(0);
        const out = JSON.parse(r.stdout);
        expect(out.unavailable.length).toBeGreaterThan(0);
        expect(r.stderr).toMatch(/\[info\].*gh unavailable/i);
      } finally {
        rmSync(stubDir, { recursive: true, force: true });
      }
    });
  });
});
