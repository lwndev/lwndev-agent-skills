// FEAT-030 regression — executing-qa is report-only.
//
// Drives the end-to-end producer pipeline (`run-framework.sh` ->
// `qa-reconcile-delta.sh` -> `render-qa-results.sh` -> `parse-qa-return.sh`
// -> `workflow-state.sh record-findings --type qa` -> `stop-hook.sh`)
// against the FEAT-030 known-buggy fixture and asserts the four NFR-5
// outcomes plus the negative variant (FR-10 stop-hook blocks a simulated
// production-file edit).
//
// Option B per the FEAT-030 plan: vitest invokes the producer scripts
// directly so the contract is verified end-to-end without needing to drive
// the executing-qa skill from a Claude Code agent session.

import { describe, it, expect, beforeEach, afterEach, beforeAll } from 'vitest';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  mkdtempSync,
  rmSync,
  mkdirSync,
  writeFileSync,
  readFileSync,
  cpSync,
  existsSync,
  unlinkSync,
} from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const ROOT = process.cwd();
const FIXTURE_SRC = join(ROOT, 'scripts/__tests__/fixtures/feat-030-known-buggy');
const ROOT_VITEST_BIN = join(ROOT, 'node_modules/.bin/vitest');

const RUN_FRAMEWORK = join(
  ROOT,
  'plugins/lwndev-sdlc/skills/executing-qa/scripts/run-framework.sh'
);
const QA_RECONCILE = join(
  ROOT,
  'plugins/lwndev-sdlc/skills/executing-qa/scripts/qa-reconcile-delta.sh'
);
const RENDER_QA = join(
  ROOT,
  'plugins/lwndev-sdlc/skills/executing-qa/scripts/render-qa-results.sh'
);
const QA_BASELINE = join(ROOT, 'plugins/lwndev-sdlc/skills/executing-qa/scripts/qa-baseline.sh');
const STOP_HOOK = join(ROOT, 'plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh');
const PARSE_QA_RETURN = join(
  ROOT,
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/parse-qa-return.sh'
);
const WORKFLOW_STATE = join(
  ROOT,
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh'
);

const FIXTURE_ID = 'FEAT-999';
const QA_STEP_INDEX_CHORE = 5; // chore chain: executing-qa is the 6th entry.
const TMP_CAPABILITY_PATH = `/tmp/qa-capability-${FIXTURE_ID}.json`;

type ExecJson = {
  total: number;
  passed: number;
  failed: number;
  errored: number;
  failingNames: string[];
  truncatedOutput: string;
  exitCode: number;
  durationMs: number;
};

function copyFixture(destParent: string): string {
  const dest = join(destParent, 'fixture');
  cpSync(FIXTURE_SRC, dest, { recursive: true });
  return dest;
}

function gitInit(repoDir: string): string {
  execFileSync('git', ['init', '-q', repoDir], { stdio: 'pipe' });
  execFileSync('git', ['-C', repoDir, 'config', 'user.email', 't@t.com']);
  execFileSync('git', ['-C', repoDir, 'config', 'user.name', 't']);
  execFileSync('git', ['-C', repoDir, 'add', '-A']);
  execFileSync('git', ['-C', repoDir, 'commit', '-q', '-m', 'fixture'], { stdio: 'pipe' });
  return execFileSync('git', ['-C', repoDir, 'rev-parse', 'HEAD'], {
    encoding: 'utf-8',
  }).trim();
}

function writeRunnerCapability(repoDir: string): string {
  // The fixture has no node_modules of its own. Point testCommand at the
  // root vitest binary with the fixture's vitest.config so run-framework.sh
  // executes vitest end-to-end against src/buggy.ts + qa-buggy.spec.ts.
  const cap = {
    id: FIXTURE_ID,
    timestamp: new Date().toISOString(),
    mode: 'test-framework',
    framework: 'vitest',
    packageManager: 'npm',
    testCommand: `${ROOT_VITEST_BIN} run --root ${repoDir} --config ${join(
      repoDir,
      'vitest.config.ts'
    )}`,
    language: 'typescript',
    notes: [],
  };
  const path = join(repoDir, 'runner-capability.json');
  writeFileSync(path, JSON.stringify(cap, null, 2));
  return path;
}

function writeStopHookCapability(): void {
  // The stop-hook reads /tmp/qa-capability-{ID}.json to pick the test-root
  // patterns for the FR-10 diff guard. Use the canonical vitest capability
  // (testCommand here is irrelevant — only `framework` matters to the guard).
  writeFileSync(
    TMP_CAPABILITY_PATH,
    JSON.stringify({
      id: FIXTURE_ID,
      mode: 'test-framework',
      framework: 'vitest',
      packageManager: 'npm',
      testCommand: 'npm test',
      language: 'typescript',
    })
  );
}

