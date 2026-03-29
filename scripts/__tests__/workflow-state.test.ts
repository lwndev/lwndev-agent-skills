import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execSync } from 'node:child_process';
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const SCRIPT = join(
  process.cwd(),
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh'
);

// Each test gets a fresh temp directory as the working directory
let testDir: string;

function run(args: string, opts?: { expectError?: boolean }): string {
  try {
    return execSync(`bash "${SCRIPT}" ${args}`, {
      cwd: testDir,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, PATH: process.env.PATH },
    }).trim();
  } catch (err) {
    if (opts?.expectError) {
      return (err as { stderr?: string }).stderr?.trim() ?? '';
    }
    throw err;
  }
}

function runJSON(args: string): Record<string, unknown> {
  return JSON.parse(run(args));
}

function readState(id: string): Record<string, unknown> {
  const file = join(testDir, '.sdlc/workflows', `${id}.json`);
  return JSON.parse(readFileSync(file, 'utf-8'));
}

// Create a minimal implementation plan with N phases for phase-count tests
function createPlan(id: string, phases: number): void {
  const dir = join(testDir, 'requirements/implementation');
  mkdirSync(dir, { recursive: true });
  let content = `# Implementation Plan\n\n`;
  for (let i = 1; i <= phases; i++) {
    content += `### Phase ${i}: Phase ${i} Name\n**Status:** Pending\n\n`;
  }
  writeFileSync(join(dir, `${id}-test-plan.md`), content);
}

beforeEach(() => {
  testDir = mkdtempSync(join(tmpdir(), 'wfstate-'));
});

afterEach(() => {
  rmSync(testDir, { recursive: true, force: true });
});

