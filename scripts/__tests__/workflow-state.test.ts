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

    it('accepts bug chain type', () => {
      const state = runJSON('init BUG-001 bug');
      expect(state.type).toBe('bug');
      expect(state.steps).toHaveLength(9);
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
    it('generate_chore_steps produces exactly 9 steps with correct names, skills, and contexts', () => {
      const state = runJSON('init CHORE-001 chore');
      const steps = state.steps as Array<Record<string, unknown>>;

      expect(steps).toHaveLength(9);

      const expected = [
        { name: 'Document chore', skill: 'documenting-chores', context: 'main' },
        {
          name: 'Review requirements (standard)',
          skill: 'reviewing-requirements',
          context: 'fork',
        },
        { name: 'Document QA test plan', skill: 'documenting-qa', context: 'main' },
        { name: 'Reconcile test plan', skill: 'reviewing-requirements', context: 'fork' },
        { name: 'Execute chore', skill: 'executing-chores', context: 'fork' },
        { name: 'PR review', skill: null, context: 'pause' },
        { name: 'Reconcile post-review', skill: 'reviewing-requirements', context: 'fork' },
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
      expect(state.steps).toHaveLength(9);
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
    it('generate_bug_steps produces exactly 9 steps with correct names, skills, and contexts', () => {
      const state = runJSON('init BUG-001 bug');
      const steps = state.steps as Array<Record<string, unknown>>;

      expect(steps).toHaveLength(9);

      const expected = [
        { name: 'Document bug', skill: 'documenting-bugs', context: 'main' },
        {
          name: 'Review requirements (standard)',
          skill: 'reviewing-requirements',
          context: 'fork',
        },
        { name: 'Document QA test plan', skill: 'documenting-qa', context: 'main' },
        { name: 'Reconcile test plan', skill: 'reviewing-requirements', context: 'fork' },
        { name: 'Execute bug fix', skill: 'executing-bug-fixes', context: 'fork' },
        { name: 'PR review', skill: null, context: 'pause' },
        { name: 'Reconcile post-review', skill: 'reviewing-requirements', context: 'fork' },
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
      expect(state.steps).toHaveLength(9);
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

      it('modelOverride takes precedence over complexity for non-locked steps', () => {
        runJSON('init FEAT-001 feature');
        runJSON('set-complexity FEAT-001 high');
        // Manually set modelOverride = sonnet (soft-override semantics).
        const stateFile = join(testDir, '.sdlc/workflows/FEAT-001.json');
        const raw = JSON.parse(readFileSync(stateFile, 'utf-8'));
        raw.modelOverride = 'sonnet';
        writeFileSync(stateFile, JSON.stringify(raw));
        // Override replaces the computed tier.
        expect(run('get-model FEAT-001 reviewing-requirements')).toBe('sonnet');
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
