import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync, readFileSync, chmodSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const SCRIPTS_DIR = join(
  process.cwd(),
  'plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts'
);
const NEXT_PENDING = join(SCRIPTS_DIR, 'next-pending-phase.sh');
const STATUS_MARKER = join(SCRIPTS_DIR, 'plan-status-marker.sh');
const CHECK_DELIVERABLE = join(SCRIPTS_DIR, 'check-deliverable.sh');
const VERIFY_DELIVERABLES = join(SCRIPTS_DIR, 'verify-phase-deliverables.sh');
const COMMIT_PUSH = join(SCRIPTS_DIR, 'commit-and-push-phase.sh');
const VERIFY_ALL_COMPLETE = join(SCRIPTS_DIR, 'verify-all-phases-complete.sh');

type RunResult = {
  status: number;
  stdout: string;
  stderr: string;
};

function run(script: string, args: string[], env?: NodeJS.ProcessEnv): RunResult {
  const result = spawnSync('bash', [script, ...args], {
    encoding: 'utf-8',
    env: env ?? process.env,
  });
  return {
    status: result.status ?? -1,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
  };
}

let workDir: string;

beforeEach(() => {
  workDir = mkdtempSync(join(tmpdir(), 'qa-feat-027-'));
});

afterEach(() => {
  rmSync(workDir, { recursive: true, force: true });
});

function writePlan(name: string, content: string): string {
  const path = join(workDir, name);
  writeFileSync(path, content);
  return path;
}

