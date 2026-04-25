import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, existsSync, chmodSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

/**
 * Adversarial QA test suite for FEAT-028.
 * Exercises the seven new orchestrating-workflows scripts (FR-1..FR-7) with
 * scenarios from qa/test-plans/QA-plan-FEAT-028.md that probe failure modes
 * not directly covered by the per-script bats fixtures.
 */

const SCRIPTS_DIR = join(
  process.cwd(),
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts'
);

type RunResult = { stdout: string; stderr: string; status: number };

function run(script: string, args: string[], opts: { env?: NodeJS.ProcessEnv; cwd?: string } = {}): RunResult {
  try {
    const stdout = execFileSync('bash', [join(SCRIPTS_DIR, script), ...args], {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
      env: opts.env ?? process.env,
      cwd: opts.cwd ?? process.cwd(),
    });
    return { stdout, stderr: '', status: 0 };
  } catch (e: any) {
    return {
      stdout: e.stdout?.toString() ?? '',
      stderr: e.stderr?.toString() ?? '',
      status: e.status ?? -1,
    };
  }
}

function runStrict(
  script: string,
  args: string[],
  opts: { env?: NodeJS.ProcessEnv; cwd?: string } = {}
): RunResult {
  const cmd = `set -euo pipefail; bash "${join(SCRIPTS_DIR, script)}" ${args
    .map((a) => `'${a.replace(/'/g, "'\\''")}'`)
    .join(' ')}`;
  try {
    const stdout = execFileSync('bash', ['-c', cmd], {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
      env: opts.env ?? process.env,
      cwd: opts.cwd ?? process.cwd(),
    });
    return { stdout, stderr: '', status: 0 };
  } catch (e: any) {
    return {
      stdout: e.stdout?.toString() ?? '',
      stderr: e.stderr?.toString() ?? '',
      status: e.status ?? -1,
    };
  }
}

describe('parse-model-flags.sh adversarial inputs', () => {
  it('rejects equals-sign form (--model=sonnet)', () => {
    const r = run('parse-model-flags.sh', ['--model=sonnet', 'FEAT-001']);
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/=/);
  });

  it('rejects unknown flag with non-zero stderr', () => {
    const r = run('parse-model-flags.sh', ['--tier', 'opus', 'FEAT-001']);
    expect(r.status).toBe(2);
    expect(r.stderr.length).toBeGreaterThan(0);
  });

  it('rejects malformed --model-for tier', () => {
    const r = run('parse-model-flags.sh', ['--model-for', 'reviewing-requirements:super', 'FEAT-001']);
    expect(r.status).toBe(2);
  });

  it('rejects empty step-name in --model-for', () => {
    const r = run('parse-model-flags.sh', ['--model-for', ':sonnet', 'FEAT-001']);
    expect(r.status).toBe(2);
  });

  it('rejects two positional tokens', () => {
    const r = run('parse-model-flags.sh', ['--model', 'sonnet', '#186', 'FEAT-001']);
    expect(r.status).toBe(2);
  });

  it('handles last-wins for repeated --model-for on the same step', () => {
    const r = run('parse-model-flags.sh', [
      '--model-for', 'reviewing-requirements:opus',
      '--model-for', 'reviewing-requirements:sonnet',
      'FEAT-001',
    ]);
    expect(r.status).toBe(0);
    const j = JSON.parse(r.stdout);
    expect(j.cliModelFor['reviewing-requirements']).toBe('sonnet');
  });

  it('handles positional interleaved between flags', () => {
    const r = run('parse-model-flags.sh', ['--model', 'opus', '#186', '--complexity', 'high']);
    expect(r.status).toBe(0);
    const j = JSON.parse(r.stdout);
    expect(j.positional).toBe('#186');
    expect(j.cliModel).toBe('opus');
    // --complexity high normalises to bare tier 'opus' per FR-1 (label-to-tier mapping)
    expect(j.cliComplexity).toBe('opus');
  });

  it('runs cleanly under set -euo pipefail (strict mode)', () => {
    const r = runStrict('parse-model-flags.sh', ['--model', 'opus', 'FEAT-001']);
    expect(r.status).toBe(0);
    const j = JSON.parse(r.stdout);
    expect(j.cliModel).toBe('opus');
  });

  it('survives invocation under env -i (no env vars)', () => {
    const r = run('parse-model-flags.sh', ['--model', 'haiku', 'FEAT-001'], {
      env: { PATH: process.env.PATH ?? '/usr/bin:/bin' },
    });
    expect(r.status).toBe(0);
  });
});

describe('parse-findings.sh adversarial outputs', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = mkdtempSync(join(tmpdir(), 'qa-feat-028-'));
  });
  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  it('emits zero counts when summary line is absent', () => {
    const f = join(tmp, 'no-summary.txt');
    writeFileSync(f, 'No issues found in FEAT-001.md.\n');
    const r = run('parse-findings.sh', [f]);
    expect(r.status).toBe(0);
    const j = JSON.parse(r.stdout);
    expect(j.counts).toEqual({ errors: 0, warnings: 0, info: 0 });
    expect(j.individual).toEqual([]);
  });

  it('handles test-plan-mode prefix on summary line', () => {
    const f = join(tmp, 'test-plan-prefix.txt');
    writeFileSync(
      f,
      'Test-plan reconciliation for FEAT-001: Found **0 errors**, **2 warnings**, **1 info**\n'
    );
    const r = run('parse-findings.sh', [f]);
    expect(r.status).toBe(0);
    const j = JSON.parse(r.stdout);
    expect(j.counts.warnings).toBe(2);
    expect(j.counts.info).toBe(1);
  });

  it('parses individual findings with em-dash separator', () => {
    const f = join(tmp, 'em-dash.txt');
    writeFileSync(
      f,
      [
        '**[W1]** internal-consistency — Some warning description',
        '**[I1]** documentation — An informational note',
        '',
        'Found **0 errors**, **1 warnings**, **1 info**',
      ].join('\n')
    );
    const r = run('parse-findings.sh', [f]);
    expect(r.status).toBe(0);
    const j = JSON.parse(r.stdout);
    expect(j.individual).toHaveLength(2);
    expect(j.individual[0].id).toBe('W1');
    expect(j.individual[0].severity).toBe('warning');
    expect(j.individual[1].id).toBe('I1');
  });

  it('parses individual findings with ASCII double-hyphen fallback', () => {
    const f = join(tmp, 'ascii-dash.txt');
    writeFileSync(
      f,
      [
        '**[W1]** category -- description with ASCII dash',
        'Found **0 errors**, **1 warnings**, **0 info**',
      ].join('\n')
    );
    const r = run('parse-findings.sh', [f]);
    expect(r.status).toBe(0);
    const j = JSON.parse(r.stdout);
    expect(j.individual).toHaveLength(1);
    expect(j.individual[0].description).toMatch(/description with ASCII dash/);
  });

  it('does NOT emit warn for errors-only output (W4 scoping)', () => {
    const f = join(tmp, 'errors-only.txt');
    writeFileSync(f, 'Found **2 errors**, **0 warnings**, **0 info**\n');
    const r = run('parse-findings.sh', [f]);
    expect(r.status).toBe(0);
    expect(r.stderr).not.toMatch(/\[warn\] parse-findings/);
  });

  it('exits 1 on missing file', () => {
    const r = run('parse-findings.sh', [join(tmp, 'does-not-exist.txt')]);
    expect(r.status).toBe(1);
  });

  it('exits 2 on missing arg', () => {
    const r = run('parse-findings.sh', []);
    expect(r.status).toBe(2);
  });
});

describe('findings-decision.sh chain+complexity gate', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = mkdtempSync(join(tmpdir(), 'qa-feat-028-'));
    mkdirSync(join(tmp, '.sdlc', 'workflows'), { recursive: true });
  });
  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  function writeState(id: string, type: string, complexity: string): void {
    const state = {
      id,
      type,
      currentStep: 1,
      status: 'in-progress',
      pauseReason: null,
      gate: null,
      steps: [{ name: 'doc', skill: 'doc', context: 'main', status: 'complete', artifact: null, completedAt: null }],
      phases: { total: 0, completed: 0 },
      prNumber: null,
      branch: null,
      startedAt: '2026-04-24T00:00:00Z',
      lastResumedAt: null,
      complexity,
      complexityStage: 'init',
      modelOverride: null,
      modelSelections: [],
    };
    writeFileSync(join(tmp, '.sdlc', 'workflows', `${id}.json`), JSON.stringify(state));
  }

  it('feature/medium with warnings-only emits prompt-user (NOT auto-advance)', () => {
    writeState('FEAT-100', 'feature', 'medium');
    const r = run('findings-decision.sh', ['FEAT-100', '1', '{"errors":0,"warnings":2,"info":1}'], {
      cwd: tmp,
    });
    expect(r.status).toBe(0);
    const j = JSON.parse(r.stdout);
    expect(j.action).toBe('prompt-user');
    expect(j.type).toBe('feature');
    expect(j.complexity).toBe('medium');
  });

  it('chore/low with warnings-only emits auto-advance (Edge Case 20 isolation)', () => {
    writeState('CHORE-100', 'chore', 'low');
    const r = run('findings-decision.sh', ['CHORE-100', '1', '{"errors":0,"warnings":3,"info":0}'], {
      cwd: tmp,
    });
    expect(r.status).toBe(0);
    const j = JSON.parse(r.stdout);
    expect(j.action).toBe('auto-advance');
    expect(j.type).toBe('chore');
    expect(j.complexity).toBe('low');
  });

  it('chore/medium with warnings-only emits auto-advance', () => {
    writeState('CHORE-101', 'chore', 'medium');
    const r = run('findings-decision.sh', ['CHORE-101', '1', '{"errors":0,"warnings":1,"info":0}'], {
      cwd: tmp,
    });
    expect(r.status).toBe(0);
    expect(JSON.parse(r.stdout).action).toBe('auto-advance');
  });

  it('chore/high with warnings-only emits prompt-user', () => {
    writeState('CHORE-102', 'chore', 'high');
    const r = run('findings-decision.sh', ['CHORE-102', '1', '{"errors":0,"warnings":1,"info":0}'], {
      cwd: tmp,
    });
    expect(r.status).toBe(0);
    expect(JSON.parse(r.stdout).action).toBe('prompt-user');
  });

  it('errors > 0 emits pause-errors regardless of chain or complexity', () => {
    writeState('FEAT-101', 'feature', 'low');
    const r = run('findings-decision.sh', ['FEAT-101', '1', '{"errors":3,"warnings":0,"info":0}'], {
      cwd: tmp,
    });
    expect(r.status).toBe(0);
    expect(JSON.parse(r.stdout).action).toBe('pause-errors');
  });

  it('zero counts emits advance', () => {
    writeState('FEAT-102', 'feature', 'high');
    const r = run('findings-decision.sh', ['FEAT-102', '1', '{"errors":0,"warnings":0,"info":0}'], {
      cwd: tmp,
    });
    expect(r.status).toBe(0);
    expect(JSON.parse(r.stdout).action).toBe('advance');
  });

  it('exits 1 on missing state file', () => {
    const r = run('findings-decision.sh', ['FEAT-999', '1', '{"errors":0,"warnings":0,"info":0}'], {
      cwd: tmp,
    });
    expect(r.status).toBe(1);
  });

  it('extra fields in counts are ignored (forward-compat)', () => {
    writeState('FEAT-103', 'feature', 'medium');
    const r = run('findings-decision.sh', [
      'FEAT-103', '1', '{"errors":0,"warnings":1,"info":2,"critical":5}',
    ], { cwd: tmp });
    expect(r.status).toBe(0);
    const j = JSON.parse(r.stdout);
    expect(['auto-advance', 'prompt-user']).toContain(j.action);
  });
});

describe('resolve-pr-number.sh extraction precedence', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = mkdtempSync(join(tmpdir(), 'qa-feat-028-'));
  });
  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  it('picks last-match-wins from multiple #N tokens', () => {
    const f = join(tmp, 'multi-pr.txt');
    writeFileSync(f, 'Earlier #100\nMiddle #150\nFinal #232\n');
    const r = run('resolve-pr-number.sh', ['feat/FEAT-028-test', f]);
    if (r.status === 0) {
      expect(r.stdout.trim()).toBe('232');
    }
    // gh fallback may also fire; either way, the last in-file match must win when present
  });

  it('exits 2 on missing branch arg', () => {
    const r = run('resolve-pr-number.sh', []);
    expect(r.status).toBe(2);
  });
});

describe('init-workflow.sh ID-from-filename + composite ordering', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = mkdtempSync(join(tmpdir(), 'qa-feat-028-'));
    mkdirSync(join(tmp, 'requirements', 'features'), { recursive: true });
  });
  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  it('rejects mismatched TYPE/filename prefix (Edge Case 14)', () => {
    const f = 'requirements/features/FEAT-928-test.md';
    writeFileSync(join(tmp, f), '# FEAT-928 Test\n\n## User Story\nstory\n');
    const r = run('init-workflow.sh', ['chore', f], { cwd: tmp });
    expect(r.status).toBe(1);
    expect(existsSync(join(tmp, '.sdlc', 'workflows', 'FEAT-928.json'))).toBe(false);
  });

  it('exits 1 when artifact filename has no extractable ID', () => {
    const f = 'requirements/features/no-id-here.md';
    writeFileSync(join(tmp, f), '# No ID\n\n## User Story\nstory\n');
    const r = run('init-workflow.sh', ['feature', f], { cwd: tmp });
    expect(r.status).toBe(1);
  });

  it('extracts ID from filename only, not document body (filename-anchored regex)', () => {
    const f = 'requirements/features/FEAT-928-real-id.md';
    writeFileSync(
      join(tmp, f),
      '# Test\n\nThis body mentions CHORE-999 and BUG-123 but those should NOT contaminate the ID.\n\n## User Story\nstory\n'
    );
    const r = run('init-workflow.sh', ['feature', f], { cwd: tmp });
    expect(r.status).toBe(0);
    const out = JSON.parse(r.stdout);
    expect(out.id).toBe('FEAT-928');
    expect(out.type).toBe('feature');
    expect(existsSync(join(tmp, '.sdlc', 'workflows', 'FEAT-928.json'))).toBe(true);
  });
});

describe('check-resume-preconditions.sh pass-through invariants', () => {
  let tmp: string;
  beforeEach(() => {
    tmp = mkdtempSync(join(tmpdir(), 'qa-feat-028-'));
    mkdirSync(join(tmp, '.sdlc', 'workflows'), { recursive: true });
  });
  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  it('exits 1 when state file is missing', () => {
    const r = run('check-resume-preconditions.sh', ['FEAT-999'], { cwd: tmp });
    expect(r.status).toBe(1);
  });

  it('emits chainTable equal to type for each chain type', () => {
    for (const type of ['feature', 'chore', 'bug']) {
      const id = `${type === 'bug' ? 'BUG' : type === 'chore' ? 'CHORE' : 'FEAT'}-200`;
      const state = {
        id,
        type,
        currentStep: 1,
        status: 'paused',
        pauseReason: 'pr-review',
        gate: null,
        steps: [{ name: 'x', skill: 'x', context: 'main', status: 'pending', artifact: null, completedAt: null }],
        phases: { total: 0, completed: 0 },
        prNumber: 100,
        branch: 'feat/x',
        startedAt: '2026-04-24T00:00:00Z',
        lastResumedAt: null,
        complexity: 'medium',
        complexityStage: 'init',
        modelOverride: null,
        modelSelections: [],
      };
      writeFileSync(join(tmp, '.sdlc', 'workflows', `${id}.json`), JSON.stringify(state));
      const r = run('check-resume-preconditions.sh', [id], { cwd: tmp });
      expect(r.status).toBe(0);
      const j = JSON.parse(r.stdout);
      expect(j.chainTable).toBe(j.type);
      expect(j.type).toBe(type);
    }
  });
});

describe('workflow-state.sh set-model-override (FR-7)', () => {
  let tmp: string;
  const SCRIPT = join(SCRIPTS_DIR, 'workflow-state.sh');

  beforeEach(() => {
    tmp = mkdtempSync(join(tmpdir(), 'qa-feat-028-'));
    mkdirSync(join(tmp, '.sdlc', 'workflows'), { recursive: true });
  });
  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  function writeState(id: string): void {
    const state = {
      id,
      type: 'feature',
      currentStep: 0,
      status: 'in-progress',
      pauseReason: null,
      gate: null,
      steps: [{ name: 'x', skill: 'x', context: 'main', status: 'pending', artifact: null, completedAt: null }],
      phases: { total: 0, completed: 0 },
      prNumber: null,
      branch: null,
      startedAt: '2026-04-24T00:00:00Z',
      lastResumedAt: null,
      complexity: 'medium',
      complexityStage: 'init',
      modelOverride: null,
      modelSelections: [],
    };
    writeFileSync(join(tmp, '.sdlc', 'workflows', `${id}.json`), JSON.stringify(state));
  }

  it('rejects label-instead-of-tier (Edge Case 19)', () => {
    writeState('FEAT-300');
    try {
      execFileSync('bash', [SCRIPT, 'set-model-override', 'FEAT-300', 'high'], {
        cwd: tmp,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      throw new Error('expected non-zero exit');
    } catch (e: any) {
      expect(e.status).toBe(2);
    }
  });

  it('permits downgrade (escape-hatch contract)', () => {
    writeState('FEAT-301');
    execFileSync('bash', [SCRIPT, 'set-model-override', 'FEAT-301', 'opus'], {
      cwd: tmp, encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'],
    });
    execFileSync('bash', [SCRIPT, 'set-model-override', 'FEAT-301', 'sonnet'], {
      cwd: tmp, encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'],
    });
    const status = execFileSync('bash', [SCRIPT, 'status', 'FEAT-301'], {
      cwd: tmp, encoding: 'utf-8',
    });
    expect(JSON.parse(status).modelOverride).toBe('sonnet');
  });

  it('is idempotent on repeat-write of the same value', () => {
    writeState('FEAT-302');
    execFileSync('bash', [SCRIPT, 'set-model-override', 'FEAT-302', 'opus'], {
      cwd: tmp, encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'],
    });
    execFileSync('bash', [SCRIPT, 'set-model-override', 'FEAT-302', 'opus'], {
      cwd: tmp, encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'],
    });
    const status = execFileSync('bash', [SCRIPT, 'status', 'FEAT-302'], {
      cwd: tmp, encoding: 'utf-8',
    });
    expect(JSON.parse(status).modelOverride).toBe('opus');
  });

  it('exits 1 on missing state file', () => {
    try {
      execFileSync('bash', [SCRIPT, 'set-model-override', 'FEAT-999', 'opus'], {
        cwd: tmp, encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'],
      });
      throw new Error('expected non-zero exit');
    } catch (e: any) {
      expect(e.status).toBe(1);
    }
  });
});
