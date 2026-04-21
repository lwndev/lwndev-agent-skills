import { describe, it, expect } from 'vitest';
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  readFileSync,
  rmSync,
  chmodSync,
  existsSync,
  symlinkSync,
} from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync, spawn } from 'node:child_process';

// ---------------------------------------------------------------------------
// FEAT-020 adversarial QA — independent from the authoring bats fixtures.
// Probes failure modes the authoring subagent likely did not cover:
//   * CRLF round-trip preservation in checkbox-flip-all.sh (the bats tolerance
//     case does not assert round-trip)
//   * Fence-awareness under language-tagged and nested-tilde fences
//   * Literal-substring guard for `AC-1.2` vs `AC-142` in check-acceptance.sh
//   * next-id.sh concurrent-invocation race
//   * Shell-metacharacter safety in create-pr.sh body substitution
//   * pr-body.tmpl missing at runtime
//   * CWD-sensitivity for scripts that glob relative to pwd
//   * ${BASH_SOURCE%/*} sibling-script resolution under symlinked scripts/
//   * jq-absent fallback emits parseable JSON (branch-id-parse.sh)
//   * Non-default locale lowercase behaviour (slugify.sh)
// ---------------------------------------------------------------------------

const REPO_ROOT = process.cwd();
const SCRIPTS = join(REPO_ROOT, 'plugins/lwndev-sdlc/scripts');

const SH = {
  nextId: join(SCRIPTS, 'next-id.sh'),
  slugify: join(SCRIPTS, 'slugify.sh'),
  resolveDoc: join(SCRIPTS, 'resolve-requirement-doc.sh'),
  buildBranch: join(SCRIPTS, 'build-branch-name.sh'),
  ensureBranch: join(SCRIPTS, 'ensure-branch.sh'),
  checkAc: join(SCRIPTS, 'check-acceptance.sh'),
  flipAll: join(SCRIPTS, 'checkbox-flip-all.sh'),
  commitWork: join(SCRIPTS, 'commit-work.sh'),
  createPr: join(SCRIPTS, 'create-pr.sh'),
  branchParse: join(SCRIPTS, 'branch-id-parse.sh'),
};

function runBash(
  script: string,
  args: string[] = [],
  opts: { cwd?: string; env?: NodeJS.ProcessEnv; input?: string } = {}
) {
  return spawnSync('bash', [script, ...args], {
    cwd: opts.cwd ?? REPO_ROOT,
    env: opts.env ?? process.env,
    input: opts.input,
    encoding: 'utf8',
  });
}

function makeTmp(): string {
  return mkdtempSync(join(tmpdir(), 'qa-feat-020-'));
}

// ---------- Inputs dimension ----------

describe('[QA FEAT-020] Inputs: slugify adversarial edge cases', () => {
  it('exits 1 on emoji-only title (nothing survives ASCII strip)', () => {
    const res = runBash(SH.slugify, ['🎉🎉🎉']);
    expect(res.status).toBe(1);
    expect(res.stderr).toMatch(/error:/i);
  });

  it('handles extremely long title by truncating to four tokens', () => {
    const long = Array.from({ length: 500 }, (_, i) => `word${i}`).join(' ');
    const res = runBash(SH.slugify, [long]);
    expect(res.status).toBe(0);
    const slug = res.stdout;
    expect(slug.split('-').length).toBe(4);
  });

  it('is deterministic: two runs return byte-identical output', () => {
    const a = runBash(SH.slugify, ['The Quick Brown Fox Jumps']);
    const b = runBash(SH.slugify, ['The Quick Brown Fox Jumps']);
    expect(a.status).toBe(0);
    expect(a.stdout).toBe(b.stdout);
    expect(a.stdout.trim()).toBe('quick-brown-fox-jumps');
  });
});