describe('workflow-state.sh', () => {
  describe('init', () => {
    it('creates a state file with correct structure', () => {
      const state = runJSON('init FEAT-001 feature');

      expect(state.id).toBe('FEAT-001');
      expect(state.type).toBe('feature');
      expect(state.currentStep).toBe(0);
      expect(state.status).toBe('in-progress');
      expect(state.pauseReason).toBeNull();
      expect(state.prNumber).toBeNull();
      expect(state.branch).toBeNull();
      expect(state.startedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
      expect(state.lastResumedAt).toBeNull();
      expect(state.phases).toEqual({ total: 0, completed: 0 });
    });

    it('generates 6 initial feature chain steps', () => {
      const state = runJSON('init FEAT-001 feature');
      const steps = state.steps as Array<Record<string, unknown>>;

      expect(steps).toHaveLength(6);
      expect(steps[0].name).toBe('Document feature requirements');
      expect(steps[0].skill).toBe('documenting-features');
      expect(steps[0].context).toBe('main');
      expect(steps[0].status).toBe('pending');

      expect(steps[1].name).toBe('Review requirements (standard)');
      expect(steps[1].skill).toBe('reviewing-requirements');
      expect(steps[1].context).toBe('fork');

      expect(steps[2].name).toBe('Create implementation plan');
      expect(steps[2].skill).toBe('creating-implementation-plans');

      expect(steps[3].name).toBe('Plan approval');
      expect(steps[3].context).toBe('pause');

      expect(steps[4].name).toBe('Document QA test plan');
      expect(steps[4].skill).toBe('documenting-qa');
      expect(steps[4].context).toBe('main');

      expect(steps[5].name).toBe('Reconcile test plan');
      expect(steps[5].skill).toBe('reviewing-requirements');
    });

    it('creates .sdlc/workflows/ directory if it does not exist', () => {
      runJSON('init FEAT-001 feature');
      const state = readState('FEAT-001');
      expect(state.id).toBe('FEAT-001');
    });

    it('returns existing state when workflow already exists (idempotent)', () => {
      runJSON('init FEAT-001 feature');
      // Advance to change state
      run('advance FEAT-001');
      // Re-init should return current state, not overwrite
      const state = runJSON('init FEAT-001 feature');
      expect(state.currentStep).toBe(1);
    });

    it('rejects invalid ID format', () => {
      const err = run('init feat-001 feature', { expectError: true });
      expect(err).toContain('Invalid ID format');
    });

    it('rejects unsupported chain types', () => {
      const err = run('init FEAT-001 chore', { expectError: true });
      expect(err).toContain('not yet implemented');
    });

    it('rejects unknown chain types', () => {
      const err = run('init FEAT-001 unknown', { expectError: true });
      expect(err).toContain('Unknown chain type');
    });

    it('has all required JSON fields', () => {
      const state = runJSON('init FEAT-001 feature');
      const requiredFields = [
        'id',
        'type',
        'currentStep',
        'status',
        'pauseReason',
        'steps',
        'phases',
        'prNumber',
        'branch',
        'startedAt',
        'lastResumedAt',
      ];
      for (const field of requiredFields) {
        expect(state).toHaveProperty(field);
      }
    });
  });

  describe('status', () => {
    it('returns current state as JSON', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('status FEAT-001');
      expect(state.id).toBe('FEAT-001');
      expect(state.status).toBe('in-progress');
    });

    it('errors when state file does not exist', () => {
      const err = run('status FEAT-999', { expectError: true });
      expect(err).toContain('State file not found');
    });

    it('errors on malformed state file', () => {
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/FEAT-001.json'), '{"id": "FEAT-001"}');
      const err = run('status FEAT-001', { expectError: true });
      expect(err).toContain('malformed or missing required fields');
    });

    it('errors on invalid JSON', () => {
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/FEAT-001.json'), 'not json');
      const err = run('status FEAT-001', { expectError: true });
      expect(err).toContain('malformed');
    });
  });

  describe('advance', () => {
    it('marks current step complete and increments currentStep', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('advance FEAT-001');

      expect(state.currentStep).toBe(1);
      const steps = state.steps as Array<Record<string, unknown>>;
      expect(steps[0].status).toBe('complete');
      expect(steps[0].completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it('records artifact path when provided', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('advance FEAT-001 "requirements/features/FEAT-001.md"');

      const steps = state.steps as Array<Record<string, unknown>>;
      expect(steps[0].artifact).toBe('requirements/features/FEAT-001.md');
    });

    it('is a no-op on already completed step (idempotent)', () => {
      runJSON('init FEAT-001 feature');
      // Advance step 0 → now currentStep is 1, step 0 is complete
      runJSON('advance FEAT-001');
      // Manually set currentStep back to 0 to simulate re-advancing a completed step
      const stateFile = join(testDir, '.sdlc/workflows/FEAT-001.json');
      const raw = JSON.parse(readFileSync(stateFile, 'utf-8'));
      raw.currentStep = 0;
      writeFileSync(stateFile, JSON.stringify(raw));
      // Advance again — step 0 is already complete, should be a no-op
      const state = runJSON('advance FEAT-001');
      expect(state.currentStep).toBe(0); // unchanged
    });

    it('advances through multiple steps sequentially', () => {
      runJSON('init FEAT-001 feature');
      run('advance FEAT-001');
      run('advance FEAT-001');
      const state = runJSON('advance FEAT-001');
      expect(state.currentStep).toBe(3);
    });
  });

  describe('pause', () => {
    it('sets status to paused with plan-approval reason', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('pause FEAT-001 plan-approval');
      expect(state.status).toBe('paused');
      expect(state.pauseReason).toBe('plan-approval');
    });

    it('sets status to paused with pr-review reason', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('pause FEAT-001 pr-review');
      expect(state.status).toBe('paused');
      expect(state.pauseReason).toBe('pr-review');
    });

    it('rejects invalid pause reasons', () => {
      runJSON('init FEAT-001 feature');
      const err = run('pause FEAT-001 invalid-reason', { expectError: true });
      expect(err).toContain('Invalid pause reason');
    });
  });

  describe('resume', () => {
    it('sets status to in-progress and clears pauseReason', () => {
      runJSON('init FEAT-001 feature');
      run('pause FEAT-001 plan-approval');
      const state = runJSON('resume FEAT-001');
      expect(state.status).toBe('in-progress');
      expect(state.pauseReason).toBeNull();
    });

    it('sets lastResumedAt to current timestamp', () => {
      runJSON('init FEAT-001 feature');
      run('pause FEAT-001 plan-approval');
      const state = runJSON('resume FEAT-001');
      expect(state.lastResumedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it('clears previous error on resume', () => {
      runJSON('init FEAT-001 feature');
      run('fail FEAT-001 "something broke"');
      const failedState = runJSON('status FEAT-001');
      expect(failedState.error).toBe('something broke');

      const resumedState = runJSON('resume FEAT-001');
      expect(resumedState.error).toBeNull();
      expect(resumedState.status).toBe('in-progress');
    });
  });

  describe('fail', () => {
    it('sets status to failed with error message', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('fail FEAT-001 "Step 3 timed out"');
      expect(state.status).toBe('failed');
      expect(state.error).toBe('Step 3 timed out');
    });

    it('marks the current step as failed', () => {
      runJSON('init FEAT-001 feature');
      run('advance FEAT-001'); // now on step 1
      const state = runJSON('fail FEAT-001 "Review failed"');
      const steps = state.steps as Array<Record<string, unknown>>;
      expect(steps[1].status).toBe('failed');
    });
  });

  describe('complete', () => {
    it('sets status to complete with timestamp', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('complete FEAT-001');
      expect(state.status).toBe('complete');
      expect(state.completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });
  });

  describe('set-pr', () => {
    it('records PR number and branch', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('set-pr FEAT-001 42 feat/FEAT-001-test');
      expect(state.prNumber).toBe(42);
      expect(state.branch).toBe('feat/FEAT-001-test');
    });
  });

  describe('phase-count', () => {
    it('counts phases from implementation plan', () => {
      createPlan('FEAT-001', 3);
      const output = run('phase-count FEAT-001');
      expect(output).toBe('3');
    });

    it('errors when no implementation plan found', () => {
      const err = run('phase-count FEAT-999', { expectError: true });
      expect(err).toContain('No implementation plan found');
    });

    it('errors when plan has 0 phases', () => {
      createPlan('FEAT-001', 0);
      const err = run('phase-count FEAT-001', { expectError: true });
      expect(err).toContain('0 phases');
    });
  });

  describe('populate-phases', () => {
    it('inserts phase steps and post-phase steps after initial 6', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('populate-phases FEAT-001 3');

      const steps = state.steps as Array<Record<string, unknown>>;
      // 6 initial + 3 phase + 5 post-phase = 14
      expect(steps).toHaveLength(14);

      // Phase steps at indices 6, 7, 8
      expect(steps[6].name).toBe('Implement phase 1 of 3');
      expect(steps[6].phaseNumber).toBe(1);
      expect(steps[7].name).toBe('Implement phase 2 of 3');
      expect(steps[7].phaseNumber).toBe(2);
      expect(steps[8].name).toBe('Implement phase 3 of 3');
      expect(steps[8].phaseNumber).toBe(3);

      // Post-phase steps at indices 9-13
      expect(steps[9].name).toBe('Create PR');
      expect(steps[10].name).toBe('PR review');
      expect(steps[11].name).toBe('Reconcile post-review');
      expect(steps[12].name).toBe('Execute QA');
      expect(steps[13].name).toBe('Finalize');
    });

    it('sets phases.total to the count', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('populate-phases FEAT-001 2');
      const phases = state.phases as { total: number; completed: number };
      expect(phases.total).toBe(2);
      expect(phases.completed).toBe(0);
    });

    it('is idempotent — returns current state if phases already populated', () => {
      runJSON('init FEAT-001 feature');
      runJSON('populate-phases FEAT-001 3');
      // Second call should be a no-op
      const state = runJSON('populate-phases FEAT-001 5');
      const steps = state.steps as Array<Record<string, unknown>>;
      // Should still have 14 steps (3 phases), not 16 (5 phases)
      expect(steps).toHaveLength(14);
    });
  });

  describe('phase-status', () => {
    it('returns empty array when no phase steps exist', () => {
      runJSON('init FEAT-001 feature');
      const output = run('phase-status FEAT-001');
      const phases = JSON.parse(output);
      expect(phases).toEqual([]);
    });
  });

  describe('error handling', () => {
    it('shows usage when no command provided', () => {
      const err = run('', { expectError: true });
      expect(err).toContain('Usage:');
    });

    it('rejects unknown commands', () => {
      const err = run('unknown-cmd', { expectError: true });
      expect(err).toContain('Unknown command');
    });

    it('errors when init has missing arguments', () => {
      const err = run('init FEAT-001', { expectError: true });
      expect(err).toContain('init requires');
    });

    it('errors when fail has missing message', () => {
      runJSON('init FEAT-001 feature');
      const err = run('fail FEAT-001', { expectError: true });
      expect(err).toContain('fail requires');
    });
  });
});
