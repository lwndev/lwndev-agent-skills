import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execSync } from 'node:child_process';
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const SCRIPT = join(
  process.cwd(),
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh'
);

const FIXTURES_DIR = join(process.cwd(), 'scripts/__tests__/fixtures/feat-014');

function fixturePath(name: string): string {
  return join(FIXTURES_DIR, name);
}

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

    it('generates 5 initial feature chain steps', () => {
      const state = runJSON('init FEAT-001 feature');
      const steps = state.steps as Array<Record<string, unknown>>;

      expect(steps).toHaveLength(5);
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

    it('accepts bug chain type', () => {
      const state = runJSON('init BUG-001 bug');
      expect(state.type).toBe('bug');
      expect(state.steps).toHaveLength(7);
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

  describe('chore chain', () => {
    it('generate_chore_steps produces exactly 7 steps with correct names, skills, and contexts', () => {
      const state = runJSON('init CHORE-001 chore');
      const steps = state.steps as Array<Record<string, unknown>>;

      expect(steps).toHaveLength(7);

      const expected = [
        { name: 'Document chore', skill: 'documenting-chores', context: 'main' },
        {
          name: 'Review requirements (standard)',
          skill: 'reviewing-requirements',
          context: 'fork',
        },
        { name: 'Document QA test plan', skill: 'documenting-qa', context: 'main' },
        { name: 'Execute chore', skill: 'executing-chores', context: 'fork' },
        { name: 'PR review', skill: null, context: 'pause' },
        { name: 'Execute QA', skill: 'executing-qa', context: 'main' },
        { name: 'Finalize', skill: 'finalizing-workflow', context: 'fork' },
      ];

      for (let i = 0; i < expected.length; i++) {
        expect(steps[i].name).toBe(expected[i].name);
        expect(steps[i].skill).toBe(expected[i].skill);
        expect(steps[i].context).toBe(expected[i].context);
        expect(steps[i].status).toBe('pending');
        expect(steps[i].artifact).toBeNull();
        expect(steps[i].completedAt).toBeNull();
      }
    });

    it('init CHORE-001 chore creates a valid state file with correct metadata', () => {
      const state = runJSON('init CHORE-001 chore');

      expect(state.id).toBe('CHORE-001');
      expect(state.type).toBe('chore');
      expect(state.currentStep).toBe(0);
      expect(state.status).toBe('in-progress');
      expect(state.pauseReason).toBeNull();
      expect(state.prNumber).toBeNull();
      expect(state.branch).toBeNull();
      expect(state.startedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
      expect(state.lastResumedAt).toBeNull();
      expect(state.phases).toEqual({ total: 0, completed: 0 });
      expect(state.steps).toHaveLength(7);
    });

    it('all state commands work with chore chain state files', () => {
      // init
      runJSON('init CHORE-001 chore');

      // status
      const statusState = runJSON('status CHORE-001');
      expect(statusState.id).toBe('CHORE-001');
      expect(statusState.type).toBe('chore');

      // advance
      const advancedState = runJSON('advance CHORE-001');
      expect(advancedState.currentStep).toBe(1);
      const steps = advancedState.steps as Array<Record<string, unknown>>;
      expect(steps[0].status).toBe('complete');

      // pause
      const pausedState = runJSON('pause CHORE-001 pr-review');
      expect(pausedState.status).toBe('paused');
      expect(pausedState.pauseReason).toBe('pr-review');

      // resume
      const resumedState = runJSON('resume CHORE-001');
      expect(resumedState.status).toBe('in-progress');
      expect(resumedState.pauseReason).toBeNull();

      // fail
      const failedState = runJSON('fail CHORE-001 "test error"');
      expect(failedState.status).toBe('failed');
      expect(failedState.error).toBe('test error');

      // resume from failure
      const recoveredState = runJSON('resume CHORE-001');
      expect(recoveredState.status).toBe('in-progress');
      expect(recoveredState.error).toBeNull();

      // set-pr
      const prState = runJSON('set-pr CHORE-001 55 chore/CHORE-001-test');
      expect(prState.prNumber).toBe(55);
      expect(prState.branch).toBe('chore/CHORE-001-test');

      // complete
      const completedState = runJSON('complete CHORE-001');
      expect(completedState.status).toBe('complete');
      expect(completedState.completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it('idempotency: init on an existing chore state file returns current state', () => {
      runJSON('init CHORE-001 chore');
      // Advance to change state
      run('advance CHORE-001');
      // Re-init should return current state, not overwrite
      const state = runJSON('init CHORE-001 chore');
      expect(state.currentStep).toBe(1);
      expect(state.type).toBe('chore');
    });

    it('CHORE- prefix IDs pass validate_id', () => {
      const state = runJSON('init CHORE-099 chore');
      expect(state.id).toBe('CHORE-099');
    });
  });

  describe('bug chain', () => {
    it('generate_bug_steps produces exactly 7 steps with correct names, skills, and contexts', () => {
      const state = runJSON('init BUG-001 bug');
      const steps = state.steps as Array<Record<string, unknown>>;

      expect(steps).toHaveLength(7);

      const expected = [
        { name: 'Document bug', skill: 'documenting-bugs', context: 'main' },
        {
          name: 'Review requirements (standard)',
          skill: 'reviewing-requirements',
          context: 'fork',
        },
        { name: 'Document QA test plan', skill: 'documenting-qa', context: 'main' },
        { name: 'Execute bug fix', skill: 'executing-bug-fixes', context: 'fork' },
        { name: 'PR review', skill: null, context: 'pause' },
        { name: 'Execute QA', skill: 'executing-qa', context: 'main' },
        { name: 'Finalize', skill: 'finalizing-workflow', context: 'fork' },
      ];

      for (let i = 0; i < expected.length; i++) {
        expect(steps[i].name).toBe(expected[i].name);
        expect(steps[i].skill).toBe(expected[i].skill);
        expect(steps[i].context).toBe(expected[i].context);
        expect(steps[i].status).toBe('pending');
        expect(steps[i].artifact).toBeNull();
        expect(steps[i].completedAt).toBeNull();
      }
    });

    it('init BUG-001 bug creates a valid state file with correct metadata', () => {
      const state = runJSON('init BUG-001 bug');

      expect(state.id).toBe('BUG-001');
      expect(state.type).toBe('bug');
      expect(state.currentStep).toBe(0);
      expect(state.status).toBe('in-progress');
      expect(state.pauseReason).toBeNull();
      expect(state.prNumber).toBeNull();
      expect(state.branch).toBeNull();
      expect(state.startedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
      expect(state.lastResumedAt).toBeNull();
      expect(state.phases).toEqual({ total: 0, completed: 0 });
      expect(state.steps).toHaveLength(7);
    });

    it('all state commands work with bug chain state files', () => {
      // init
      runJSON('init BUG-001 bug');

      // status
      const statusState = runJSON('status BUG-001');
      expect(statusState.id).toBe('BUG-001');
      expect(statusState.type).toBe('bug');

      // advance
      const advancedState = runJSON('advance BUG-001');
      expect(advancedState.currentStep).toBe(1);
      const steps = advancedState.steps as Array<Record<string, unknown>>;
      expect(steps[0].status).toBe('complete');

      // pause
      const pausedState = runJSON('pause BUG-001 pr-review');
      expect(pausedState.status).toBe('paused');
      expect(pausedState.pauseReason).toBe('pr-review');

      // resume
      const resumedState = runJSON('resume BUG-001');
      expect(resumedState.status).toBe('in-progress');
      expect(resumedState.pauseReason).toBeNull();

      // fail
      const failedState = runJSON('fail BUG-001 "test error"');
      expect(failedState.status).toBe('failed');
      expect(failedState.error).toBe('test error');

      // resume from failure
      const recoveredState = runJSON('resume BUG-001');
      expect(recoveredState.status).toBe('in-progress');
      expect(recoveredState.error).toBeNull();

      // set-pr
      const prState = runJSON('set-pr BUG-001 77 fix/BUG-001-test');
      expect(prState.prNumber).toBe(77);
      expect(prState.branch).toBe('fix/BUG-001-test');

      // complete
      const completedState = runJSON('complete BUG-001');
      expect(completedState.status).toBe('complete');
      expect(completedState.completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it('idempotency: init on an existing bug state file returns current state', () => {
      runJSON('init BUG-001 bug');
      // Advance to change state
      run('advance BUG-001');
      // Re-init should return current state, not overwrite
      const state = runJSON('init BUG-001 bug');
      expect(state.currentStep).toBe(1);
      expect(state.type).toBe('bug');
    });

    it('BUG- prefix IDs pass validate_id', () => {
      const state = runJSON('init BUG-099 bug');
      expect(state.id).toBe('BUG-099');
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

    it('sets status to paused with review-findings reason', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('pause FEAT-001 review-findings');
      expect(state.status).toBe('paused');
      expect(state.pauseReason).toBe('review-findings');
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

    it('resumes from review-findings pause and clears pauseReason', () => {
      runJSON('init FEAT-001 feature');
      run('pause FEAT-001 review-findings');
      const state = runJSON('resume FEAT-001');
      expect(state.status).toBe('in-progress');
      expect(state.pauseReason).toBeNull();
      expect(state.lastResumedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it('clears previous error and resets failed step status on resume', () => {
      runJSON('init FEAT-001 feature');
      run('fail FEAT-001 "something broke"');
      const failedState = runJSON('status FEAT-001');
      expect(failedState.error).toBe('something broke');
      const failedSteps = failedState.steps as Array<Record<string, unknown>>;
      expect(failedSteps[0].status).toBe('failed');

      const resumedState = runJSON('resume FEAT-001');
      expect(resumedState.error).toBeNull();
      expect(resumedState.status).toBe('in-progress');
      const resumedSteps = resumedState.steps as Array<Record<string, unknown>>;
      expect(resumedSteps[0].status).toBe('pending');
    });
  });

  describe('set-gate', () => {
    it('sets gate to findings-decision on an in-progress workflow', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('set-gate FEAT-001 findings-decision');
      expect(state.gate).toBe('findings-decision');
      expect(state.status).toBe('in-progress');
    });

    it('rejects invalid gate types', () => {
      runJSON('init FEAT-001 feature');
      const err = run('set-gate FEAT-001 invalid-gate', { expectError: true });
      expect(err).toContain('Invalid gate type');
    });

    it('errors when state file not found', () => {
      const err = run('set-gate FEAT-999 findings-decision', { expectError: true });
      expect(err).toContain('State file not found');
    });

    it('rejects set-gate on a paused workflow', () => {
      runJSON('init FEAT-001 feature');
      run('pause FEAT-001 plan-approval');
      const err = run('set-gate FEAT-001 findings-decision', { expectError: true });
      expect(err).toContain('Cannot set gate on a paused workflow');
    });

    it('rejects set-gate on a failed workflow', () => {
      runJSON('init FEAT-001 feature');
      run('fail FEAT-001 "step broke"');
      const err = run('set-gate FEAT-001 findings-decision', { expectError: true });
      expect(err).toContain('Cannot set gate on a failed workflow');
    });

    it('rejects set-gate on a complete workflow', () => {
      runJSON('init FEAT-001 feature');
      run('complete FEAT-001');
      const err = run('set-gate FEAT-001 findings-decision', { expectError: true });
      expect(err).toContain('Cannot set gate on a complete workflow');
    });
  });

  describe('clear-gate', () => {
    it('clears an active gate back to null', () => {
      runJSON('init FEAT-001 feature');
      run('set-gate FEAT-001 findings-decision');
      const state = runJSON('clear-gate FEAT-001');
      expect(state.gate).toBeNull();
    });

    it('is a no-op when gate is already null', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('clear-gate FEAT-001');
      expect(state.gate).toBeNull();
    });

    it('errors when state file not found', () => {
      const err = run('clear-gate FEAT-999', { expectError: true });
      expect(err).toContain('State file not found');
    });
  });

  describe('gate cleared by state transitions', () => {
    it('advance clears an active gate', () => {
      runJSON('init FEAT-001 feature');
      run('set-gate FEAT-001 findings-decision');
      const state = runJSON('advance FEAT-001');
      expect(state.gate).toBeNull();
    });

    it('pause clears an active gate', () => {
      runJSON('init FEAT-001 feature');
      run('set-gate FEAT-001 findings-decision');
      const state = runJSON('pause FEAT-001 review-findings');
      expect(state.gate).toBeNull();
    });

    it('resume clears an active gate', () => {
      runJSON('init FEAT-001 feature');
      run('pause FEAT-001 review-findings');
      // Manually set gate on the state file to simulate an abnormal state
      run('resume FEAT-001');
      run('set-gate FEAT-001 findings-decision');
      const state = runJSON('resume FEAT-001');
      expect(state.gate).toBeNull();
    });

    it('fail clears an active gate', () => {
      runJSON('init FEAT-001 feature');
      run('set-gate FEAT-001 findings-decision');
      const state = runJSON('fail FEAT-001 "step broke"');
      expect(state.gate).toBeNull();
      expect(state.status).toBe('failed');
    });
  });

  describe('init includes gate field', () => {
    it('new workflow state includes gate: null', () => {
      const state = runJSON('init FEAT-001 feature');
      expect(Object.prototype.hasOwnProperty.call(state, 'gate')).toBe(true);
      expect(state.gate).toBeNull();
    });

    it('new chore workflow includes gate: null', () => {
      const state = runJSON('init CHORE-001 chore');
      expect(Object.prototype.hasOwnProperty.call(state, 'gate')).toBe(true);
      expect(state.gate).toBeNull();
    });

    it('new bug workflow includes gate: null', () => {
      const state = runJSON('init BUG-001 bug');
      expect(Object.prototype.hasOwnProperty.call(state, 'gate')).toBe(true);
      expect(state.gate).toBeNull();
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
    it('inserts phase steps and post-phase steps after initial 5', () => {
      runJSON('init FEAT-001 feature');
      const state = runJSON('populate-phases FEAT-001 3');

      const steps = state.steps as Array<Record<string, unknown>>;
      // 5 initial + 3 phase + 4 post-phase = 12
      expect(steps).toHaveLength(12);

      // Phase steps at indices 5, 6, 7
      expect(steps[5].name).toBe('Implement phase 1 of 3');
      expect(steps[5].phaseNumber).toBe(1);
      expect(steps[6].name).toBe('Implement phase 2 of 3');
      expect(steps[6].phaseNumber).toBe(2);
      expect(steps[7].name).toBe('Implement phase 3 of 3');
      expect(steps[7].phaseNumber).toBe(3);

      // Post-phase steps at indices 8-11
      expect(steps[8].name).toBe('Create PR');
      expect(steps[9].name).toBe('PR review');
      expect(steps[10].name).toBe('Execute QA');
      expect(steps[11].name).toBe('Finalize');
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
      // Should still have 12 steps (3 phases), not 14 (5 phases)
      expect(steps).toHaveLength(12);
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

  describe('model selection (FEAT-014)', () => {
    describe('init defaults', () => {
      it('writes complexity, complexityStage, modelOverride, and modelSelections on fresh init', () => {
        const state = runJSON('init FEAT-001 feature');
        expect(state.complexity).toBeNull();
        expect(state.complexityStage).toBe('init');
        expect(state.modelOverride).toBeNull();
        expect(state.modelSelections).toEqual([]);
      });

      it('includes all four model-selection fields on chore init', () => {
        const state = runJSON('init CHORE-001 chore');
        expect(state).toHaveProperty('complexity', null);
        expect(state).toHaveProperty('complexityStage', 'init');
        expect(state).toHaveProperty('modelOverride', null);
        expect(state).toHaveProperty('modelSelections');
        expect(state.modelSelections).toEqual([]);
      });

      it('includes all four model-selection fields on bug init', () => {
        const state = runJSON('init BUG-001 bug');
        expect(state).toHaveProperty('complexity', null);
        expect(state).toHaveProperty('complexityStage', 'init');
        expect(state).toHaveProperty('modelOverride', null);
        expect(state).toHaveProperty('modelSelections');
      });
    });

    describe('migration (FR-13)', () => {
      // Helper to write a pre-FEAT-014 state file (lacking the four new fields).
      function writeLegacyState(id: string): void {
        mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
        const legacy = {
          id,
          type: 'feature',
          currentStep: 2,
          status: 'in-progress',
          pauseReason: null,
          steps: [
            {
              name: 'Document feature requirements',
              skill: 'documenting-features',
              context: 'main',
              status: 'complete',
              artifact: 'requirements/features/FEAT-050.md',
              completedAt: '2026-04-01T00:00:00Z',
            },
            {
              name: 'Review requirements (standard)',
              skill: 'reviewing-requirements',
              context: 'fork',
              status: 'complete',
              artifact: null,
              completedAt: '2026-04-01T00:05:00Z',
            },
            {
              name: 'Create implementation plan',
              skill: 'creating-implementation-plans',
              context: 'fork',
              status: 'pending',
              artifact: null,
              completedAt: null,
            },
          ],
          phases: { total: 0, completed: 0 },
          prNumber: null,
          branch: null,
          startedAt: '2026-04-01T00:00:00Z',
          lastResumedAt: null,
        };
        writeFileSync(join(testDir, '.sdlc/workflows', `${id}.json`), JSON.stringify(legacy));
      }

      it('adds missing complexity/complexityStage/modelOverride/modelSelections without clobbering existing data', () => {
        writeLegacyState('FEAT-050');
        const state = runJSON('status FEAT-050');

        // New fields populated with init defaults.
        expect(state.complexity).toBeNull();
        expect(state.complexityStage).toBe('init');
        expect(state.modelOverride).toBeNull();
        expect(state.modelSelections).toEqual([]);

        // Existing data preserved.
        expect(state.currentStep).toBe(2);
        expect(state.status).toBe('in-progress');
        const steps = state.steps as Array<Record<string, unknown>>;
        expect(steps).toHaveLength(3);
        expect(steps[0].status).toBe('complete');
        expect(steps[0].artifact).toBe('requirements/features/FEAT-050.md');
        expect(steps[1].status).toBe('complete');
        expect(steps[2].status).toBe('pending');
      });

      it('migration persists to disk so subsequent reads are already-migrated', () => {
        writeLegacyState('FEAT-051');
        // First read triggers migration.
        runJSON('status FEAT-051');
        // Second read should see already-migrated file (no double-migration, no data loss).
        const state = readState('FEAT-051');
        expect(state.complexity).toBeNull();
        expect(state.complexityStage).toBe('init');
        expect(state.modelOverride).toBeNull();
        expect(state.modelSelections).toEqual([]);
        expect(state.currentStep).toBe(2);
      });

      it('migration does not overwrite a partially-populated complexity value', () => {
        mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
        // Partial legacy file: has complexity but missing the rest.
        const partial = {
          id: 'FEAT-052',
          type: 'feature',
          currentStep: 0,
          status: 'in-progress',
          pauseReason: null,
          steps: [
            {
              name: 'Document feature requirements',
              skill: 'documenting-features',
              context: 'main',
              status: 'pending',
              artifact: null,
              completedAt: null,
            },
          ],
          phases: { total: 0, completed: 0 },
          prNumber: null,
          branch: null,
          startedAt: '2026-04-01T00:00:00Z',
          lastResumedAt: null,
          complexity: 'high',
        };
        writeFileSync(join(testDir, '.sdlc/workflows/FEAT-052.json'), JSON.stringify(partial));

        const state = runJSON('status FEAT-052');
        expect(state.complexity).toBe('high'); // preserved
        expect(state.complexityStage).toBe('init'); // added
        expect(state.modelOverride).toBeNull(); // added
        expect(state.modelSelections).toEqual([]); // added
      });
    });

    describe('set-complexity', () => {
      it('writes complexity value and round-trips through status', () => {
        runJSON('init FEAT-001 feature');
        const state = runJSON('set-complexity FEAT-001 high');
        expect(state.complexity).toBe('high');

        const rereadState = runJSON('status FEAT-001');
        expect(rereadState.complexity).toBe('high');
      });

      it('accepts low, medium, and high tiers', () => {
        runJSON('init FEAT-001 feature');

        const lowState = runJSON('set-complexity FEAT-001 low');
        expect(lowState.complexity).toBe('low');

        const medState = runJSON('set-complexity FEAT-001 medium');
        expect(medState.complexity).toBe('medium');

        const highState = runJSON('set-complexity FEAT-001 high');
        expect(highState.complexity).toBe('high');
      });

      it('leaves complexityStage untouched (manual override is not a stage transition)', () => {
        runJSON('init FEAT-001 feature');
        const state = runJSON('set-complexity FEAT-001 high');
        expect(state.complexityStage).toBe('init');
      });

      it('rejects invalid tier values with non-zero exit code', () => {
        runJSON('init FEAT-001 feature');
        const err = run('set-complexity FEAT-001 huge', { expectError: true });
        expect(err).toContain('Invalid complexity tier');
      });

      it('rejects empty tier', () => {
        runJSON('init FEAT-001 feature');
        const err = run('set-complexity FEAT-001', { expectError: true });
        expect(err).toContain('set-complexity requires');
      });

      it('does not clobber modelOverride when setting complexity', () => {
        runJSON('init FEAT-001 feature');
        // Manually set modelOverride via direct file edit (set-complexity should not touch it).
        const stateFile = join(testDir, '.sdlc/workflows/FEAT-001.json');
        const raw = JSON.parse(readFileSync(stateFile, 'utf-8'));
        raw.modelOverride = 'opus';
        writeFileSync(stateFile, JSON.stringify(raw));

        const state = runJSON('set-complexity FEAT-001 low');
        expect(state.complexity).toBe('low');
        expect(state.modelOverride).toBe('opus');
      });
    });

    describe('get-model', () => {
      it('returns the step baseline floor when complexity is null', () => {
        runJSON('init FEAT-001 feature');
        // Sonnet-baseline steps
        expect(run('get-model FEAT-001 reviewing-requirements')).toBe('sonnet');
        expect(run('get-model FEAT-001 creating-implementation-plans')).toBe('sonnet');
        expect(run('get-model FEAT-001 implementing-plan-phases')).toBe('sonnet');
        expect(run('get-model FEAT-001 executing-chores')).toBe('sonnet');
        expect(run('get-model FEAT-001 executing-bug-fixes')).toBe('sonnet');
        // Baseline-locked steps
        expect(run('get-model FEAT-001 finalizing-workflow')).toBe('haiku');
        expect(run('get-model FEAT-001 pr-creation')).toBe('haiku');
      });

      it('honours complexity upgrade for non-baseline-locked steps', () => {
        runJSON('init FEAT-001 feature');
        runJSON('set-complexity FEAT-001 high');
        // max(sonnet, opus) = opus
        expect(run('get-model FEAT-001 reviewing-requirements')).toBe('opus');
        expect(run('get-model FEAT-001 implementing-plan-phases')).toBe('opus');
      });

      it('does not downgrade below baseline when complexity is low', () => {
        runJSON('init FEAT-001 feature');
        runJSON('set-complexity FEAT-001 low');
        // max(sonnet, haiku) = sonnet — Sonnet baseline floor protects us.
        expect(run('get-model FEAT-001 reviewing-requirements')).toBe('sonnet');
        expect(run('get-model FEAT-001 implementing-plan-phases')).toBe('sonnet');
      });

      it('returns medium→sonnet complexity as a no-op upgrade on sonnet-baseline steps', () => {
        runJSON('init FEAT-001 feature');
        runJSON('set-complexity FEAT-001 medium');
        expect(run('get-model FEAT-001 reviewing-requirements')).toBe('sonnet');
      });

      it('baseline-locked steps ignore complexity upgrades', () => {
        runJSON('init FEAT-001 feature');
        runJSON('set-complexity FEAT-001 high');
        expect(run('get-model FEAT-001 finalizing-workflow')).toBe('haiku');
        expect(run('get-model FEAT-001 pr-creation')).toBe('haiku');
      });

      it('modelOverride is soft and upgrade-only — cannot downgrade below computed tier', () => {
        runJSON('init FEAT-001 feature');
        runJSON('set-complexity FEAT-001 high');
        // Manually set modelOverride = sonnet (soft-override, FR-5 #4).
        const stateFile = join(testDir, '.sdlc/workflows/FEAT-001.json');
        const raw = JSON.parse(readFileSync(stateFile, 'utf-8'));
        raw.modelOverride = 'sonnet';
        writeFileSync(stateFile, JSON.stringify(raw));
        // FR-5 #4: upgrade-only. complexity=high → opus, soft override=sonnet
        // is LOWER, so max(opus, sonnet) = opus. Override cannot downgrade.
        expect(run('get-model FEAT-001 reviewing-requirements')).toBe('opus');
      });

      it('modelOverride upgrades non-locked steps when higher than computed tier', () => {
        runJSON('init FEAT-001 feature');
        runJSON('set-complexity FEAT-001 low');
        // complexity=low → haiku, baseline=sonnet, so computed = sonnet.
        // Set modelOverride = opus — soft upgrade above the computed tier.
        const stateFile = join(testDir, '.sdlc/workflows/FEAT-001.json');
        const raw = JSON.parse(readFileSync(stateFile, 'utf-8'));
        raw.modelOverride = 'opus';
        writeFileSync(stateFile, JSON.stringify(raw));
        // max(sonnet, opus) = opus.
        expect(run('get-model FEAT-001 reviewing-requirements')).toBe('opus');
      });

      it('get-model and resolve-tier agree on identical inputs (no divergence)', () => {
        // Regression guard for the FR-5 #4 violation fixed after code review:
        // both resolvers must return the same tier when given the same state
        // and no CLI-flag overrides. cmd_get_model is a flag-less wrapper
        // around cmd_resolve_tier, so any future divergence is a bug.
        runJSON('init FEAT-001 feature');
        runJSON('set-complexity FEAT-001 high');
        const stateFile = join(testDir, '.sdlc/workflows/FEAT-001.json');
        const raw = JSON.parse(readFileSync(stateFile, 'utf-8'));
        raw.modelOverride = 'sonnet';
        writeFileSync(stateFile, JSON.stringify(raw));

        const steps = [
          'reviewing-requirements',
          'creating-implementation-plans',
          'implementing-plan-phases',
          'executing-chores',
          'executing-bug-fixes',
          'finalizing-workflow',
          'pr-creation',
        ];
        for (const step of steps) {
          const getModel = run(`get-model FEAT-001 ${step}`);
          const resolveTier = run(`resolve-tier FEAT-001 ${step}`);
          expect(getModel).toBe(resolveTier);
        }
      });

      it('baseline-locked steps ignore modelOverride (soft override)', () => {
        runJSON('init FEAT-001 feature');
        const stateFile = join(testDir, '.sdlc/workflows/FEAT-001.json');
        const raw = JSON.parse(readFileSync(stateFile, 'utf-8'));
        raw.modelOverride = 'opus';
        writeFileSync(stateFile, JSON.stringify(raw));
        expect(run('get-model FEAT-001 finalizing-workflow')).toBe('haiku');
        expect(run('get-model FEAT-001 pr-creation')).toBe('haiku');
      });

      it('unknown step names default to sonnet (safe floor)', () => {
        runJSON('init FEAT-001 feature');
        expect(run('get-model FEAT-001 totally-made-up-skill')).toBe('sonnet');
      });

      it('errors when state file does not exist', () => {
        const err = run('get-model FEAT-999 reviewing-requirements', { expectError: true });
        expect(err).toContain('State file not found');
      });
    });

    describe('record-model-selection', () => {
      it('appends the first entry to modelSelections', () => {
        runJSON('init FEAT-001 feature');
        const state = runJSON(
          'record-model-selection FEAT-001 1 reviewing-requirements standard null sonnet init 2026-04-11T00:00:00Z'
        );
        const selections = state.modelSelections as Array<Record<string, unknown>>;
        expect(selections).toHaveLength(1);
        expect(selections[0]).toEqual({
          stepIndex: 1,
          skill: 'reviewing-requirements',
          mode: 'standard',
          phase: null,
          tier: 'sonnet',
          complexityStage: 'init',
          startedAt: '2026-04-11T00:00:00Z',
        });
      });

      it('appends subsequent entries without overwriting earlier ones', () => {
        runJSON('init FEAT-001 feature');
        runJSON(
          'record-model-selection FEAT-001 1 reviewing-requirements standard null sonnet init 2026-04-11T00:00:00Z'
        );
        runJSON(
          'record-model-selection FEAT-001 2 creating-implementation-plans null null opus init 2026-04-11T00:05:00Z'
        );
        const state = runJSON(
          'record-model-selection FEAT-001 3 implementing-plan-phases null 1 opus post-plan 2026-04-11T00:10:00Z'
        );
        const selections = state.modelSelections as Array<Record<string, unknown>>;
        expect(selections).toHaveLength(3);
        expect(selections[0].skill).toBe('reviewing-requirements');
        expect(selections[0].tier).toBe('sonnet');
        expect(selections[1].skill).toBe('creating-implementation-plans');
        expect(selections[1].tier).toBe('opus');
        expect(selections[1].complexityStage).toBe('init');
        expect(selections[2].skill).toBe('implementing-plan-phases');
        expect(selections[2].phase).toBe(1);
        expect(selections[2].complexityStage).toBe('post-plan');
      });

      it('supports null mode and null phase via "null" literal', () => {
        runJSON('init FEAT-001 feature');
        const state = runJSON(
          'record-model-selection FEAT-001 5 finalizing-workflow null null haiku init 2026-04-11T01:00:00Z'
        );
        const selections = state.modelSelections as Array<Record<string, unknown>>;
        expect(selections[0].mode).toBeNull();
        expect(selections[0].phase).toBeNull();
      });

      it('preserves existing modelSelections when appending after a migration', () => {
        // Write a legacy state file, then append without clobbering.
        mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
        const legacy = {
          id: 'FEAT-060',
          type: 'feature',
          currentStep: 0,
          status: 'in-progress',
          pauseReason: null,
          steps: [
            {
              name: 'Document feature requirements',
              skill: 'documenting-features',
              context: 'main',
              status: 'pending',
              artifact: null,
              completedAt: null,
            },
          ],
          phases: { total: 0, completed: 0 },
          prNumber: null,
          branch: null,
          startedAt: '2026-04-01T00:00:00Z',
          lastResumedAt: null,
        };
        writeFileSync(join(testDir, '.sdlc/workflows/FEAT-060.json'), JSON.stringify(legacy));

        const state = runJSON(
          'record-model-selection FEAT-060 0 documenting-features null null sonnet init 2026-04-11T00:00:00Z'
        );
        const selections = state.modelSelections as Array<Record<string, unknown>>;
        expect(selections).toHaveLength(1);
        expect(selections[0].skill).toBe('documenting-features');
      });

      it('errors when missing arguments', () => {
        runJSON('init FEAT-001 feature');
        const err = run('record-model-selection FEAT-001 1 reviewing-requirements', {
          expectError: true,
        });
        expect(err).toContain('record-model-selection requires');
      });

      it('rejects non-numeric stepIndex with a clear error (not a cryptic jq failure)', () => {
        runJSON('init FEAT-001 feature');
        const err = run(
          'record-model-selection FEAT-001 notanumber reviewing-requirements standard null sonnet init 2026-04-11T00:00:00Z',
          { expectError: true }
        );
        expect(err).toContain('requires a numeric');
      });

      it('rejects empty stepIndex with a clear error', () => {
        runJSON('init FEAT-001 feature');
        const err = run(
          'record-model-selection FEAT-001 "" reviewing-requirements standard null sonnet init 2026-04-11T00:00:00Z',
          { expectError: true }
        );
        expect(err).toContain('requires a numeric');
      });
    });

    describe('record-findings', () => {
      it('writes the correct JSON structure for a valid stepIndex', () => {
        runJSON('init FEAT-001 feature');
        const state = runJSON('record-findings FEAT-001 1 3 2 1 advanced "No issues found"');
        const steps = state.steps as Array<Record<string, unknown>>;
        expect(steps[1].findings).toEqual({
          errors: 3,
          warnings: 2,
          info: 1,
          decision: 'advanced',
          summary: 'No issues found',
        });
        // Numeric fields are numbers, not strings.
        const findings = steps[1].findings as Record<string, unknown>;
        expect(typeof findings.errors).toBe('number');
        expect(typeof findings.warnings).toBe('number');
        expect(typeof findings.info).toBe('number');
      });

      it('--rerun writes to rerunFindings without overwriting an existing findings field', () => {
        runJSON('init FEAT-001 feature');
        runJSON('record-findings FEAT-001 1 0 2 1 auto-advanced "Warnings found"');
        const state = runJSON('record-findings FEAT-001 1 0 0 0 advanced "Clean on rerun" --rerun');
        const steps = state.steps as Array<Record<string, unknown>>;
        // Original findings must be preserved.
        expect(steps[1].findings).toMatchObject({ decision: 'auto-advanced' });
        // rerunFindings must be written.
        expect(steps[1].rerunFindings).toMatchObject({
          decision: 'advanced',
          summary: 'Clean on rerun',
        });
      });

      it('stores a summary containing shell-special characters verbatim', () => {
        runJSON('init FEAT-001 feature');
        const specialSummary = 'Found: $HOME `echo hi` (parens) "quotes" \'single\'';
        // Pass the summary as a single shell-quoted argument via execSync.
        const state = JSON.parse(
          execSync(
            `bash "${SCRIPT}" record-findings FEAT-001 1 0 1 0 paused '${specialSummary.replace(/'/g, "'\\''")}'`,
            { cwd: testDir, encoding: 'utf-8' }
          )
        ) as Record<string, unknown>;
        const steps = state.steps as Array<Record<string, unknown>>;
        const findings = steps[1].findings as Record<string, unknown>;
        expect(findings.summary).toBe(specialSummary);
      });

      it('--details-file with decision "auto-advanced" includes the details array', () => {
        runJSON('init FEAT-001 feature');
        const detailsFile = join(testDir, 'details.json');
        const detailsArray = [
          { id: 'W1', severity: 'warning', category: 'Style', description: 'Missing semicolon' },
          { id: 'I1', severity: 'info', category: 'Docs', description: 'Consider adding example' },
        ];
        writeFileSync(detailsFile, JSON.stringify(detailsArray));
        const state = runJSON(
          `record-findings FEAT-001 1 0 1 1 auto-advanced "Warnings only" --details-file ${detailsFile}`
        );
        const steps = state.steps as Array<Record<string, unknown>>;
        const findings = steps[1].findings as Record<string, unknown>;
        expect(findings.decision).toBe('auto-advanced');
        expect(Array.isArray(findings.details)).toBe(true);
        expect(findings.details).toEqual(detailsArray);
      });

      it('--details-file with a non-auto-advanced decision omits details from the written object', () => {
        runJSON('init FEAT-001 feature');
        const detailsFile = join(testDir, 'details.json');
        writeFileSync(
          detailsFile,
          JSON.stringify([{ id: 'W1', severity: 'warning', category: 'Style', description: 'x' }])
        );
        const state = runJSON(
          `record-findings FEAT-001 1 0 1 0 user-advanced "User confirmed" --details-file ${detailsFile}`
        );
        const steps = state.steps as Array<Record<string, unknown>>;
        const findings = steps[1].findings as Record<string, unknown>;
        expect(findings.decision).toBe('user-advanced');
        expect(Object.prototype.hasOwnProperty.call(findings, 'details')).toBe(false);
      });

      it('--details-file pointing to invalid JSON logs warning and writes without details', () => {
        runJSON('init FEAT-001 feature');
        const badFile = join(testDir, 'bad.json');
        writeFileSync(badFile, 'not valid json {{');
        // Should succeed (exit 0) but log warning to stderr.
        const output = execSync(
          `bash "${SCRIPT}" record-findings FEAT-001 1 0 1 0 auto-advanced "Warnings" --details-file ${badFile} 2>&1`,
          { cwd: testDir, encoding: 'utf-8' }
        );
        // Should contain the warning on stderr (merged into stdout via 2>&1).
        expect(output).toContain('[warn] Could not read details file');
        // State file must still be updated without details.
        const stateAfter = readState('FEAT-001');
        const steps = stateAfter.steps as Array<Record<string, unknown>>;
        const findings = steps[1].findings as Record<string, unknown>;
        expect(findings.decision).toBe('auto-advanced');
        expect(Object.prototype.hasOwnProperty.call(findings, 'details')).toBe(false);
      });

      it('--details-file pointing to a non-existent file logs warning and writes without details', () => {
        runJSON('init FEAT-001 feature');
        const missingFile = join(testDir, 'missing.json');
        const output = execSync(
          `bash "${SCRIPT}" record-findings FEAT-001 1 0 1 0 auto-advanced "Warnings" --details-file ${missingFile} 2>&1 || true`,
          { cwd: testDir, encoding: 'utf-8', shell: '/bin/bash' }
        );
        // Should contain the warning.
        expect(output).toContain('[warn] Could not read details file');
        // State file must still be updated without details.
        const stateAfter = readState('FEAT-001');
        const steps = stateAfter.steps as Array<Record<string, unknown>>;
        const findings = steps[1].findings as Record<string, unknown>;
        expect(findings.decision).toBe('auto-advanced');
        expect(Object.prototype.hasOwnProperty.call(findings, 'details')).toBe(false);
      });

      it('stepIndex equal to steps.length (out of bounds) exits non-zero and does not modify the state file', () => {
        runJSON('init FEAT-001 feature');
        // Feature workflow has 6 initial steps; index 6 is out of bounds.
        const before = readState('FEAT-001');
        const err = run('record-findings FEAT-001 6 0 0 0 advanced "test"', { expectError: true });
        expect(err).toContain('out of bounds');
        const after = readState('FEAT-001');
        expect(JSON.stringify(after)).toBe(JSON.stringify(before));
      });

      it('status subcommand returns findings data when present and works normally when absent', () => {
        runJSON('init FEAT-001 feature');
        // Without findings: status should work normally.
        const stateWithout = runJSON('status FEAT-001');
        const stepsWithout = stateWithout.steps as Array<Record<string, unknown>>;
        expect(Object.prototype.hasOwnProperty.call(stepsWithout[1], 'findings')).toBe(false);

        // After recording findings: status should include the findings field.
        runJSON('record-findings FEAT-001 1 0 0 0 advanced "No issues found"');
        const stateWith = runJSON('status FEAT-001');
        const stepsWith = stateWith.steps as Array<Record<string, unknown>>;
        expect(Object.prototype.hasOwnProperty.call(stepsWith[1], 'findings')).toBe(true);
        const findings = stepsWith[1].findings as Record<string, unknown>;
        expect(findings.decision).toBe('advanced');
      });
    });

    describe('classifier (FEAT-014 Phase 2)', () => {
      // --- chore signal extractor tests ---
      describe('chore classifier', () => {
        it('buckets 3 ACs as low (≤3)', () => {
          runJSON('init CHORE-001 chore');
          expect(run(`classify-init CHORE-001 ${fixturePath('chore-low.md')}`)).toBe('low');
        });

        it('buckets 4 ACs as medium (first item in 4–8)', () => {
          runJSON('init CHORE-001 chore');
          expect(run(`classify-init CHORE-001 ${fixturePath('chore-boundary-4.md')}`)).toBe(
            'medium'
          );
        });

        it('buckets 5 ACs as medium', () => {
          runJSON('init CHORE-001 chore');
          expect(run(`classify-init CHORE-001 ${fixturePath('chore-medium.md')}`)).toBe('medium');
        });

        it('buckets 8 ACs as medium (last item in 4–8)', () => {
          runJSON('init CHORE-001 chore');
          expect(run(`classify-init CHORE-001 ${fixturePath('chore-boundary-8.md')}`)).toBe(
            'medium'
          );
        });

        it('buckets 9 ACs as high (first item in 9+)', () => {
          runJSON('init CHORE-001 chore');
          expect(run(`classify-init CHORE-001 ${fixturePath('chore-boundary-9.md')}`)).toBe('high');
        });

        it('buckets 10 ACs as high', () => {
          runJSON('init CHORE-001 chore');
          expect(run(`classify-init CHORE-001 ${fixturePath('chore-high.md')}`)).toBe('high');
        });
      });

      // --- bug signal extractor tests ---
      describe('bug classifier', () => {
        it('low severity + 1 RC + logic-error → low', () => {
          runJSON('init BUG-001 bug');
          expect(run(`classify-init BUG-001 ${fixturePath('bug-low.md')}`)).toBe('low');
        });

        it('medium severity + 2 RCs + logic-error → medium', () => {
          runJSON('init BUG-001 bug');
          expect(run(`classify-init BUG-001 ${fixturePath('bug-medium.md')}`)).toBe('medium');
        });

        it('high severity + 3 RCs + security category → high (bump ceils)', () => {
          runJSON('init BUG-001 bug');
          expect(run(`classify-init BUG-001 ${fixturePath('bug-high.md')}`)).toBe('high');
        });

        it('critical severity alone caps at medium (CHORE-031 T1)', () => {
          runJSON('init BUG-001 bug');
          expect(run(`classify-init BUG-001 ${fixturePath('bug-critical-severity.md')}`)).toBe(
            'medium'
          );
        });

        it('performance category bumps low base → medium', () => {
          runJSON('init BUG-001 bug');
          expect(run(`classify-init BUG-001 ${fixturePath('bug-perf-bump.md')}`)).toBe('medium');
        });

        it('RC count 4 alone caps at medium when severity is low (CHORE-031 T1)', () => {
          runJSON('init BUG-001 bug');
          expect(run(`classify-init BUG-001 ${fixturePath('bug-max-severity-rc.md')}`)).toBe(
            'medium'
          );
        });

        it('high severity + 4 RCs + logic-error → high via rc_tier branch (CHORE-031 T1)', () => {
          runJSON('init BUG-001 bug');
          expect(run(`classify-init BUG-001 ${fixturePath('bug-high-rc-only.md')}`)).toBe('high');
        });
      });

      // --- feature init-stage extractor tests ---
      describe('feature init classifier', () => {
        it('3 FRs, no NFR bump → low', () => {
          runJSON('init FEAT-001 feature');
          expect(run(`classify-init FEAT-001 ${fixturePath('feature-low.md')}`)).toBe('low');
        });

        it('8 FRs, no NFR bump → medium', () => {
          runJSON('init FEAT-001 feature');
          expect(run(`classify-init FEAT-001 ${fixturePath('feature-medium-no-bump.md')}`)).toBe(
            'medium'
          );
        });

        it('8 FRs with perf NFR → bumped to high', () => {
          runJSON('init FEAT-001 feature');
          expect(run(`classify-init FEAT-001 ${fixturePath('feature-medium.md')}`)).toBe('high');
        });

        it('14 FRs with security NFR → high (bump ceils)', () => {
          runJSON('init FEAT-001 feature');
          expect(run(`classify-init FEAT-001 ${fixturePath('feature-high.md')}`)).toBe('high');
        });

        it('NFR section with benign "author"/"performer" text does NOT trigger a bump', () => {
          // Code review Issue 3: _check_security_auth_perf used substring
          // matching, so "author metadata", "performer", and similar false
          // positives incorrectly bumped the tier. Word-boundary matching
          // must reject these.
          runJSON('init FEAT-901 feature');
          // feature-nfr-false-positive.md has 2 FRs → low bucket. Without
          // the bump, classifier returns "low". If the substring bug were
          // still present, it would bump to "medium".
          expect(
            run(`classify-init FEAT-901 ${fixturePath('feature-nfr-false-positive.md')}`)
          ).toBe('low');
        });

        it('keywords inside fenced code blocks in NFR prose do NOT trigger a bump', () => {
          // Code review Issue 3: fenced YAML/JSON examples inside the NFR
          // section were counted as real signal. The fence-aware extractor
          // must skip content between ``` markers.
          runJSON('init FEAT-902 feature');
          // feature-nfr-fenced-code.md has 2 FRs → low bucket. The NFR
          // section only mentions security/auth/perf INSIDE a fenced YAML
          // example; the prose itself is benign. Expected: low.
          expect(run(`classify-init FEAT-902 ${fixturePath('feature-nfr-fenced-code.md')}`)).toBe(
            'low'
          );
        });
      });

      // --- feature post-plan upgrade tests ---
      describe('feature post-plan upgrade', () => {
        it('init medium + 4 phases → upgraded to high (sonnet → opus)', () => {
          runJSON('init FEAT-001 feature');
          runJSON('set-complexity FEAT-001 medium');
          expect(
            run(`classify-post-plan FEAT-001 ${fixturePath('feature-low-plan-4phase.md')}`)
          ).toBe('high');
        });

        it('init high + 1 phase → stays high (upgrade-only, never downgrade)', () => {
          runJSON('init FEAT-001 feature');
          runJSON('set-complexity FEAT-001 high');
          expect(
            run(`classify-post-plan FEAT-001 ${fixturePath('feature-low-plan-1phase.md')}`)
          ).toBe('high');
        });

        it('init low + 4 phases → upgraded to high', () => {
          runJSON('init FEAT-001 feature');
          runJSON('set-complexity FEAT-001 low');
          expect(
            run(`classify-post-plan FEAT-001 ${fixturePath('feature-low-plan-4phase.md')}`)
          ).toBe('high');
        });

        it('init medium + 1 phase → stays medium (low ≤ medium)', () => {
          runJSON('init FEAT-001 feature');
          runJSON('set-complexity FEAT-001 medium');
          expect(
            run(`classify-post-plan FEAT-001 ${fixturePath('feature-low-plan-1phase.md')}`)
          ).toBe('medium');
        });

        it('missing plan → retain persisted tier (NFR-5)', () => {
          runJSON('init FEAT-001 feature');
          runJSON('set-complexity FEAT-001 medium');
          expect(run('classify-post-plan FEAT-001 /nonexistent/plan.md')).toBe('medium');
        });

        it('rejects non-feature chains', () => {
          runJSON('init CHORE-001 chore');
          const err = run('classify-post-plan CHORE-001', { expectError: true });
          expect(err).toContain('only valid for feature chains');
        });
      });

      // --- unparseable / fallback tests (FR-10) ---
      describe('unparseable signal fallback (FR-10)', () => {
        it('empty doc on chore chain → medium (sonnet, never opus)', () => {
          runJSON('init CHORE-001 chore');
          expect(run(`classify-init CHORE-001 ${fixturePath('empty-doc.md')}`)).toBe('medium');
        });

        it('empty doc on bug chain → medium (sonnet, never opus)', () => {
          runJSON('init BUG-001 bug');
          expect(run(`classify-init BUG-001 ${fixturePath('empty-doc.md')}`)).toBe('medium');
        });

        it('empty doc on feature chain → medium (sonnet, never opus)', () => {
          runJSON('init FEAT-001 feature');
          expect(run(`classify-init FEAT-001 ${fixturePath('empty-doc.md')}`)).toBe('medium');
        });

        it('missing doc path on feature chain → medium (sonnet, never opus)', () => {
          runJSON('init FEAT-001 feature');
          expect(run('classify-init FEAT-001 /nonexistent/doc.md')).toBe('medium');
        });

        it('falls back to medium, NEVER to opus', () => {
          runJSON('init FEAT-001 feature');
          // Explicitly verify no path produces 'high' (which would map to opus).
          const emptyResult = run(`classify-init FEAT-001 ${fixturePath('empty-doc.md')}`);
          expect(emptyResult).not.toBe('high');
          expect(emptyResult).toBe('medium');
        });
      });

      // --- FR-3 override precedence chain (resolve-tier) tests ---
      describe('resolve-tier FR-3 precedence chain', () => {
        it('default: baseline floor when no complexity and no overrides', () => {
          runJSON('init FEAT-001 feature');
          expect(run('resolve-tier FEAT-001 reviewing-requirements')).toBe('sonnet');
          expect(run('resolve-tier FEAT-001 creating-implementation-plans')).toBe('sonnet');
          expect(run('resolve-tier FEAT-001 implementing-plan-phases')).toBe('sonnet');
        });

        it('baseline-locked steps default to haiku', () => {
          runJSON('init FEAT-001 feature');
          expect(run('resolve-tier FEAT-001 finalizing-workflow')).toBe('haiku');
          expect(run('resolve-tier FEAT-001 pr-creation')).toBe('haiku');
        });

        it('work-item complexity high upgrades non-locked step to opus', () => {
          runJSON('init FEAT-001 feature');
          runJSON('set-complexity FEAT-001 high');
          expect(run('resolve-tier FEAT-001 reviewing-requirements')).toBe('opus');
          expect(run('resolve-tier FEAT-001 implementing-plan-phases')).toBe('opus');
        });

        it('baseline-locked step ignores work-item complexity high', () => {
          runJSON('init FEAT-001 feature');
          runJSON('set-complexity FEAT-001 high');
          expect(run('resolve-tier FEAT-001 finalizing-workflow')).toBe('haiku');
          expect(run('resolve-tier FEAT-001 pr-creation')).toBe('haiku');
        });

        it('baseline floor is sonnet for reviewing-requirements even when wi-complexity=low', () => {
          runJSON('init FEAT-001 feature');
          runJSON('set-complexity FEAT-001 low');
          // max(sonnet-baseline, haiku-from-low) = sonnet
          expect(run('resolve-tier FEAT-001 reviewing-requirements')).toBe('sonnet');
        });

        // --- Hard overrides (FR-5 #1 and #2) ---
        it('hard --cli-model haiku REPLACES tier — downgrades below sonnet baseline', () => {
          runJSON('init FEAT-001 feature');
          // Feature chain in main: sonnet baseline. Hard haiku must win.
          expect(run('resolve-tier FEAT-001 reviewing-requirements --cli-model haiku')).toBe(
            'haiku'
          );
        });

        it('hard --cli-model opus BYPASSES baseline lock on finalizing-workflow', () => {
          runJSON('init FEAT-001 feature');
          expect(run('resolve-tier FEAT-001 finalizing-workflow --cli-model opus')).toBe('opus');
        });

        it('hard --cli-model-for <step>:<tier> beats blanket hard --cli-model (FR-5 #1 > #2)', () => {
          runJSON('init FEAT-001 feature');
          // Per-step hard=opus should beat blanket hard=haiku for the matching step.
          expect(
            run(
              'resolve-tier FEAT-001 reviewing-requirements --cli-model haiku --cli-model-for reviewing-requirements:opus'
            )
          ).toBe('opus');
        });

        it('hard --cli-model-for does not affect non-matching steps', () => {
          runJSON('init FEAT-001 feature');
          // --cli-model-for reviewing-requirements:opus should not alter implementing-plan-phases
          // when a blanket hard --cli-model haiku is also passed (haiku wins for that step).
          expect(
            run(
              'resolve-tier FEAT-001 implementing-plan-phases --cli-model haiku --cli-model-for reviewing-requirements:opus'
            )
          ).toBe('haiku');
        });

        // --- Multi-flag --cli-model-for accumulation (FEAT-021 Edge Case 6) ---
        // Pre-FEAT-021 fix, resolve-tier stored --cli-model-for in a scalar
        // that silently discarded all but the last flag. The array
        // accumulation preserves every occurrence; first-matching-step wins.
        it('multiple --cli-model-for: flag matching the target step wins', () => {
          runJSON('init FEAT-001 feature');
          expect(
            run(
              'resolve-tier FEAT-001 reviewing-requirements ' +
                '--cli-model-for reviewing-requirements:opus ' +
                '--cli-model-for implementing-plan-phases:haiku'
            )
          ).toBe('opus');
        });

        it('multiple --cli-model-for: different target step picks its own flag', () => {
          runJSON('init FEAT-001 feature');
          expect(
            run(
              'resolve-tier FEAT-001 implementing-plan-phases ' +
                '--cli-model-for reviewing-requirements:opus ' +
                '--cli-model-for implementing-plan-phases:haiku'
            )
          ).toBe('haiku');
        });

        it('multiple --cli-model-for: unmatched target falls back to baseline', () => {
          runJSON('init FEAT-001 feature');
          // finalizing-workflow is baseline-locked at haiku; neither flag targets it.
          expect(
            run(
              'resolve-tier FEAT-001 finalizing-workflow ' +
                '--cli-model-for reviewing-requirements:opus ' +
                '--cli-model-for implementing-plan-phases:haiku'
            )
          ).toBe('haiku');
        });

        it('multiple --cli-model-for for the same step: first occurrence wins', () => {
          runJSON('init FEAT-001 feature');
          // Per Edge Case 6: first-occurrence-wins for same-step disambiguation.
          expect(
            run(
              'resolve-tier FEAT-001 reviewing-requirements ' +
                '--cli-model-for reviewing-requirements:opus ' +
                '--cli-model-for reviewing-requirements:haiku'
            )
          ).toBe('opus');
        });

        // --- Soft overrides (FR-5 #3 and #4) ---
        it('soft --cli-complexity low on computed opus tier is a no-op (upgrade-only)', () => {
          runJSON('init FEAT-001 feature');
          runJSON('set-complexity FEAT-001 high');
          expect(run('resolve-tier FEAT-001 reviewing-requirements --cli-complexity low')).toBe(
            'opus'
          );
        });

        it('soft --cli-complexity high on a default sonnet-baseline step → opus', () => {
          runJSON('init FEAT-001 feature');
          expect(run('resolve-tier FEAT-001 reviewing-requirements --cli-complexity high')).toBe(
            'opus'
          );
        });

        it('soft --state-override opus on finalizing-workflow is rejected (baseline-locked)', () => {
          runJSON('init FEAT-001 feature');
          expect(run('resolve-tier FEAT-001 finalizing-workflow --state-override opus')).toBe(
            'haiku'
          );
        });

        it('soft --state-override opus on reviewing-requirements upgrades non-locked step', () => {
          runJSON('init FEAT-001 feature');
          expect(run('resolve-tier FEAT-001 reviewing-requirements --state-override opus')).toBe(
            'opus'
          );
        });

        it('soft --cli-complexity high on baseline-locked finalizing-workflow stays haiku', () => {
          runJSON('init FEAT-001 feature');
          expect(run('resolve-tier FEAT-001 finalizing-workflow --cli-complexity high')).toBe(
            'haiku'
          );
        });

        it('hard --cli-model beats soft --cli-complexity even when soft would upgrade', () => {
          runJSON('init FEAT-001 feature');
          // --cli-model haiku is hard (FR-5 #2) and wins over --cli-complexity high (FR-5 #3).
          expect(
            run(
              'resolve-tier FEAT-001 reviewing-requirements --cli-model haiku --cli-complexity high'
            )
          ).toBe('haiku');
        });

        it('soft --cli-complexity wins over soft --state-override when set first (precedence #3 > #4)', () => {
          runJSON('init FEAT-001 feature');
          // Both soft; --cli-complexity is higher precedence so it applies first. Because the chain
          // breaks on the first non-null, --state-override is never consulted.
          // --cli-complexity low on sonnet baseline is a no-op (max(sonnet, haiku) = sonnet).
          // --state-override opus would upgrade to opus if it were consulted. Verify it is NOT.
          expect(
            run(
              'resolve-tier FEAT-001 reviewing-requirements --cli-complexity low --state-override opus'
            )
          ).toBe('sonnet');
        });
      });

      // --- FEAT-021 Phase 1: step-baseline / step-baseline-locked subcommands ---
      describe('step-baseline (FEAT-021 Phase 1)', () => {
        it('echoes sonnet for reviewing-requirements', () => {
          expect(run('step-baseline reviewing-requirements')).toBe('sonnet');
        });

        it('echoes sonnet for creating-implementation-plans', () => {
          expect(run('step-baseline creating-implementation-plans')).toBe('sonnet');
        });

        it('echoes sonnet for implementing-plan-phases', () => {
          expect(run('step-baseline implementing-plan-phases')).toBe('sonnet');
        });

        it('echoes sonnet for executing-chores', () => {
          expect(run('step-baseline executing-chores')).toBe('sonnet');
        });

        it('echoes sonnet for executing-bug-fixes', () => {
          expect(run('step-baseline executing-bug-fixes')).toBe('sonnet');
        });

        it('echoes haiku for finalizing-workflow', () => {
          expect(run('step-baseline finalizing-workflow')).toBe('haiku');
        });

        it('echoes haiku for pr-creation', () => {
          expect(run('step-baseline pr-creation')).toBe('haiku');
        });

        it('exits 2 with a clear error for an unknown step-name', () => {
          const err = run('step-baseline bogus-step', { expectError: true });
          expect(err).toContain("unknown step-name 'bogus-step'");
        });

        it('exits 2 when no step-name is provided', () => {
          const err = run('step-baseline', { expectError: true });
          expect(err).toContain('step-baseline requires');
        });
      });

      describe('step-baseline-locked (FEAT-021 Phase 1)', () => {
        it('echoes false for reviewing-requirements', () => {
          expect(run('step-baseline-locked reviewing-requirements')).toBe('false');
        });

        it('echoes false for creating-implementation-plans', () => {
          expect(run('step-baseline-locked creating-implementation-plans')).toBe('false');
        });

        it('echoes false for implementing-plan-phases', () => {
          expect(run('step-baseline-locked implementing-plan-phases')).toBe('false');
        });

        it('echoes false for executing-chores', () => {
          expect(run('step-baseline-locked executing-chores')).toBe('false');
        });

        it('echoes false for executing-bug-fixes', () => {
          expect(run('step-baseline-locked executing-bug-fixes')).toBe('false');
        });

        it('echoes true for finalizing-workflow', () => {
          expect(run('step-baseline-locked finalizing-workflow')).toBe('true');
        });

        it('echoes true for pr-creation', () => {
          expect(run('step-baseline-locked pr-creation')).toBe('true');
        });

        it('exits 2 with a clear error for an unknown step-name', () => {
          const err = run('step-baseline-locked bogus-step', { expectError: true });
          expect(err).toContain("unknown step-name 'bogus-step'");
        });

        it('exits 2 when no step-name is provided', () => {
          const err = run('step-baseline-locked', { expectError: true });
          expect(err).toContain('step-baseline-locked requires');
        });
      });
    });

    // --- FEAT-014 Phase 4: retry, resume, version compatibility helpers ---
    describe('Phase 4 shell helpers', () => {
      describe('next-tier-up', () => {
        it('escalates haiku → sonnet', () => {
          expect(run('next-tier-up haiku')).toBe('sonnet');
        });

        it('escalates sonnet → opus', () => {
          expect(run('next-tier-up sonnet')).toBe('opus');
        });

        it('exits 2 at opus', () => {
          const err = run('next-tier-up opus', { expectError: true });
          expect(err).toContain('retry exhausted at opus');
        });

        it('rejects unknown tiers', () => {
          const err = run('next-tier-up banana', { expectError: true });
          expect(err).toContain('requires a known tier');
        });
      });

      describe('resume-recompute', () => {
        it('returns persisted tier silently when signals unchanged', () => {
          runJSON('init CHORE-701 chore');
          // Seed a medium-complexity chore fixture at the canonical path.
          mkdirSync(join(testDir, 'requirements/chores'), { recursive: true });
          const content = execSync(`cat "${fixturePath('chore-medium.md')}"`, {
            encoding: 'utf-8',
          });
          writeFileSync(join(testDir, 'requirements/chores/CHORE-701.md'), content);
          run('set-complexity CHORE-701 medium');

          const tier = run('resume-recompute CHORE-701');
          expect(tier).toBe('medium');
          const state = readState('CHORE-701');
          expect(state.complexity).toBe('medium');
          expect(state.complexityStage).toBe('init');
        });

        it('upgrades persisted tier and logs when signals upgraded', () => {
          runJSON('init CHORE-702 chore');
          mkdirSync(join(testDir, 'requirements/chores'), { recursive: true });
          const lowContent = execSync(`cat "${fixturePath('chore-low.md')}"`, {
            encoding: 'utf-8',
          });
          writeFileSync(join(testDir, 'requirements/chores/CHORE-702.md'), lowContent);
          run('set-complexity CHORE-702 low');
          // Now swap in a high-complexity doc (simulating edits between pause/resume).
          const highContent = execSync(`cat "${fixturePath('chore-high.md')}"`, {
            encoding: 'utf-8',
          });
          writeFileSync(join(testDir, 'requirements/chores/CHORE-702.md'), highContent);

          // Capture stderr via 2>&1 1>/dev/null trick.
          const stderr = execSync(`bash "${SCRIPT}" resume-recompute CHORE-702 2>&1 1>/dev/null`, {
            cwd: testDir,
            encoding: 'utf-8',
          }).toString();
          expect(stderr).toContain('Work-item complexity upgraded since last invocation');
          expect(stderr).toContain('low');
          expect(stderr).toContain('high');

          const state = readState('CHORE-702');
          expect(state.complexity).toBe('high');
        });

        it('does not downgrade even when the doc signal drops', () => {
          runJSON('init CHORE-703 chore');
          mkdirSync(join(testDir, 'requirements/chores'), { recursive: true });
          const highContent = execSync(`cat "${fixturePath('chore-high.md')}"`, {
            encoding: 'utf-8',
          });
          writeFileSync(join(testDir, 'requirements/chores/CHORE-703.md'), highContent);
          run('set-complexity CHORE-703 high');
          // Swap in a low-complexity doc — resume must NOT downgrade.
          const lowContent = execSync(`cat "${fixturePath('chore-low.md')}"`, {
            encoding: 'utf-8',
          });
          writeFileSync(join(testDir, 'requirements/chores/CHORE-703.md'), lowContent);

          const tier = run('resume-recompute CHORE-703');
          expect(tier).toBe('high');
          const state = readState('CHORE-703');
          expect(state.complexity).toBe('high');
        });

        it('preserves complexityStage=post-plan across resume', () => {
          runJSON('init FEAT-701 feature');
          mkdirSync(join(testDir, 'requirements/features'), { recursive: true });
          const featContent = execSync(`cat "${fixturePath('feature-medium-no-bump.md')}"`, {
            encoding: 'utf-8',
          });
          writeFileSync(join(testDir, 'requirements/features/FEAT-701.md'), featContent);
          run('set-complexity FEAT-701 medium');

          // Post-plan transition via classify-post-plan.
          mkdirSync(join(testDir, 'requirements/implementation'), { recursive: true });
          const planContent = execSync(`cat "${fixturePath('feature-low-plan-4phase.md')}"`, {
            encoding: 'utf-8',
          });
          writeFileSync(join(testDir, 'requirements/implementation/FEAT-701-plan.md'), planContent);
          run('classify-post-plan FEAT-701');

          const mid = readState('FEAT-701');
          expect(mid.complexityStage).toBe('post-plan');

          // resume-recompute must keep post-plan stage.
          run('resume-recompute FEAT-701');
          const post = readState('FEAT-701');
          expect(post.complexityStage).toBe('post-plan');
          expect(post.complexity).toBe('high');
        });

        it('populates complexity on a freshly-migrated legacy state file', () => {
          // Write a legacy state file (FR-13) with no FEAT-014 fields at all.
          mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
          const legacy = {
            id: 'CHORE-704',
            type: 'chore',
            currentStep: 0,
            status: 'in-progress',
            pauseReason: null,
            steps: [
              {
                name: 'Document chore',
                skill: 'documenting-chores',
                context: 'main',
                status: 'pending',
                artifact: null,
                completedAt: null,
              },
            ],
            phases: { total: 0, completed: 0 },
            prNumber: null,
            branch: null,
            startedAt: '2026-04-01T00:00:00Z',
            lastResumedAt: null,
          };
          writeFileSync(join(testDir, '.sdlc/workflows/CHORE-704.json'), JSON.stringify(legacy));
          mkdirSync(join(testDir, 'requirements/chores'), { recursive: true });
          const highContent = execSync(`cat "${fixturePath('chore-high.md')}"`, {
            encoding: 'utf-8',
          });
          writeFileSync(join(testDir, 'requirements/chores/CHORE-704.md'), highContent);

          // resume-recompute runs the first-time population path (no log).
          run('resume-recompute CHORE-704');
          const state = readState('CHORE-704');
          expect(state.complexity).toBe('high');
          expect(state.complexityStage).toBe('init');
          expect(state.modelSelections).toEqual([]);
        });
      });

      describe('check-claude-version', () => {
        it('exits 0 when claude CLI is unavailable', () => {
          // Strip claude from PATH.
          execSync(`bash "${SCRIPT}" check-claude-version 2.1.72`, {
            cwd: testDir,
            encoding: 'utf-8',
            env: { PATH: '/usr/bin:/bin' },
          });
          // Reaching here means exit 0.
          expect(true).toBe(true);
        });

        it('warns and exits 1 when current < required', () => {
          const stubDir = join(testDir, 'stubs');
          mkdirSync(stubDir, { recursive: true });
          const stub = join(stubDir, 'claude');
          writeFileSync(stub, '#!/usr/bin/env bash\necho "1.0.0 (Claude Code)"\n');
          execSync(`chmod +x "${stub}"`);

          let stderr = '';
          let status: number | undefined;
          try {
            execSync(`bash "${SCRIPT}" check-claude-version 2.1.72`, {
              cwd: testDir,
              encoding: 'utf-8',
              stdio: ['pipe', 'pipe', 'pipe'],
              env: { PATH: `${stubDir}:/usr/bin:/bin` },
            });
          } catch (err) {
            const e = err as { status?: number; stderr?: string };
            status = e.status;
            stderr = e.stderr ?? '';
          }
          expect(status).toBe(1);
          expect(stderr).toContain('[model] Claude Code 1.0.0');
          expect(stderr).toContain('below the minimum 2.1.72');
        });

        it('exits 0 silently when current >= required', () => {
          const stubDir = join(testDir, 'stubs');
          mkdirSync(stubDir, { recursive: true });
          const stub = join(stubDir, 'claude');
          writeFileSync(stub, '#!/usr/bin/env bash\necho "3.0.5 (Claude Code)"\n');
          execSync(`chmod +x "${stub}"`);

          const result = execSync(`bash "${SCRIPT}" check-claude-version 2.1.72`, {
            cwd: testDir,
            encoding: 'utf-8',
            env: { PATH: `${stubDir}:/usr/bin:/bin` },
          }).toString();
          expect(result).toBe('');
        });

        it('accepts a custom required version', () => {
          const stubDir = join(testDir, 'stubs');
          mkdirSync(stubDir, { recursive: true });
          const stub = join(stubDir, 'claude');
          writeFileSync(stub, '#!/usr/bin/env bash\necho "2.0.0 (Claude Code)"\n');
          execSync(`chmod +x "${stub}"`);

          // 2.0.0 meets 1.5.0 but not 3.0.0.
          execSync(`bash "${SCRIPT}" check-claude-version 1.5.0`, {
            cwd: testDir,
            encoding: 'utf-8',
            env: { PATH: `${stubDir}:/usr/bin:/bin` },
          });

          let status: number | undefined;
          try {
            execSync(`bash "${SCRIPT}" check-claude-version 3.0.0`, {
              cwd: testDir,
              encoding: 'utf-8',
              stdio: ['pipe', 'pipe', 'pipe'],
              env: { PATH: `${stubDir}:/usr/bin:/bin` },
            });
          } catch (err) {
            status = (err as { status?: number }).status;
          }
          expect(status).toBe(1);
        });
      });
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

    it('errors when set-gate has missing gate-type', () => {
      runJSON('init FEAT-001 feature');
      const err = run('set-gate FEAT-001', { expectError: true });
      expect(err).toContain('set-gate requires');
    });

    it('errors when clear-gate has missing ID', () => {
      const err = run('clear-gate', { expectError: true });
      expect(err).toContain('clear-gate requires');
    });
  });
});

// Stop hook tests
const STOP_HOOK = join(
  process.cwd(),
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/stop-hook.sh'
);

const WORKFLOW_STATE = join(
  process.cwd(),
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh'
);

// Both runHook and runState use cwd: testDir so that relative paths in
// stop-hook.sh (e.g. ACTIVE_FILE=".sdlc/workflows/.active") resolve inside
// the isolated temp directory, matching real-world behavior where scripts
// run from the project root.
function runHook(): {
  stdout: string;
  stderr: string;
  exitCode: number;
} {
  try {
    const stdout = execSync(`bash "${STOP_HOOK}"`, {
      cwd: testDir,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, PATH: process.env.PATH },
    });
    return { stdout: stdout.trim(), stderr: '', exitCode: 0 };
  } catch (err) {
    const e = err as { status?: number; stderr?: Buffer | string; stdout?: Buffer | string };
    return {
      stdout: (e.stdout?.toString() ?? '').trim(),
      stderr: (e.stderr?.toString() ?? '').trim(),
      exitCode: e.status ?? 1,
    };
  }
}

function runState(args: string): void {
  execSync(`bash "${WORKFLOW_STATE}" ${args}`, {
    cwd: testDir,
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, PATH: process.env.PATH },
  });
}

function writeActiveFile(id: string): void {
  mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
  writeFileSync(join(testDir, '.sdlc/workflows/.active'), id, 'utf-8');
}

describe('stop-hook.sh', () => {
  beforeEach(() => {
    testDir = mkdtempSync(join(tmpdir(), 'stop-hook-'));
  });

  afterEach(() => {
    rmSync(testDir, { recursive: true, force: true });
  });

  it('allows stop when .active file does not exist', () => {
    const result = runHook();
    expect(result.exitCode).toBe(0);
  });

  it('allows stop when .active file is empty', () => {
    mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
    writeFileSync(join(testDir, '.sdlc/workflows/.active'), '', 'utf-8');
    const result = runHook();
    expect(result.exitCode).toBe(0);
  });

  it('allows stop when workflow is paused', () => {
    runState('init FEAT-001 feature');
    runState('pause FEAT-001 review-findings');
    writeActiveFile('FEAT-001');
    const result = runHook();
    expect(result.exitCode).toBe(0);
  });

  it('allows stop when workflow is complete', () => {
    runState('init FEAT-001 feature');
    runState('complete FEAT-001');
    writeActiveFile('FEAT-001');
    const result = runHook();
    expect(result.exitCode).toBe(0);
  });

  it('blocks stop when workflow is in-progress with remaining steps', () => {
    runState('init FEAT-001 feature');
    writeActiveFile('FEAT-001');
    const result = runHook();
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain('FEAT-001');
    expect(result.stderr).toContain('in-progress');
  });

  it('allows stop when gate is active (findings-decision gate suppresses nudge)', () => {
    runState('init FEAT-001 feature');
    runState('set-gate FEAT-001 findings-decision');
    writeActiveFile('FEAT-001');
    const result = runHook();
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toBe('');
  });

  it('blocks stop again after gate is cleared', () => {
    runState('init FEAT-001 feature');
    runState('set-gate FEAT-001 findings-decision');
    runState('clear-gate FEAT-001');
    writeActiveFile('FEAT-001');
    const result = runHook();
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain('in-progress');
  });

  it('allows stop when .active file references stale/missing state', () => {
    mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
    writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'FEAT-999', 'utf-8');
    const result = runHook();
    expect(result.exitCode).toBe(0);
  });
});