describe('[QA FEAT-020] Inputs: check-acceptance.sh literal-substring matching', () => {
  it('treats `.` as a literal dot, not regex wildcard', () => {
    const tmp = makeTmp();
    const doc = join(tmp, 'ac.md');
    try {
      writeFileSync(
        doc,
        [
          '## Acceptance Criteria',
          '',
          '- [ ] AC-142 some criterion',
          '- [ ] AC-1.2 some other criterion',
          '',
        ].join('\n')
      );
      const res = runBash(SH.checkAc, [doc, 'AC-1.2']);
      expect(res.status).toBe(0);
      const after = readFileSync(doc, 'utf8');
      expect(after).toMatch(/- \[ \] AC-142 some criterion/);
      expect(after).toMatch(/- \[x\] AC-1\.2 some other criterion/);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  it('rejects regex metachars being interpreted (brackets, parens)', () => {
    const tmp = makeTmp();
    const doc = join(tmp, 'ac.md');
    try {
      writeFileSync(doc, '## A\n\n- [ ] AC-1[a] thing\n- [ ] AC-1a thing\n');
      const res = runBash(SH.checkAc, [doc, 'AC-1[a]']);
      expect(res.status).toBe(0);
      const after = readFileSync(doc, 'utf8');
      expect(after).toMatch(/- \[x\] AC-1\[a\] thing/);
      expect(after).toMatch(/- \[ \] AC-1a thing/);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe('[QA FEAT-020] Inputs: fence-awareness with language-tagged and tilde fences', () => {
  it('does not flip boxes inside ```markdown fenced blocks', () => {
    const tmp = makeTmp();
    const doc = join(tmp, 'ac.md');
    try {
      writeFileSync(
        doc,
        [
          '## Acceptance Criteria',
          '',
          '```markdown',
          '- [ ] CRIT-inside example',
          '```',
          '',
          '- [ ] CRIT-outside real',
          '',
        ].join('\n')
      );
      const res = runBash(SH.flipAll, [doc, 'Acceptance Criteria']);
      expect(res.status).toBe(0);
      expect(res.stdout).toMatch(/checked 1 lines/);
      const after = readFileSync(doc, 'utf8');
      expect(after).toMatch(/- \[ \] CRIT-inside example/);
      expect(after).toMatch(/- \[x\] CRIT-outside real/);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  it('does not flip boxes inside ~~~ tilde fences', () => {
    const tmp = makeTmp();
    const doc = join(tmp, 'ac.md');
    try {
      writeFileSync(
        doc,
        [
          '## Acceptance Criteria',
          '',
          '~~~',
          '- [ ] CRIT-tilde-inside',
          '~~~',
          '- [ ] CRIT-tilde-outside',
        ].join('\n')
      );
      const res = runBash(SH.flipAll, [doc, 'Acceptance Criteria']);
      expect(res.status).toBe(0);
      expect(res.stdout).toMatch(/checked 1 lines/);
      const after = readFileSync(doc, 'utf8');
      expect(after).toMatch(/- \[ \] CRIT-tilde-inside/);
      expect(after).toMatch(/- \[x\] CRIT-tilde-outside/);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

// ---------- State transitions dimension ----------

describe('[QA FEAT-020] State transitions: idempotency', () => {
  it('check-acceptance.sh is byte-idempotent on already-checked lines', () => {
    const tmp = makeTmp();
    const doc = join(tmp, 'ac.md');
    try {
      writeFileSync(doc, '## A\n\n- [ ] AC-1 thing\n');
      runBash(SH.checkAc, [doc, 'AC-1']);
      const first = readFileSync(doc, 'utf8');
      const second = runBash(SH.checkAc, [doc, 'AC-1']);
      expect(second.status).toBe(0);
      expect(second.stdout.trim()).toBe('already checked');
      expect(readFileSync(doc, 'utf8')).toBe(first);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  it('checkbox-flip-all.sh reports `checked 0 lines` on second run', () => {
    const tmp = makeTmp();
    const doc = join(tmp, 'ac.md');
    try {
      writeFileSync(doc, '## A\n\n- [ ] one\n- [ ] two\n');
      runBash(SH.flipAll, [doc, 'A']);
      const afterFirst = readFileSync(doc, 'utf8');
      const second = runBash(SH.flipAll, [doc, 'A']);
      expect(second.status).toBe(0);
      expect(second.stdout.trim()).toBe('checked 0 lines');
      expect(readFileSync(doc, 'utf8')).toBe(afterFirst);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe('[QA FEAT-020] State transitions: next-id.sh concurrent invocation', () => {
  it('concurrent invocations all return the same next ID when state is unchanged', async () => {
    const tmp = makeTmp();
    const reqDir = join(tmp, 'requirements/features');
    mkdirSync(reqDir, { recursive: true });
    for (let i = 1; i <= 5; i++) {
      writeFileSync(join(reqDir, `FEAT-00${i}-foo.md`), '');
    }
    try {
      const runs = await Promise.all(
        Array.from(
          { length: 6 },
          () =>
            new Promise<string>((resolve, reject) => {
              const proc = spawn('bash', [SH.nextId, 'FEAT'], { cwd: tmp });
              let out = '';
              proc.stdout.on('data', (c) => {
                out += c.toString();
              });
              proc.on('close', (code) =>
                code === 0 ? resolve(out.trim()) : reject(new Error(`rc=${code}`))
              );
            })
        )
      );
      const unique = new Set(runs);
      expect(unique.size).toBe(1);
      expect(runs[0]).toBe('006');
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

// ---------- Environment dimension ----------

describe('[QA FEAT-020] Environment: CRLF round-trip preservation', () => {
  it('check-acceptance.sh preserves CRLF line endings on write', () => {
    const tmp = makeTmp();
    const doc = join(tmp, 'ac.md');
    try {
      const content = '## A\r\n\r\n- [ ] AC-1 item\r\n';
      writeFileSync(doc, content);
      const res = runBash(SH.checkAc, [doc, 'AC-1']);
      expect(res.status).toBe(0);
      const after = readFileSync(doc, 'utf8');
      expect(after).toContain('\r\n');
      expect(after).toMatch(/- \[x\] AC-1 item\r\n/);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  it('checkbox-flip-all.sh preserves CRLF line endings on write', () => {
    const tmp = makeTmp();
    const doc = join(tmp, 'ac.md');
    try {
      const content = '## A\r\n\r\n- [ ] one\r\n- [ ] two\r\n';
      writeFileSync(doc, content);
      const res = runBash(SH.flipAll, [doc, 'A']);
      expect(res.status).toBe(0);
      const after = readFileSync(doc, 'utf8');
      expect(after).toContain('\r\n');
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe('[QA FEAT-020] Environment: CWD sensitivity of glob-based scripts', () => {
  it('next-id.sh returns 001 when run from a directory with no requirements/ tree', () => {
    const tmp = makeTmp();
    try {
      const res = runBash(SH.nextId, ['FEAT'], { cwd: tmp });
      expect(res.status).toBe(0);
      expect(res.stdout.trim()).toBe('001');
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  it('resolve-requirement-doc.sh exits 1 with a clean "no file matches" when CWD has no matching file', () => {
    const tmp = makeTmp();
    try {
      const res = runBash(SH.resolveDoc, ['FEAT-999'], { cwd: tmp });
      expect(res.status).toBe(1);
      expect(res.stderr).toMatch(/no file matches/i);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe('[QA FEAT-020] Environment: jq-absent fallback for branch-id-parse.sh', () => {
  it('emits parseable JSON when jq is absent from PATH', () => {
    const tmp = makeTmp();
    try {
      const env = { ...process.env, PATH: `${tmp}:/usr/bin:/bin` };
      const res = runBash(SH.branchParse, ['feat/FEAT-042-scaffold-thing'], { env });
      expect(res.status).toBe(0);
      const parsed = JSON.parse(res.stdout);
      expect(parsed.id).toBe('FEAT-042');
      expect(parsed.type).toBe('feature');
      expect(parsed.dir).toBe('requirements/features');
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe('[QA FEAT-020] Environment: non-default locale does not break slugify', () => {
  it("slugify.sh preserves ASCII 'I' → 'i' under LC_ALL=tr_TR.UTF-8", () => {
    const env = { ...process.env, LC_ALL: 'tr_TR.UTF-8' };
    const res = runBash(SH.slugify, ['IMPORTANT Thing'], { env });
    expect(res.status).toBe(0);
    expect(res.stdout.trim()).toBe('important-thing');
  });
});

// ---------- Dependency failure dimension ----------

describe('[QA FEAT-020] Dependency failure: create-pr.sh error paths with PATH-shadowed git/gh', () => {
  it('exits 1 with pr-body.tmpl missing at runtime', () => {
    const tmp = makeTmp();
    try {
      const scriptsCopy = join(tmp, 'scripts');
      mkdirSync(scriptsCopy, { recursive: true });
      const src = readFileSync(SH.createPr, 'utf8');
      const createPrCopy = join(scriptsCopy, 'create-pr.sh');
      writeFileSync(createPrCopy, src);
      chmodSync(createPrCopy, 0o755);
      mkdirSync(join(scriptsCopy, 'assets'), { recursive: true });

      const gitStub = join(tmp, 'git');
      writeFileSync(
        gitStub,
        '#!/usr/bin/env bash\ncase "$1" in\n  rev-parse) echo "feat/FEAT-001-foo"; exit 0 ;;\n  push) exit 0 ;;\nesac\nexit 0\n'
      );
      chmodSync(gitStub, 0o755);
      const ghStub = join(tmp, 'gh');
      writeFileSync(ghStub, '#!/usr/bin/env bash\necho "https://example/pull/1"; exit 0\n');
      chmodSync(ghStub, 0o755);
      const env = { ...process.env, PATH: `${tmp}:${process.env.PATH}` };

      const res = runBash(createPrCopy, ['feat', 'FEAT-001', 'sample summary'], { env });
      expect(res.status).not.toBe(0);
      expect(res.stderr + res.stdout).toMatch(/pr-body\.tmpl|template/i);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  it('git push failure exits 1 without invoking gh pr create', () => {
    const tmp = makeTmp();
    try {
      const gitStub = join(tmp, 'git');
      writeFileSync(
        gitStub,
        '#!/usr/bin/env bash\ncase "$1" in\n  rev-parse) echo "feat/FEAT-001-foo"; exit 0 ;;\n  push) echo "error: push failed" >&2; exit 1 ;;\nesac\nexit 0\n'
      );
      chmodSync(gitStub, 0o755);
      const ghSentinel = join(tmp, 'gh-sentinel');
      const ghStub = join(tmp, 'gh');
      writeFileSync(
        ghStub,
        `#!/usr/bin/env bash\ntouch "${ghSentinel}"\necho "https://example/pull/1"\nexit 0\n`
      );
      chmodSync(ghStub, 0o755);
      const env = { ...process.env, PATH: `${tmp}:${process.env.PATH}` };
      const res = runBash(SH.createPr, ['feat', 'FEAT-001', 'summary'], { env });
      expect(res.status).toBe(1);
      expect(existsSync(ghSentinel)).toBe(false);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe('[QA FEAT-020] Dependency failure: commit-work.sh with nothing staged', () => {
  it('exits non-zero and passes git error through', () => {
    const tmp = makeTmp();
    try {
      const r = spawnSync('git', ['init', '-q', '-b', 'main', tmp], { encoding: 'utf8' });
      expect(r.status).toBe(0);
      spawnSync('git', ['-C', tmp, 'config', 'user.email', 'qa@example.com'], { encoding: 'utf8' });
      spawnSync('git', ['-C', tmp, 'config', 'user.name', 'QA'], { encoding: 'utf8' });
      writeFileSync(join(tmp, 'seed.txt'), 'seed');
      spawnSync('git', ['-C', tmp, 'add', 'seed.txt'], { encoding: 'utf8' });
      spawnSync('git', ['-C', tmp, 'commit', '-q', '-m', 'seed'], { encoding: 'utf8' });

      const res = runBash(SH.commitWork, ['chore', 'qa', 'empty commit attempt'], { cwd: tmp });
      expect(res.status).toBe(1);
      expect(res.stderr + res.stdout).toMatch(/nothing to commit|no changes added/i);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

// ---------- Cross-cutting dimension ----------

describe('[QA FEAT-020] Cross-cutting: shell-metacharacter safety in create-pr.sh body', () => {
  it('handles backticks, $-substitution, and `&` in summary without corruption', () => {
    const tmp = makeTmp();
    try {
      const capturedBody = join(tmp, 'gh-body.txt');
      const gitStub = join(tmp, 'git');
      writeFileSync(
        gitStub,
        '#!/usr/bin/env bash\ncase "$1" in\n  rev-parse) echo "feat/FEAT-001-foo"; exit 0 ;;\n  push) exit 0 ;;\nesac\nexit 0\n'
      );
      chmodSync(gitStub, 0o755);
      const ghStub = join(tmp, 'gh');
      writeFileSync(
        ghStub,
        `#!/usr/bin/env bash\nwhile [[ $# -gt 0 ]]; do\n  case "$1" in\n    --body) shift; printf '%s' "$1" > "${capturedBody}"; shift ;;\n    *) shift ;;\n  esac\ndone\necho "https://example/pull/1"\nexit 0\n`
      );
      chmodSync(ghStub, 0o755);
      const env = { ...process.env, PATH: `${tmp}:${process.env.PATH}` };

      const adversarial = 'summary with `backtick` & $(echo EXECUTED) & ampersand';
      const res = runBash(SH.createPr, ['feat', 'FEAT-001', adversarial], { env });
      expect(res.status).toBe(0);
      const body = readFileSync(capturedBody, 'utf8');
      expect(body).toContain('`backtick`');
      expect(body).toContain('$(echo EXECUTED)');
      expect(body).toContain('& ampersand');
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe('[QA FEAT-020] Cross-cutting: ${BASH_SOURCE%/*} sibling resolution under symlink', () => {
  it('build-branch-name.sh finds slugify.sh when scripts/ is reached via symlink', () => {
    const tmp = makeTmp();
    try {
      const linkDir = join(tmp, 'alias');
      symlinkSync(SCRIPTS, linkDir);
      const linkedBuild = join(linkDir, 'build-branch-name.sh');
      const res = runBash(linkedBuild, ['feat', 'FEAT-001', 'sample title here']);
      expect(res.status).toBe(0);
      expect(res.stdout.trim()).toBe('feat/FEAT-001-sample-title-here');
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});
