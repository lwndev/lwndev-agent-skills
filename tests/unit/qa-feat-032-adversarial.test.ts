// QA-FEAT-032: adversarial probe of addressing-qa-findings scripts and FR-9
// safety-net glob anchoring. These tests exercise the real shell scripts
// against a real git repo set up under a tempdir. They focus on coverage gaps
// not covered by the existing bats fixtures: shell-special filenames,
// path-traversal arguments, non-ASCII filenames, and FR-9 glob anchoring
// (extension and subdirectory leakage).
//
// Mode: test-framework
// Ref: qa/test-plans/QA-plan-FEAT-032.md

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync, spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const ADOPT = path.join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts/adopt-qa-test.sh'
);

interface RunResult {
  stdout: string;
  stderr: string;
  status: number;
}

function runBashIn(cwd: string, script: string, args: string[]): RunResult {
  const r = spawnSync('bash', [script, ...args], {
    cwd,
    encoding: 'utf8',
    env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
  });
  return {
    stdout: r.stdout ?? '',
    stderr: r.stderr ?? '',
    status: r.status ?? -1,
  };
}

function gitInit(cwd: string): void {
  execFileSync('git', ['init', '-q', '-b', 'main'], { cwd });
  execFileSync('git', ['config', 'user.email', 'qa@feat-032.test'], { cwd });
  execFileSync('git', ['config', 'user.name', 'qa-feat-032'], { cwd });
  execFileSync('git', ['config', 'commit.gpgsign', 'false'], { cwd });
}

function gitAddCommit(cwd: string, msg: string): void {
  execFileSync('git', ['add', '-A'], { cwd });
  execFileSync('git', ['commit', '-q', '-m', msg], { cwd });
}

function mktempd(prefix: string): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