describe('FEAT-027 — Inputs dimension', () => {
  describe('P0: zero phase blocks → exit 1 with [error]', () => {
    const plan = `# Empty Plan\n\nNo phases defined here.\n`;

    it('next-pending-phase.sh exits 1', () => {
      const path = writePlan('empty.md', plan);
      const r = run(NEXT_PENDING, [path]);
      expect(r.status).toBe(1);
    });

    it('verify-phase-deliverables.sh exits 1', () => {
      const path = writePlan('empty.md', plan);
      const r = run(VERIFY_DELIVERABLES, [path, '1']);
      expect(r.status).toBe(1);
    });

    it('verify-all-phases-complete.sh exits 1 with [error]', () => {
      const path = writePlan('empty.md', plan);
      const r = run(VERIFY_ALL_COMPLETE, [path]);
      expect(r.status).toBe(1);
      expect(r.stderr).toMatch(/\[error\]/);
    });
  });

  describe('P0: phase missing **Status:** line', () => {
    const plan = [
      '### Phase 1: Foo',
      '',
      '#### Rationale',
      'No status line below.',
      '',
      '#### Deliverables',
      '- [ ] one',
      '',
    ].join('\n');

    it('next-pending-phase.sh exits 1', () => {
      const path = writePlan('no-status.md', plan);
      const r = run(NEXT_PENDING, [path]);
      expect(r.status).toBe(1);
    });

    it('plan-status-marker.sh exits 1 with a phase-1 no-Status error on stderr', () => {
      const path = writePlan('no-status.md', plan);
      const r = run(STATUS_MARKER, [path, '1', 'in-progress']);
      expect(r.status).toBe(1);
      expect(r.stderr).toMatch(/phase 1/);
      expect(r.stderr).toMatch(/\*\*Status:\*\*/);
    });
  });

  describe('P0: **Status:** only inside fenced code block → fence-aware scripts ignore', () => {
    const plan = [
      '### Phase 1: Fenced only',
      '',
      '```markdown',
      '**Status:** Pending',
      '```',
      '',
      '#### Deliverables',
      '- [ ] only fenced status above',
      '',
    ].join('\n');

    it('next-pending-phase.sh treats phase as missing status → exit 1', () => {
      const path = writePlan('fenced.md', plan);
      const r = run(NEXT_PENDING, [path]);
      expect(r.status).toBe(1);
    });

    it('plan-status-marker.sh exits 1 (no real Status: line found)', () => {
      const path = writePlan('fenced.md', plan);
      const r = run(STATUS_MARKER, [path, '1', 'complete']);
      expect(r.status).toBe(1);
      const after = readFileSync(path, 'utf-8');
      expect(after).toBe(plan);
    });

    it('verify-all-phases-complete.sh does not report the fenced Status: line as a completion', () => {
      const path = writePlan('fenced.md', plan);
      const r = run(VERIFY_ALL_COMPLETE, [path]);
      expect(r.status).toBe(1);
    });
  });

  describe('P0: plan-status-marker unknown state tokens → exit 2', () => {
    const plan = [
      '### Phase 1: Solo',
      '**Status:** Pending',
      '',
      '#### Deliverables',
      '- [ ] one',
      '',
    ].join('\n');

    it.each(['Done', 'In Progress', 'complete ', 'COMPLETE', ''])(
      'rejects %p with exit 2',
      (token) => {
        const path = writePlan('one.md', plan);
        const r = run(STATUS_MARKER, [path, '1', token]);
        expect(r.status).toBe(2);
        const after = readFileSync(path, 'utf-8');
        expect(after).toBe(plan);
      }
    );
  });

  describe('P0: check-deliverable numeric index edge cases', () => {
    const plan = [
      '### Phase 1: Three items',
      '**Status:** 🔄 In Progress',
      '',
      '#### Deliverables',
      '- [ ] first',
      '- [ ] second',
      '- [ ] third',
      '',
    ].join('\n');

    it('index 0 → exit 1 out-of-range', () => {
      const path = writePlan('three.md', plan);
      const r = run(CHECK_DELIVERABLE, [path, '1', '0']);
      expect(r.status).toBe(1);
      expect(r.stderr).toMatch(/out of range/);
    });

    it('index == deliverable count → exit 0, last item flipped', () => {
      const path = writePlan('three.md', plan);
      const r = run(CHECK_DELIVERABLE, [path, '1', '3']);
      expect(r.status).toBe(0);
      const after = readFileSync(path, 'utf-8');
      expect(after).toMatch(/- \[x\] third/);
      expect(after).toMatch(/- \[ \] first/);
      expect(after).toMatch(/- \[ \] second/);
    });

    it('index exceeding count → exit 1 with explicit counts', () => {
      const path = writePlan('three.md', plan);
      const r = run(CHECK_DELIVERABLE, [path, '1', '4']);
      expect(r.status).toBe(1);
      expect(r.stderr).toMatch(/index 4 out of range/);
      expect(r.stderr).toMatch(/3 deliverables/);
    });
  });

  describe('P1: check-deliverable text-matcher semantics', () => {
    const planMixed = [
      '### Phase 1: Mixed',
      '**Status:** 🔄 In Progress',
      '',
      '#### Deliverables',
      '- [x] foo already done',
      '- [ ] foo still pending',
      '',
    ].join('\n');

    it('text matcher hits one unchecked + one already-checked → flips only the unchecked', () => {
      const path = writePlan('mixed.md', planMixed);
      const r = run(CHECK_DELIVERABLE, [path, '1', 'foo still pending']);
      expect(r.status).toBe(0);
      expect(r.stdout.trim()).toBe('checked');
      const after = readFileSync(path, 'utf-8');
      expect(after).toMatch(/- \[x\] foo already done/);
      expect(after).toMatch(/- \[x\] foo still pending/);
    });

    it('text matcher matches only already-checked lines → exit 0 already checked, file unchanged', () => {
      const path = writePlan('already.md', planMixed);
      const r = run(CHECK_DELIVERABLE, [path, '1', 'foo already done']);
      expect(r.status).toBe(0);
      expect(r.stdout.trim()).toBe('already checked');
      const after = readFileSync(path, 'utf-8');
      expect(after).toBe(planMixed);
    });
  });

  describe('P2: commit-and-push-phase arg validation', () => {
    it.each([
      ['feat-027', '1', 'name'],
      ['FEATURE-001', '1', 'name'],
      ['FEAT-', '1', 'name'],
      ['FEAT-027a', '1', 'name'],
    ])('rejects lowercase/malformed FEAT-ID %s with exit 2', (id, p, n) => {
      const r = run(COMMIT_PUSH, [id, p, n]);
      expect(r.status).toBe(2);
    });

    it.each([
      ['FEAT-027', '1.5', 'name'],
      ['FEAT-027', '0', 'name'],
      ['FEAT-027', '-1', 'name'],
    ])('rejects non-integer / non-positive phase-N %s with exit 2', (id, p, n) => {
      const r = run(COMMIT_PUSH, [id, p, n]);
      expect(r.status).toBe(2);
    });

    it('rejects empty phase-name with exit 2', () => {
      const r = run(COMMIT_PUSH, ['FEAT-027', '1', '']);
      expect(r.status).toBe(2);
    });

    it('rejects whitespace-only phase-name with exit 2', () => {
      const r = run(COMMIT_PUSH, ['FEAT-027', '1', '   ']);
      expect(r.status).toBe(2);
    });
  });
});