function clearStopHookCapability(): void {
  if (existsSync(TMP_CAPABILITY_PATH)) unlinkSync(TMP_CAPABILITY_PATH);
}

function runFramework(repoDir: string, capabilityPath: string, glob: string): ExecJson {
  // Strip VITEST_* env vars when invoking the nested vitest run so the child
  // does not inherit the parent suite's worker / thread / config hints.
  // Disable ANSI color output in the child so run-framework.sh's vitest
  // summary-line regex (`^[[:space:]]*Tests[[:space:]]+`) matches — the
  // parent suite leaves FORCE_COLOR set, which leaks into the child and
  // turns the `Tests …` line into `\x1b[2m      Tests \x1b[22m …`,
  // breaking the regex.
  const childEnv: NodeJS.ProcessEnv = { ...process.env };
  for (const key of Object.keys(childEnv)) {
    if (key.startsWith('VITEST') || key === 'VITE_NODE_DEPS_MODULE_DIRECTORIES') {
      delete childEnv[key];
    }
  }
  childEnv.NO_COLOR = '1';
  childEnv.FORCE_COLOR = '0';
  const result = spawnSync('bash', [RUN_FRAMEWORK, capabilityPath, glob], {
    cwd: repoDir,
    encoding: 'utf-8',
    env: childEnv,
  });
  if (!result.stdout) {
    throw new Error(
      `run-framework.sh emitted no stdout (status=${result.status})\nSTDERR:\n${result.stderr}`
    );
  }
  try {
    const parsed = JSON.parse(result.stdout) as ExecJson;
    if (parsed.failed === 0 && parsed.passed === 0 && parsed.errored === 0) {
      throw new Error(
        `run-framework.sh parsed zero counts — likely vitest reused parent process. STDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`
      );
    }
    return parsed;
  } catch (err) {
    if ((err as Error).message?.startsWith('run-framework.sh parsed')) throw err;
    throw new Error(
      `run-framework.sh stdout is not JSON (status=${result.status}):\n${result.stdout}\nSTDERR:\n${result.stderr}`
    );
  }
}

