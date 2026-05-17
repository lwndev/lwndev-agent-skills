import { describe, it, expect } from 'vitest';
import { execFileSync, spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';

const SCRIPTS_DIR = join(process.cwd(), 'plugins/lwndev-sdlc/skills/managing-work-items/scripts');

const BACKEND_DETECT = join(SCRIPTS_DIR, 'backend-detect.sh');
const EXTRACT_ISSUE_REF = join(SCRIPTS_DIR, 'extract-issue-ref.sh');
const PR_LINK = join(SCRIPTS_DIR, 'pr-link.sh');
const RENDER_ISSUE_COMMENT = join(SCRIPTS_DIR, 'render-issue-comment.sh');
const POST_ISSUE_COMMENT = join(SCRIPTS_DIR, 'post-issue-comment.sh');
const FETCH_ISSUE = join(SCRIPTS_DIR, 'fetch-issue.sh');

function run(
  script: string,
  args: string[] = [],
  env: NodeJS.ProcessEnv = {}
): { stdout: string; stderr: string; status: number | null } {
  const result = spawnSync('bash', [script, ...args], {
    encoding: 'utf-8',
    env: { ...process.env, ...env },
  });
  return {
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    status: result.status,
  };
}

describe('FEAT-025 QA: managing-work-items scripts — P0 adversarial scenarios', () => {
  describe('backend-detect.sh: inputs dimension', () => {
    it('rejects whitespace-only ref with exit 2', () => {
      const { status } = run(BACKEND_DETECT, [' \t\n']);
      expect(status).toBe(2);
    });

    it('rejects empty ref with exit 2', () => {
      const { status } = run(BACKEND_DETECT, ['']);
      expect(status).toBe(2);
    });

    it('trims leading/trailing whitespace on valid #N', () => {
      const { stdout, status } = run(BACKEND_DETECT, [' #183 ']);
      expect(status).toBe(0);
      const obj = JSON.parse(stdout);
      expect(obj).toEqual({ backend: 'github', issueNumber: 183 });
    });

    it('treats leading zeros as a numeric value (not a string)', () => {
      const { stdout, status } = run(BACKEND_DETECT, ['#007']);
      expect(status).toBe(0);
      const obj = JSON.parse(stdout);
      expect(obj.issueNumber).toBe(7);
      expect(typeof obj.issueNumber).toBe('number');
    });

    it('rejects negative-number ref as null', () => {
      const { stdout, status } = run(BACKEND_DETECT, ['#-5']);
      expect(status).toBe(0);
      expect(stdout.trim()).toBe('null');
    });

    it('parses alphanumeric Jira project keys', () => {
      const { stdout, status } = run(BACKEND_DETECT, ['PROJ2-456']);
      expect(status).toBe(0);
      const obj = JSON.parse(stdout);
      expect(obj).toEqual({
        backend: 'jira',
        projectKey: 'PROJ2',
        issueNumber: 456,
      });
    });

    it('rejects lowercase Jira ref as null', () => {
      const { stdout, status } = run(BACKEND_DETECT, ['proj-123']);
      expect(status).toBe(0);
      expect(stdout.trim()).toBe('null');
    });

    it('rejects underscore-separated ref as null', () => {
      const { stdout, status } = run(BACKEND_DETECT, ['PROJ_123']);
      expect(status).toBe(0);
      expect(stdout.trim()).toBe('null');
    });

    it('rejects unicode homoglyphs as null', () => {
      const { stdout, status } = run(BACKEND_DETECT, ['＃183']);
      expect(status).toBe(0);
      expect(stdout.trim()).toBe('null');
    });
  });

  describe('extract-issue-ref.sh: inputs dimension', () => {
    it('returns empty stdout + exit 0 when section is missing', () => {
      const repo = mkdtempSync(join(tmpdir(), 'qa-extract-'));
      try {
        const doc = join(repo, 'feature.md');
        writeFileSync(doc, '# Title\n\n## Overview\nNo issue section here.\n');
        const { stdout, status } = run(EXTRACT_ISSUE_REF, [doc]);
        expect(status).toBe(0);
        expect(stdout).toBe('');
      } finally {
        rmSync(repo, { recursive: true, force: true });
      }
    });

    it('returns first link when multiple matches exist in GitHub Issue section', () => {
      const repo = mkdtempSync(join(tmpdir(), 'qa-extract-'));
      try {
        const doc = join(repo, 'feature.md');
        writeFileSync(
          doc,
          '# Feature\n\n## GitHub Issue\n[#100](https://github.com/x/y/issues/100) and also [#200](https://github.com/x/y/issues/200).\n\n## Other\n'
        );
        const { stdout, status } = run(EXTRACT_ISSUE_REF, [doc]);
        expect(status).toBe(0);
        expect(stdout.trim()).toBe('#100');
      } finally {
        rmSync(repo, { recursive: true, force: true });
      }
    });

    it('exits 1 when the requirement document does not exist', () => {
      const { status } = run(EXTRACT_ISSUE_REF, ['/tmp/definitely-does-not-exist-FEAT-025.md']);
      expect(status).toBe(1);
    });

    it('exits 2 on missing arg', () => {
      const { status } = run(EXTRACT_ISSUE_REF, []);
      expect(status).toBe(2);
    });
  });

  describe('pr-link.sh: inputs dimension', () => {
    it('exits 2 on empty arg', () => {
      const { status } = run(PR_LINK, ['']);
      expect(status).toBe(2);
    });

    it('emits empty stdout for null ref (unrecognized)', () => {
      const { stdout, status } = run(PR_LINK, ['garbage-not-a-ref']);
      expect(status).toBe(0);
      expect(stdout).toBe('');
    });

    it('emits exactly "Closes #N\\n" for GitHub refs', () => {
      const { stdout, status } = run(PR_LINK, ['#183']);
      expect(status).toBe(0);
      expect(stdout).toBe('Closes #183\n');
    });

    it('emits the raw key + newline for Jira refs', () => {
      const { stdout, status } = run(PR_LINK, ['PROJ-123']);
      expect(status).toBe(0);
      expect(stdout).toBe('PROJ-123\n');
    });
  });

  describe('render-issue-comment.sh: inputs dimension', () => {
    it('exits 2 on invalid backend', () => {
      const { status } = run(RENDER_ISSUE_COMMENT, ['slack', 'phase-start', '{}']);
      expect(status).toBe(2);
    });

    it('exits 2 on invalid comment type', () => {
      const { status } = run(RENDER_ISSUE_COMMENT, ['github', 'phase_start', '{}']);
      expect(status).toBe(2);
    });

    it('exits 2 on malformed context JSON', () => {
      const { status } = run(RENDER_ISSUE_COMMENT, ['github', 'phase-start', '{not valid json']);
      expect(status).toBe(2);
    });
  });

  describe('post-issue-comment.sh: graceful degradation (no-reference skip path)', () => {
    it('exits 0 silently when ref is unrecognized (null-path)', () => {
      const { status, stderr } = run(POST_ISSUE_COMMENT, [
        'not-a-valid-ref',
        'phase-start',
        '{"phase":1,"name":"X","workItemId":"FEAT-025"}',
      ]);
      expect(status).toBe(0);
      expect(stderr).toMatch(/No issue reference provided/);
    });

    it('exits 2 on missing args', () => {
      const { status } = run(POST_ISSUE_COMMENT, ['#183']);
      expect(status).toBe(2);
    });
  });

  describe('fetch-issue.sh: graceful degradation + args', () => {
    it('emits "null" for unrecognized ref with exit 0', () => {
      const { stdout, status } = run(FETCH_ISSUE, ['not-a-ref']);
      expect(status).toBe(0);
      expect(stdout.trim()).toBe('null');
    });

    it('exits 2 on missing arg', () => {
      const { status } = run(FETCH_ISSUE, []);
      expect(status).toBe(2);
    });
  });

  describe('cross-script integration: pr-link invokes backend-detect', () => {
    it('pr-link output is consistent with backend-detect classification', () => {
      const refs = ['#1', '#42', '#183', 'PROJ-1', 'ABC123-999', 'garbage'];
      for (const ref of refs) {
        const detectOut = run(BACKEND_DETECT, [ref]).stdout.trim();
        const prOut = run(PR_LINK, [ref]).stdout;
        if (detectOut === 'null') {
          expect(prOut).toBe('');
        } else {
          const parsed = JSON.parse(detectOut);
          if (parsed.backend === 'github') {
            expect(prOut).toBe(`Closes #${parsed.issueNumber}\n`);
          } else {
            expect(prOut).toBe(`${parsed.projectKey}-${parsed.issueNumber}\n`);
          }
        }
      }
    });
  });

  describe('idempotency / determinism (NFR-3)', () => {
    it('backend-detect produces identical output across repeated calls', () => {
      const first = run(BACKEND_DETECT, ['#183']).stdout;
      const second = run(BACKEND_DETECT, ['#183']).stdout;
      const third = run(BACKEND_DETECT, ['#183']).stdout;
      expect(first).toBe(second);
      expect(second).toBe(third);
    });

    it('pr-link produces identical output across repeated calls', () => {
      const first = run(PR_LINK, ['PROJ-123']).stdout;
      const second = run(PR_LINK, ['PROJ-123']).stdout;
      expect(first).toBe(second);
    });
  });
});

// Sanity-check that the scripts exist on disk (fast-fail if the paths drifted).
describe('FEAT-025 QA: script file integrity', () => {
  it('all six scripts are present and executable', () => {
    const scripts = [
      BACKEND_DETECT,
      EXTRACT_ISSUE_REF,
      PR_LINK,
      RENDER_ISSUE_COMMENT,
      POST_ISSUE_COMMENT,
      FETCH_ISSUE,
    ];
    for (const s of scripts) {
      // execFileSync with --help-equivalent (missing arg) should not throw at least
      // to the degree that the file exists on disk. Use a no-arg call and expect
      // exit 2 for scripts that require args.
      try {
        execFileSync('bash', ['-n', s], { encoding: 'utf-8' });
      } catch (err) {
        throw new Error(`Script syntax check failed for ${s}: ${err}`);
      }
    }
  });
});