describe('FEAT-027 — State transitions dimension', () => {
  describe('P0: plan-status-marker idempotency — same state twice', () => {
    const plan = [
      '### Phase 1: Solo',
      '**Status:** Pending',
      '',
      '#### Deliverables',
      '- [ ] one',
      '',
    ].join('\n');

    it('first call emits transitioned, second emits already set, no duplicate emoji', () => {
      const path = writePlan('idem.md', plan);
      const first = run(STATUS_MARKER, [path, '1', 'complete']);
      expect(first.status).toBe(0);
      expect(first.stdout.trim()).toBe('transitioned');

      const second = run(STATUS_MARKER, [path, '1', 'complete']);
      expect(second.status).toBe(0);
      expect(second.stdout.trim()).toBe('already set');

      const after = readFileSync(path, 'utf-8');
      const completeMatches = after.match(/\*\*Status:\*\* ✅ Complete/g) ?? [];
      expect(completeMatches.length).toBe(1);
    });
  });

  describe('P1: check-deliverable idempotency across invocations', () => {
    const plan = [
      '### Phase 1: Items',
      '**Status:** 🔄 In Progress',
      '',
      '#### Deliverables',
      '- [ ] alpha',
      '- [ ] beta',
      '',
    ].join('\n');

    it('same matcher twice → first checked, second already checked', () => {
      const path = writePlan('idem2.md', plan);
      const first = run(CHECK_DELIVERABLE, [path, '1', 'alpha']);
      expect(first.status).toBe(0);
      expect(first.stdout.trim()).toBe('checked');

      const second = run(CHECK_DELIVERABLE, [path, '1', 'alpha']);
      expect(second.status).toBe(0);
      expect(second.stdout.trim()).toBe('already checked');
    });
  });

  describe('P2: next-pending-phase reason classifications', () => {
    it('resume-in-progress: Phase 1 In Progress → reason=resume-in-progress', () => {
      const plan = [
        '### Phase 1: Active',
        '**Status:** 🔄 In Progress',
        '',
        '#### Deliverables',
        '- [ ] one',
        '',
        '### Phase 2: Next',
        '**Status:** Pending',
        '',
        '#### Deliverables',
        '- [ ] two',
        '',
      ].join('\n');
      const path = writePlan('resume.md', plan);
      const r = run(NEXT_PENDING, [path]);
      expect(r.status).toBe(0);
      const parsed = JSON.parse(r.stdout);
      expect(parsed.phase).toBe(1);
      expect(parsed.reason).toBe('resume-in-progress');
    });

    it('blocked: Phase 2 Pending with Depends on Phase 3 (forward dep) → blockedOn:[3]', () => {
      const plan = [
        '### Phase 1: A',
        '**Status:** ✅ Complete',
        '',
        '### Phase 2: B',
        '**Status:** Pending',
        '**Depends on:** Phase 3',
        '',
        '### Phase 3: C',
        '**Status:** Pending',
        '',
      ].join('\n');
      const path = writePlan('blocked.md', plan);
      const r = run(NEXT_PENDING, [path]);
      expect(r.status).toBe(0);
      const parsed = JSON.parse(r.stdout);
      expect(parsed.phase).toBeNull();
      expect(parsed.reason).toBe('blocked');
      expect(parsed.blockedOn).toContain(3);
    });

    it('blocked by sequential: Phase 2 Pending but Phase 1 not complete → blocked on 1', () => {
      const plan = [
        '### Phase 1: A',
        '**Status:** Pending',
        '',
        '### Phase 2: B',
        '**Status:** Pending',
        '',
      ].join('\n');
      const path = writePlan('seq.md', plan);
      const r = run(NEXT_PENDING, [path]);
      expect(r.status).toBe(0);
      // Phase 1 is the next pending (sequential); it should be selected, not blocked.
      const parsed = JSON.parse(r.stdout);
      expect(parsed.phase).toBe(1);
    });
  });
});

describe('FEAT-027 — Environment dimension', () => {
  describe('P0: verify-phase-deliverables graceful degradation when npm is absent', () => {
    it('emits [warn] ... npm not found; sets test/build/coverage to skipped; exit 0 when files present', () => {
      const deliverableFile = join(workDir, 'src.ts');
      writeFileSync(deliverableFile, '// present\n');
      const plan = [
        '### Phase 1: Files',
        '**Status:** 🔄 In Progress',
        '',
        '#### Deliverables',
        `- [ ] \`${deliverableFile}\``,
        '',
      ].join('\n');
      const path = writePlan('files.md', plan);

      const fakePathDir = mkdtempSync(join(tmpdir(), 'qa-nopath-'));
      try {
        const env = {
          ...process.env,
          PATH: `${fakePathDir}:/bin:/usr/bin`,
        };
        const r = run(VERIFY_DELIVERABLES, [path, '1'], env);
        expect(r.stderr).toMatch(/\[warn\]/);
        expect(r.stderr).toMatch(/npm not found/);
        const parsed = JSON.parse(r.stdout);
        expect(parsed.test).toBe('skipped');
        expect(parsed.build).toBe('skipped');
        expect(parsed.coverage).toBe('skipped');
        expect(parsed.files.missing).toEqual([]);
        expect(r.status).toBe(0);
      } finally {
        rmSync(fakePathDir, { recursive: true, force: true });
      }
    });
  });
});

