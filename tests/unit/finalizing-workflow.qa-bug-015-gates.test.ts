// QA-BUG-015: Adversarial probes for the confirmation-gate hooks introduced
// in BUG-015. These tests are independent of the bats fixtures the fix added —
// they exercise the same hook scripts via vitest+execFileSync to give an
// independent failure-mode signal under the QA persona.
//
// Plan reference: qa/test-plans/QA-plan-BUG-015.md
// Hooks under test:
//   plugins/lwndev-sdlc/scripts/hooks/guard-findings-edits.sh   (RC-1)
//   plugins/lwndev-sdlc/scripts/hooks/guard-agent-prompts.sh    (RC-2)
//   plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh (RC-3)

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, utimesSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const REPO_ROOT = process.cwd();
const GUARD_FINDINGS_EDITS = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/scripts/hooks/guard-findings-edits.sh'
);
const GUARD_AGENT_PROMPTS = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/scripts/hooks/guard-agent-prompts.sh'
);
const WORKFLOW_STATE = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh'
);

type HookEnvelope = {
  hookSpecificOutput?: { permissionDecision?: 'allow' | 'deny' | 'ask' };
  systemMessage?: string;
};

function fireHook(
  hookPath: string,
  payload: unknown,
  cwd: string
): { stdout: string; status: number } {
  const result = spawnSync('bash', [hookPath], {
    encoding: 'utf-8',
    cwd,
    input: JSON.stringify(payload),
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return { stdout: result.stdout ?? '', status: result.status ?? -1 };
}

function parseDecision(stdout: string): HookEnvelope | null {
  const trimmed = stdout.trim();
  if (!trimmed) return null;
  try {
    return JSON.parse(trimmed) as HookEnvelope;
  } catch {
    return null;
  }
}

function setActiveWorkflow(repo: string, id: string): void {
  mkdirSync(join(repo, '.sdlc/workflows'), { recursive: true });
  writeFileSync(join(repo, '.sdlc/workflows/.active'), `${id}\n`);
}

function initWorkflowState(repo: string, id: string, type: 'feature' | 'chore' | 'bug'): void {
  setActiveWorkflow(repo, id);
  execFileSync('bash', [WORKFLOW_STATE, 'init', id, type], { cwd: repo, stdio: 'pipe' });
}

function setGate(repo: string, id: string, gateType: string): void {
  execFileSync('bash', [WORKFLOW_STATE, 'set-gate', id, gateType], { cwd: repo, stdio: 'pipe' });
}

function clearGate(repo: string, id: string): void {
  execFileSync('bash', [WORKFLOW_STATE, 'clear-gate', id], { cwd: repo, stdio: 'pipe' });
}

function writeMarker(repo: string, name: string, mtimeOffsetSeconds: number = 0): string {
  const dir = join(repo, '.sdlc/approvals');
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `.approval-${name}`);
  writeFileSync(path, `timestamp: ${new Date().toISOString()}\n`);
  if (mtimeOffsetSeconds !== 0) {
    const seconds = Math.floor(Date.now() / 1000) + mtimeOffsetSeconds;
    utimesSync(path, seconds, seconds);
  }
  return path;
}

let repo: string;

beforeEach(() => {
  repo = mkdtempSync(join(tmpdir(), 'qa-bug-015-'));
});

afterEach(() => {
  rmSync(repo, { recursive: true, force: true });
});

describe('QA-BUG-015 RC-1: guard-findings-edits.sh denies Edit/Write/MultiEdit on gated requirements path', () => {
  it.each([
    ['Edit', 'requirements/bugs/BUG-100-foo.md'],
    ['Write', 'requirements/features/FEAT-100-bar.md'],
    ['MultiEdit', 'requirements/chores/CHORE-100-baz.md'],
  ])('denies %s on %s with gate set and no marker', (toolName, filePath) => {
    initWorkflowState(repo, 'BUG-100', 'bug');
    setGate(repo, 'BUG-100', 'findings-decision');
    const { stdout, status } = fireHook(
      GUARD_FINDINGS_EDITS,
      { tool_name: toolName, tool_input: { file_path: filePath } },
      repo
    );
    expect(status).toBe(0);
    const env = parseDecision(stdout);
    expect(env, `expected JSON envelope on stdout, got: ${stdout}`).not.toBeNull();
    expect(env?.hookSpecificOutput?.permissionDecision).toBe('deny');
    expect(env?.systemMessage ?? '').toMatch(/findings-decision/);
  });

  it('allows Edit when gate is null (cleared)', () => {
    initWorkflowState(repo, 'BUG-100', 'bug');
    setGate(repo, 'BUG-100', 'findings-decision');
    clearGate(repo, 'BUG-100');
    const { stdout, status } = fireHook(
      GUARD_FINDINGS_EDITS,
      { tool_name: 'Edit', tool_input: { file_path: 'requirements/bugs/BUG-100-foo.md' } },
      repo
    );
    expect(status).toBe(0);
    expect(stdout.trim()).toBe('');
  });

  it('allows Edit on out-of-scope path even when gate is set (no scope creep)', () => {
    initWorkflowState(repo, 'BUG-100', 'bug');
    setGate(repo, 'BUG-100', 'findings-decision');
    const { stdout, status } = fireHook(
      GUARD_FINDINGS_EDITS,
      { tool_name: 'Edit', tool_input: { file_path: 'src/index.ts' } },
      repo
    );
    expect(status).toBe(0);
    expect(stdout.trim()).toBe('');
  });

  it('denies Edit with stale marker (mtime predates gateSetAt)', () => {
    initWorkflowState(repo, 'BUG-100', 'bug');
    writeMarker(repo, 'findings-decision-BUG-100', -3600);
    setGate(repo, 'BUG-100', 'findings-decision');
    const { stdout, status } = fireHook(
      GUARD_FINDINGS_EDITS,
      { tool_name: 'Edit', tool_input: { file_path: 'requirements/bugs/BUG-100-foo.md' } },
      repo
    );
    expect(status).toBe(0);
    const env = parseDecision(stdout);
    expect(env?.hookSpecificOutput?.permissionDecision).toBe('deny');
  });

  it('allows Edit with fresh marker (mtime >= gateSetAt)', () => {
    initWorkflowState(repo, 'BUG-100', 'bug');
    setGate(repo, 'BUG-100', 'findings-decision');
    // Write marker AFTER set-gate so its mtime exceeds gateSetAt
    writeMarker(repo, 'findings-decision-BUG-100');
    const { stdout, status } = fireHook(
      GUARD_FINDINGS_EDITS,
      { tool_name: 'Edit', tool_input: { file_path: 'requirements/bugs/BUG-100-foo.md' } },
      repo
    );
    expect(status).toBe(0);
    expect(stdout.trim()).toBe('');
  });

  it('denies Edit on legacy state file (no gateSetAt) after gate is set', () => {
    // Simulate legacy state: init + set-gate but then strip gateSetAt to mimic
    // a state file written by a pre-fix workflow-state.sh. The fix's
    // set-gate writes gateSetAt; this test removes it post-hoc to assert the
    // hook treats missing gateSetAt as infinitely old (BUG-014 / AC9 precedent).
    initWorkflowState(repo, 'BUG-100', 'bug');
    setGate(repo, 'BUG-100', 'findings-decision');
    writeMarker(repo, 'findings-decision-BUG-100');
    const stateFile = join(repo, '.sdlc/workflows/BUG-100.json');
    const beforeJson = JSON.parse(execFileSync('cat', [stateFile], { encoding: 'utf-8' }));
    delete beforeJson.gateSetAt;
    writeFileSync(stateFile, JSON.stringify(beforeJson, null, 2));
    const { stdout } = fireHook(
      GUARD_FINDINGS_EDITS,
      { tool_name: 'Edit', tool_input: { file_path: 'requirements/bugs/BUG-100-foo.md' } },
      repo
    );
    const env = parseDecision(stdout);
    expect(env?.hookSpecificOutput?.permissionDecision).toBe('deny');
  });

  it('allows Edit when no .active marker exists (no active workflow)', () => {
    // No initWorkflowState, no .active file
    const { stdout, status } = fireHook(
      GUARD_FINDINGS_EDITS,
      { tool_name: 'Edit', tool_input: { file_path: 'requirements/bugs/BUG-100-foo.md' } },
      repo
    );
    expect(status).toBe(0);
    expect(stdout.trim()).toBe('');
  });
});

describe('QA-BUG-015 RC-2: guard-agent-prompts.sh extracts embedded SKILL.md name before subagent_type', () => {
  it('denies general-purpose Agent fork with embedded name: finalizing-workflow and no merge marker', () => {
    setActiveWorkflow(repo, 'BUG-100');
    const prompt = '---\nname: finalizing-workflow\n---\nMerge the PR.';
    const { stdout, status } = fireHook(
      GUARD_AGENT_PROMPTS,
      {
        tool_name: 'Agent',
        tool_input: { subagent_type: 'general-purpose', prompt },
      },
      repo
    );
    expect(status).toBe(0);
    const env = parseDecision(stdout);
    expect(env?.hookSpecificOutput?.permissionDecision, `expected deny, got: ${stdout}`).toBe(
      'deny'
    );
    expect(env?.systemMessage ?? '').toMatch(/merge/i);
  });

  it('allows general-purpose Agent fork with embedded name: reviewing-requirements (no false positive)', () => {
    setActiveWorkflow(repo, 'BUG-100');
    const prompt = '---\nname: reviewing-requirements\n---\nValidate the document.';
    const { stdout, status } = fireHook(
      GUARD_AGENT_PROMPTS,
      {
        tool_name: 'Agent',
        tool_input: { subagent_type: 'general-purpose', prompt },
      },
      repo
    );
    expect(status).toBe(0);
    expect(stdout.trim()).toBe('');
  });

  it('allows general-purpose Agent fork with embedded name: finalizing-workflow when fresh merge-approval marker exists', () => {
    setActiveWorkflow(repo, 'BUG-100');
    writeMarker(repo, 'merge-approval-BUG-100');
    const prompt = '---\nname: finalizing-workflow\n---\nMerge the PR.';
    const { stdout, status } = fireHook(
      GUARD_AGENT_PROMPTS,
      {
        tool_name: 'Agent',
        tool_input: { subagent_type: 'general-purpose', prompt },
      },
      repo
    );
    expect(status).toBe(0);
    expect(stdout.trim()).toBe('');
  });

  it('denies finalizing-workflow Agent fork (subagent_type direct) with no marker (regression — existing AC8)', () => {
    setActiveWorkflow(repo, 'BUG-100');
    const { stdout } = fireHook(
      GUARD_AGENT_PROMPTS,
      {
        tool_name: 'Agent',
        tool_input: { subagent_type: 'finalizing-workflow', prompt: 'Merge.' },
      },
      repo
    );
    const env = parseDecision(stdout);
    expect(env?.hookSpecificOutput?.permissionDecision).toBe('deny');
  });
});

describe('QA-BUG-015 RC-3: workflow-state.sh records gateSetAt on set-gate / pause / clear-gate', () => {
  function readState(id: string): Record<string, unknown> {
    const path = join(repo, '.sdlc/workflows', `${id}.json`);
    return JSON.parse(execFileSync('cat', [path], { encoding: 'utf-8' }));
  }

  it('writes gateSetAt as ISO-8601 on set-gate', () => {
    initWorkflowState(repo, 'BUG-100', 'bug');
    setGate(repo, 'BUG-100', 'findings-decision');
    const state = readState('BUG-100');
    expect(state.gateSetAt).toBeTypeOf('string');
    expect(state.gateSetAt as string).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  });

  it('resets gateSetAt to null on clear-gate', () => {
    initWorkflowState(repo, 'BUG-100', 'bug');
    setGate(repo, 'BUG-100', 'findings-decision');
    clearGate(repo, 'BUG-100');
    const state = readState('BUG-100');
    expect(state.gateSetAt).toBeNull();
  });

  it('resets gateSetAt to null on pause (auto-clears gate)', () => {
    initWorkflowState(repo, 'BUG-100', 'bug');
    setGate(repo, 'BUG-100', 'findings-decision');
    execFileSync('bash', [WORKFLOW_STATE, 'pause', 'BUG-100', 'review-findings'], {
      cwd: repo,
      stdio: 'pipe',
    });
    const state = readState('BUG-100');
    expect(state.gate).toBeNull();
    expect(state.gateSetAt).toBeNull();
  });

  it('init writes gate=null and gateSetAt=null', () => {
    initWorkflowState(repo, 'BUG-100', 'bug');
    const state = readState('BUG-100');
    expect(state.gate).toBeNull();
    // gateSetAt may be absent (legacy parity) or null on init; both are valid
    if ('gateSetAt' in state) {
      expect(state.gateSetAt).toBeNull();
    }
  });
});