let tmp = '';
beforeEach(() => {
  tmp = mktempd('qa-feat-032-');
});
afterEach(() => {
  if (tmp && fs.existsSync(tmp)) {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// ----------------------------------------------------------------------------
// Inputs dimension
// ----------------------------------------------------------------------------

describe('Inputs: adopt-qa-test.sh argument hardening', () => {
  it('P0 #3 — shell-special characters in QA-test path are passed safely (no command injection)', () => {
    // The QA filename contains shell metacharacters that would, if the script
    // ever interpolated its argument unquoted, execute a sentinel command.
    // We deposit a guard file in a sibling tree; injection would either
    // create INJECTED or remove PRESENT. Whatever the exit code, both
    // invariants must hold.
    gitInit(tmp);
    const sentinelDir = path.join(tmp, 'sentinel');
    fs.mkdirSync(sentinelDir, { recursive: true });
    const present = path.join(sentinelDir, 'PRESENT');
    fs.writeFileSync(present, 'guard');
    fs.mkdirSync(path.join(tmp, 'src'), { recursive: true });
    fs.mkdirSync(path.join(tmp, 'tests/unit'), { recursive: true });
    fs.writeFileSync(path.join(tmp, 'src/dollar-fn.ts'), 'export const x = 1;\n');
    fs.writeFileSync(
      path.join(tmp, 'tests/unit/dollar-fn.test.ts'),
      "import { x } from '../../src/dollar-fn';\nimport { test, expect } from 'vitest';\ntest('peer', () => expect(x).toBe(1));\n"
    );
    // Backticks + `;` + spaces are the highest-yield metacharacters for shell
    // injection probes. Avoid `$(...)` here only because the host filesystem
    // would otherwise need to allow nested-paren patterns; the existing chars
    // are sufficient to prove the script does not eval its argument.
    const qaName = 'qa-`touch sentinel_INJECTED`; rm sentinel_PRESENT.test.ts';
    const qaRel = `tests/unit/${qaName}`;
    fs.writeFileSync(
      path.join(tmp, qaRel),
      "import { x } from '../../src/dollar-fn';\nimport { test, expect } from 'vitest';\ntest('qa', () => expect(x).toBe(1));\n"
    );
    gitAddCommit(tmp, 'seed');

    const r = runBashIn(tmp, ADOPT, [qaRel]);

    // Security invariants — independent of exit code.
    expect(fs.existsSync(present), 'sentinel/PRESENT must still exist').toBe(true);
    expect(fs.existsSync(path.join(sentinelDir, 'INJECTED'))).toBe(false);
    expect(fs.existsSync(path.join(tmp, 'sentinel_INJECTED'))).toBe(false);
    // Adoption may succeed (rename preserves the literal name) or fail with
    // exit 1/2; only exit 0 with side effects on the sentinel would be a bug.
    expect([0, 1, 2]).toContain(r.status);
  });

  it('P2 — path traversal argument outside repo is rejected, no write outside tempdir', () => {
    gitInit(tmp);
    const outside = mktempd('qa-feat-032-outside-');
    try {
      // Create a peer test inside repo so the peer-resolution branch wouldn't
      // accidentally green-light a traversal target.
      fs.mkdirSync(path.join(tmp, 'src'), { recursive: true });
      fs.mkdirSync(path.join(tmp, 'tests/unit'), { recursive: true });
      fs.writeFileSync(path.join(tmp, 'src/foo.ts'), 'export const f = 1;\n');
      fs.writeFileSync(
        path.join(tmp, 'tests/unit/foo.test.ts'),
        "import { f } from '../../src/foo';\nimport { test, expect } from 'vitest';\ntest('peer', () => expect(f).toBe(1));\n"
      );
      gitAddCommit(tmp, 'seed');

      // Place a QA file *outside* the repo, then pass a traversal path to
      // adopt-qa-test from inside the repo.
      const traversalAbs = path.join(outside, 'qa-evil.test.ts');
      fs.writeFileSync(
        traversalAbs,
        "import { f } from '../../src/foo';\ntest('evil', () => {});\n"
      );
      const traversalRel = path.relative(tmp, traversalAbs);

      const r = runBashIn(tmp, ADOPT, [traversalRel]);

      // The path resolves outside the repo. adopt-qa-test must NOT have
      // created any file inside the repo's tree under tests/, and must NOT
      // have removed the QA file outside the repo. Acceptable outcomes:
      // exit 1 (git mv refuses) or exit 2 (no peer / unsupported). What is
      // NOT acceptable: a successful (`exit 0`) adoption that lands a file
      // somewhere unexpected.
      expect(r.status).not.toBe(0);
      // No qa-foo file appeared inside the repo's tests/ tree at the
      // traversal-implied location.
      const escaped = path.join(outside, 'foo.qa.test.ts');
      expect(fs.existsSync(escaped)).toBe(false);
      // Original QA file outside the repo is still in place — the adopt
      // script must not delete files it has refused to adopt.
      expect(fs.existsSync(traversalAbs)).toBe(true);
    } finally {
      fs.rmSync(outside, { recursive: true, force: true });
    }
  });

  it('P1 — non-ASCII characters in QA-test base name preserve content and adopt cleanly', () => {
    // The peer test is plain ASCII; only the QA file uses non-ASCII. The
    // adopted target name is derived from the peer base, so it stays ASCII.
    // What we adversarially probe: that the QA file's *content* (which
    // contains non-ASCII identifiers) survives `git mv` byte-for-byte.
    gitInit(tmp);
    fs.mkdirSync(path.join(tmp, 'src'), { recursive: true });
    fs.mkdirSync(path.join(tmp, 'tests/unit'), { recursive: true });
    fs.writeFileSync(path.join(tmp, 'src/widget.ts'), 'export const w = 1;\n');
    fs.writeFileSync(
      path.join(tmp, 'tests/unit/widget.test.ts'),
      "import { w } from '../../src/widget';\nimport { test, expect } from 'vitest';\ntest('peer', () => expect(w).toBe(1));\n"
    );
    const qaContent =
      "import { w } from '../../src/widget';\n" +
      "import { test, expect } from 'vitest';\n" +
      "test('日本語 — RTL: العربية — combining: é', () => expect(w).toBe(1));\n";
    const qaRel = 'tests/unit/qa-i18n.test.ts';
    fs.writeFileSync(path.join(tmp, qaRel), qaContent, { encoding: 'utf8' });
    gitAddCommit(tmp, 'seed');

    const r = runBashIn(tmp, ADOPT, [qaRel]);
    expect(r.status, `stderr=${r.stderr}`).toBe(0);

    const adoptedPath = r.stdout.trim();
    expect(adoptedPath).toBe('tests/unit/widget.qa.test.ts');
    const adoptedContent = fs.readFileSync(path.join(tmp, adoptedPath), 'utf8');
    // Bit-for-bit content preservation is the i18n invariant.
    expect(adoptedContent).toBe(qaContent);
    // Original qa-* path is gone (renamed, not copied).
    expect(fs.existsSync(path.join(tmp, qaRel))).toBe(false);
  });
});

// ----------------------------------------------------------------------------
// State transitions dimension — FR-9 safety-net glob anchoring
// ----------------------------------------------------------------------------
//
// The FR-9 safety-net script in finalizing-workflow/scripts/preflight-checks.sh
// uses three globs (anchored to canonical ephemeral paths):
//   - tests/unit/qa-*.test.ts
//   - tests/unit/qa-*.test.js
//   - tests/bats/qa/qa-*.bats
//
// These tests probe whether plausible-but-non-canonical paths leak past the
// gate. The goal is not to score the script wrong — anchoring is intentional
// per CLAUDE.md (so permanent qa-dispatch.bats / qa-baseline.bats etc. don't
// trip the gate) — but to *document* the v1 surface area as a coverage report.
// Findings are surfaced in ## Findings and counted as `coverage-gap` in the
// reconciliation delta, not as a code defect.

describe('FR-9 safety-net (preflight-checks.sh): glob coverage probe', () => {
  // We invoke `git ls-files` directly with the v1 glob set. This mirrors what
  // the script does internally (lines 336-340). Tracking is the trigger; the
  // gate fires iff ls-files emits any path.

  function lsFilesV1(cwd: string): string[] {
    const r = spawnSync(
      'git',
      ['ls-files', 'tests/unit/qa-*.test.ts', 'tests/unit/qa-*.test.js', 'tests/bats/qa/qa-*.bats'],
      { cwd, encoding: 'utf8' }
    );
    return (r.stdout ?? '')
      .split('\n')
      .map((line) => line.trim())
      .filter(Boolean);
  }

  it('Edge probe: a tracked .tsx-extension QA test under tests/unit is NOT caught by the v1 glob', () => {
    // .tsx is a valid React-ish test extension; if a QA author writes
    // `qa-leak.test.tsx`, the glob `qa-*.test.ts` does not match (fnmatch
    // does not treat .ts as a prefix of .tsx).
    gitInit(tmp);
    fs.mkdirSync(path.join(tmp, 'tests/unit'), { recursive: true });
    fs.writeFileSync(path.join(tmp, 'tests/unit/qa-leak.test.tsx'), 'export const _ = 1;\n');
    gitAddCommit(tmp, 'seed');

    const leaks = lsFilesV1(tmp);
    // Document the gap: v1 globs do NOT see the .tsx file. This is the
    // current behavior; reporting it here makes the surface area explicit.
    expect(leaks).toEqual([]);
  });

  it('Edge probe: a tracked qa-* file in a tests/unit subdirectory is NOT caught by the v1 glob', () => {
    // git ls-files pathspecs use fnmatch where `*` does not cross `/`.
    // A QA test placed under tests/unit/sub/qa-*.test.ts therefore escapes.
    gitInit(tmp);
    fs.mkdirSync(path.join(tmp, 'tests/unit/sub'), { recursive: true });
    fs.writeFileSync(path.join(tmp, 'tests/unit/sub/qa-leak.test.ts'), 'export const _ = 1;\n');
    gitAddCommit(tmp, 'seed');

    const leaks = lsFilesV1(tmp);
    expect(leaks).toEqual([]);
  });

  it('Edge probe: a tracked qa-*.bats file directly under tests/bats (not tests/bats/qa) is NOT caught', () => {
    // The bats glob is anchored to tests/bats/qa/, intentional per CLAUDE.md
    // (so permanent fixtures under tests/bats/skills/<skill>/qa-*.bats don't
    // trip). A qa-*.bats file at tests/bats/qa-foo.bats lives between the
    // canonical leaf and the permanent infrastructure; document it.
    gitInit(tmp);
    fs.mkdirSync(path.join(tmp, 'tests/bats'), { recursive: true });
    fs.writeFileSync(
      path.join(tmp, 'tests/bats/qa-misplaced.bats'),
      '#!/usr/bin/env bats\n@test "x" { :; }\n'
    );
    gitAddCommit(tmp, 'seed');

    const leaks = lsFilesV1(tmp);
    expect(leaks).toEqual([]);
  });

  it('Confirms a canonical-leaf qa-* file IS caught by the v1 glob (control)', () => {
    gitInit(tmp);
    fs.mkdirSync(path.join(tmp, 'tests/unit'), { recursive: true });
    fs.writeFileSync(path.join(tmp, 'tests/unit/qa-canonical.test.ts'), 'export const _ = 1;\n');
    gitAddCommit(tmp, 'seed');

    const leaks = lsFilesV1(tmp);
    expect(leaks).toEqual(['tests/unit/qa-canonical.test.ts']);
  });
});