describe('FEAT-027 — Dependency failure dimension', () => {
  describe('P0: npm test passes but npm build fails → aggregate test:pass build:fail exit 1', () => {
    it('aggregates sub-check results correctly', () => {
      const deliverableFile = join(workDir, 'src.ts');
      writeFileSync(deliverableFile, '// present\n');
      const plan = [
        '### Phase 1: Mixed',
        '**Status:** 🔄 In Progress',
        '',
        '#### Deliverables',
        `- [ ] \`${deliverableFile}\``,
        '',
      ].join('\n');
      const path = writePlan('mixed.md', plan);

      const stubDir = mkdtempSync(join(tmpdir(), 'qa-stubs-'));
      try {
        const npmStub = join(stubDir, 'npm');
        writeFileSync(
          npmStub,
          [
            '#!/usr/bin/env bash',
            'case "$*" in',
            '  "test")      echo "PASS runtime"; exit 0 ;;',
            '  "run build") echo "build ERROR: missing tsc"; exit 1 ;;',
            '  "run test:coverage") echo "coverage missing"; exit 1 ;;',
            '  *)           echo "unexpected npm invocation: $*" >&2; exit 99 ;;',
            'esac',
            '',
          ].join('\n')
        );
        chmodSync(npmStub, 0o755);

        const env = {
          ...process.env,
          PATH: `${stubDir}:${process.env.PATH ?? ''}`,
        };
        const r = run(VERIFY_DELIVERABLES, [path, '1'], env);
        const parsed = JSON.parse(r.stdout);
        expect(parsed.test).toBe('pass');
        expect(parsed.build).toBe('fail');
        expect(parsed.files.missing).toEqual([]);
        expect(r.status).toBe(1);
        const outputBuild =
          typeof parsed.output === 'object' && parsed.output !== null
            ? (parsed.output.build ?? '')
            : '';
        expect(outputBuild).toContain('build ERROR');
      } finally {
        rmSync(stubDir, { recursive: true, force: true });
      }
    });
  });
});

describe('FEAT-027 — Cross-cutting dimension', () => {
  describe('P2: check-deliverable handles tab-indented deliverable lines', () => {
    it('regex matches `- [ ]` regardless of preceding whitespace', () => {
      const plan = [
        '### Phase 1: Tabs',
        '**Status:** 🔄 In Progress',
        '',
        '#### Deliverables',
        '\t- [ ] tabbed alpha',
        '  - [ ] spaced beta',
        '',
      ].join('\n');
      const path = writePlan('tabs.md', plan);
      const r = run(CHECK_DELIVERABLE, [path, '1', 'tabbed alpha']);
      expect(r.status).toBe(0);
      const after = readFileSync(path, 'utf-8');
      expect(after).toMatch(/- \[x\] tabbed alpha/);
    });
  });

  describe('P2: deliverable paths containing parens are handled safely', () => {
    it('verify-phase-deliverables file-existence check handles `(`/`)` without shell expansion', () => {
      const trickyName = 'file(with-parens).txt';
      const trickyPath = join(workDir, trickyName);
      writeFileSync(trickyPath, 'present\n');

      const plan = [
        '### Phase 1: Parens',
        '**Status:** 🔄 In Progress',
        '',
        '#### Deliverables',
        `- [ ] \`${trickyPath}\``,
        '',
      ].join('\n');
      const path = writePlan('parens.md', plan);

      const fakePathDir = mkdtempSync(join(tmpdir(), 'qa-nopath-'));
      try {
        const env = {
          ...process.env,
          PATH: `${fakePathDir}:/bin:/usr/bin`,
        };
        const r = run(VERIFY_DELIVERABLES, [path, '1'], env);
        const parsed = JSON.parse(r.stdout);
        expect(parsed.files.missing).toEqual([]);
        expect(r.status).toBe(0);
      } finally {
        rmSync(fakePathDir, { recursive: true, force: true });
      }
    });
  });
});