function renderArtifact(
  repoDir: string,
  verdict: string,
  capPath: string,
  execPath: string
): string {
  const out = execFileSync('bash', [RENDER_QA, FIXTURE_ID, verdict, capPath, execPath], {
    cwd: repoDir,
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  // The script emits the relative path it wrote to (e.g. `qa/test-results/...`).
  // Resolve against the repo dir so callers can read/stat it without cwd magic.
  const rel = out.trim();
  return rel.startsWith('/') ? rel : join(repoDir, rel);
}

function reconcile(resultsDoc: string, requirementsDoc: string, repoDir: string): string {
  return execFileSync('bash', [QA_RECONCILE, resultsDoc, requirementsDoc], {
    cwd: repoDir,
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}

function parseFinalLine(repoDir: string, line: string, artifactPath: string) {
  const out = execFileSync('bash', [PARSE_QA_RETURN, '--stdin', '--artifact', artifactPath], {
    cwd: repoDir,
    input: line,
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return JSON.parse(out) as Record<string, unknown>;
}

function initWorkflowState(repoDir: string, id: string): void {
  execFileSync('bash', [WORKFLOW_STATE, 'init', id, 'chore'], {
    cwd: repoDir,
    stdio: 'pipe',
  });
}

function recordQaFindings(
  repoDir: string,
  id: string,
  stepIndex: number,
  verdict: string,
  passed: number,
  failed: number,
  errored: number,
  summary: string
): void {
  execFileSync(
    'bash',
    [
      WORKFLOW_STATE,
      'record-findings',
      '--type',
      'qa',
      id,
      String(stepIndex),
      verdict,
      String(passed),
      String(failed),
      String(errored),
      summary,
    ],
    { cwd: repoDir, stdio: 'pipe' }
  );
}

function readWorkflowState(repoDir: string, id: string): Record<string, unknown> {
  return JSON.parse(readFileSync(join(repoDir, '.sdlc/workflows', `${id}.json`), 'utf-8'));
}

function runStopHook(
  repoDir: string,
  artifactBasename: string
): { status: number; stderr: string; stdout: string } {
  const result = spawnSync('bash', [STOP_HOOK], {
    cwd: repoDir,
    input: JSON.stringify({
      last_assistant_message: `Results saved to qa/test-results/${artifactBasename}`,
    }),
    encoding: 'utf-8',
  });
  return {
    status: result.status ?? 1,
    stderr: result.stderr ?? '',
    stdout: result.stdout ?? '',
  };
}

let workdir: string;
let repoDir: string;

beforeAll(() => {
  expect(existsSync(ROOT_VITEST_BIN)).toBe(true);
  expect(existsSync(FIXTURE_SRC)).toBe(true);
});

beforeEach(() => {
  workdir = mkdtempSync(join(tmpdir(), 'feat030-'));
  repoDir = copyFixture(workdir);
  // Make the fixture a real git repo so the FR-10 diff guard can compute
  // git diff <baseline> HEAD. The baseline marker captures HEAD post-init.
  gitInit(repoDir);
  // Initial workflow state with the chore chain — executing-qa lives at
  // step index 5.
  initWorkflowState(repoDir, FIXTURE_ID);
  // Install state markers as the executing-qa skill would on startup.
  mkdirSync(join(repoDir, '.sdlc/qa'), { recursive: true });
  writeFileSync(join(repoDir, '.sdlc/qa/.executing-active'), '');
  execFileSync('bash', [QA_BASELINE, 'init', FIXTURE_ID], {
    cwd: repoDir,
    stdio: 'pipe',
  });
  writeStopHookCapability();
});

afterEach(() => {
  if (workdir) rmSync(workdir, { recursive: true, force: true });
  clearStopHookCapability();
});

describe('FEAT-030 regression: executing-qa is report-only', () => {
  it('produces ISSUES-FOUND verdict against the known-buggy fixture', () => {
    const capPath = writeRunnerCapability(repoDir);
    const exec = runFramework(repoDir, capPath, '__tests__/qa-buggy.spec.ts');

    expect(exec.failed).toBeGreaterThan(0);
    expect(exec.passed).toBe(0);
    expect(exec.errored).toBe(0);
    expect(exec.failingNames.length).toBeGreaterThan(0);

    const execPath = join(repoDir, 'execution.json');
    writeFileSync(execPath, JSON.stringify(exec));
    const artifact = renderArtifact(repoDir, 'ISSUES-FOUND', capPath, execPath);

    expect(existsSync(artifact)).toBe(true);
    const body = readFileSync(artifact, 'utf-8');
    expect(body).toMatch(/^verdict: ISSUES-FOUND$/m);
    expect(body).toMatch(/^- Total: \d+$/m);
    expect(body).toMatch(/^- Failed: [1-9]\d*$/m);
    expect(body).toMatch(/^- Exit code: [1-9]\d*$/m);
  });

  it('does not modify production files during the run', () => {
    const capPath = writeRunnerCapability(repoDir);
    const exec = runFramework(repoDir, capPath, '__tests__/qa-buggy.spec.ts');
    const execPath = join(repoDir, 'execution.json');
    writeFileSync(execPath, JSON.stringify(exec));
    renderArtifact(repoDir, 'ISSUES-FOUND', capPath, execPath);

    // The buggy production file MUST be byte-identical after the run.
    const originalBuggy = readFileSync(join(FIXTURE_SRC, 'src/buggy.ts'), 'utf-8');
    const postRunBuggy = readFileSync(join(repoDir, 'src/buggy.ts'), 'utf-8');
    expect(postRunBuggy).toBe(originalBuggy);
  });

  it('lists failing test names in the artifact ## Findings', () => {
    const capPath = writeRunnerCapability(repoDir);
    const exec = runFramework(repoDir, capPath, '__tests__/qa-buggy.spec.ts');
    const execPath = join(repoDir, 'execution.json');
    writeFileSync(execPath, JSON.stringify(exec));
    const artifact = renderArtifact(repoDir, 'ISSUES-FOUND', capPath, execPath);

    const body = readFileSync(artifact, 'utf-8');
    const findingsBlock = body.split('## Findings')[1].split('## ')[0];
    // At least one failing-test reference must appear.
    expect(findingsBlock).toMatch(/classifyNumber/);
  });

  it('persists FR-1 findings shape to workflow-state JSON', () => {
    const capPath = writeRunnerCapability(repoDir);
    const exec = runFramework(repoDir, capPath, '__tests__/qa-buggy.spec.ts');
    const execPath = join(repoDir, 'execution.json');
    writeFileSync(execPath, JSON.stringify(exec));
    const artifact = renderArtifact(repoDir, 'ISSUES-FOUND', capPath, execPath);

    const finalLine = `Verdict: ISSUES-FOUND | Passed: ${exec.passed} | Failed: ${exec.failed} | Errored: ${exec.errored}`;
    const parsed = parseFinalLine(repoDir, finalLine, artifact) as {
      verdict: string;
      passed: number;
      failed: number;
      errored: number;
      summary: string;
    };

    recordQaFindings(
      repoDir,
      FIXTURE_ID,
      QA_STEP_INDEX_CHORE,
      parsed.verdict,
      parsed.passed,
      parsed.failed,
      parsed.errored,
      parsed.summary
    );

    const state = readWorkflowState(repoDir, FIXTURE_ID) as {
      steps: Array<{ skill?: string; findings?: Record<string, unknown> }>;
    };
    const qaStep = state.steps[QA_STEP_INDEX_CHORE];
    expect(qaStep.skill).toBe('executing-qa');
    expect(qaStep.findings).toBeDefined();
    expect(qaStep.findings).toMatchObject({
      verdict: 'ISSUES-FOUND',
      passed: 0,
      errored: 0,
    });
    expect((qaStep.findings as { failed: number }).failed).toBeGreaterThan(0);
    // Summary string carries the artifact path pointer.
    expect((qaStep.findings as { summary: string }).summary).toMatch(/QA-results-/);
  });

  it('does not block via stop-hook (artifact is well-formed)', () => {
    const capPath = writeRunnerCapability(repoDir);
    const exec = runFramework(repoDir, capPath, '__tests__/qa-buggy.spec.ts');
    const execPath = join(repoDir, 'execution.json');
    writeFileSync(execPath, JSON.stringify(exec));
    const artifact = renderArtifact(repoDir, 'ISSUES-FOUND', capPath, execPath);

    // Reconciliation delta runs against the fixture requirements doc.
    const reconciliation = reconcile(artifact, join(repoDir, 'requirements.md'), repoDir);
    expect(reconciliation).toMatch(/coverage-surplus: \d+/);
    expect(reconciliation).toMatch(/coverage-gap: \d+/);

    // Re-render with the reconciliation body to mirror the real skill flow.
    const env = { ...process.env, QA_RECONCILIATION: reconciliation };
    execFileSync('bash', [RENDER_QA, FIXTURE_ID, 'ISSUES-FOUND', capPath, execPath], {
      cwd: repoDir,
      env,
      stdio: 'pipe',
    });

    // Stop-hook validates the artifact + runs the FR-10 diff guard. The
    // guard sees no diff outside the test root because we only modified
    // qa/test-results and execution.json (the latter is in the repo root
    // — it is a runner artifact, not a production source file). The diff
    // guard considers it "outside test root" but execution.json is also
    // not a tracked file at baseline; let's stage and commit only the
    // QA artifact path under qa/test-results to keep the diff clean.
    execFileSync('git', ['-C', repoDir, 'add', 'qa/test-results/']);
    execFileSync('git', ['-C', repoDir, 'commit', '-q', '-m', 'qa artifact'], {
      stdio: 'pipe',
    });

    const result = runStopHook(repoDir, `QA-results-${FIXTURE_ID}.md`);
    if (result.status !== 0) {
      // Surface the stop-hook stderr to make failures actionable in CI.
      throw new Error(`stop-hook blocked: ${result.stderr}`);
    }
    expect(result.status).toBe(0);
  });

  // --- Negative variant — FR-10 stop-hook MUST block production edits ---

  it('blocks via FR-10 stop-hook when production files are modified outside test root', () => {
    const capPath = writeRunnerCapability(repoDir);
    const exec = runFramework(repoDir, capPath, '__tests__/qa-buggy.spec.ts');
    const execPath = join(repoDir, 'execution.json');
    writeFileSync(execPath, JSON.stringify(exec));
    renderArtifact(repoDir, 'ISSUES-FOUND', capPath, execPath);

    // Simulate the pre-FEAT-030 misbehavior: the skill edits a production
    // file mid-run to "make the failing test pass" instead of reporting.
    writeFileSync(
      join(repoDir, 'src/buggy.ts'),
      `// Patched mid-run — the FR-10 diff guard MUST block this.
export function classifyNumber(n: number): 'positive' | 'negative' | 'zero' {
  if (n === 0) return 'zero';
  if (n > 0) return 'positive';
  return 'negative';
}
`
    );
    execFileSync('git', ['-C', repoDir, 'add', '-A']);
    execFileSync(
      'git',
      ['-C', repoDir, 'commit', '-q', '-m', 'illegal mid-run patch (regression simulation)'],
      { stdio: 'pipe' }
    );

    const result = runStopHook(repoDir, `QA-results-${FIXTURE_ID}.md`);
    expect(result.status).toBe(2);
    // Verbatim FR-10 error fragments — the hook names the offending file
    // and surfaces the report-only directive.
    expect(result.stderr).toContain(
      'executing-qa modified production files outside the framework test root'
    );
    expect(result.stderr).toContain('src/buggy.ts');
    expect(result.stderr).toContain('QA is report-only');
    expect(result.stderr).toContain('Revert these files and add the issue to ## Findings');
  });
});
