import { describe, it, expect, beforeAll, beforeEach, afterEach } from 'vitest';
import { readFile } from 'node:fs/promises';
import { execSync, type ExecSyncOptionsWithStringEncoding } from 'node:child_process';
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/orchestrating-workflows';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const SCRIPTS_DIR = join(SKILL_DIR, 'scripts');
const STATE_SCRIPT = join(SCRIPTS_DIR, 'workflow-state.sh');
const STOP_HOOK = join(SCRIPTS_DIR, 'stop-hook.sh');

// --- Skill Validation Tests ---

describe('orchestrating-workflows skill', () => {
  let skillMd: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
  });

  describe('SKILL.md', () => {
    it('should have frontmatter with name: orchestrating-workflows', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*orchestrating-workflows[\s\S]*?---/);
    });

    it('should have frontmatter with non-empty description', () => {
      const match = skillMd.match(/^---\s*\n[\s\S]*?description:\s*(.+)[\s\S]*?---/);
      expect(match).not.toBeNull();
      expect(match![1].trim().length).toBeGreaterThan(0);
    });

    it('should have argument-hint in frontmatter', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?argument-hint:[\s\S]*?---/);
    });

    it('should have compatibility field in frontmatter', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?compatibility:[\s\S]*?---/);
    });

    it('should have hooks field with Stop command hook', () => {
      expect(skillMd).toMatch(
        /^---\s*\n[\s\S]*?hooks:[\s\S]*?Stop:[\s\S]*?type:\s*command[\s\S]*?---/
      );
    });

    it('should use ${CLAUDE_PLUGIN_ROOT} in Stop hook command path', () => {
      expect(skillMd).toMatch(
        /^---\s*\n[\s\S]*?command:\s*.*\$\{CLAUDE_PLUGIN_ROOT\}\/skills\/orchestrating-workflows\/scripts\/stop-hook\.sh[\s\S]*?---/
      );
    });

    it('should use ${CLAUDE_SKILL_DIR} for workflow-state.sh references in body', () => {
      // Extract body content (everything after the closing ---)
      const bodyMatch = skillMd.match(/^---\s*\n[\s\S]*?---\s*\n([\s\S]*)$/);
      expect(bodyMatch).not.toBeNull();
      const body = bodyMatch![1];

      // No bare scripts/workflow-state.sh references should remain in body
      const bareRefs = body.match(/(?<!\$\{CLAUDE_SKILL_DIR\}\/)scripts\/workflow-state\.sh/g);
      expect(bareRefs).toBeNull();

      // All references should use ${CLAUDE_SKILL_DIR}/ prefix
      const prefixedRefs = body.match(/\$\{CLAUDE_SKILL_DIR\}\/scripts\/workflow-state\.sh/g);
      expect(prefixedRefs).not.toBeNull();
      expect(prefixedRefs!.length).toBe(70);
    });

    it('should include "When to Use This Skill" section', () => {
      expect(skillMd).toContain('## When to Use This Skill');
    });

    it('should include "Quick Start" section', () => {
      expect(skillMd).toContain('## Quick Start');
    });

    it('should include "Verification Checklist" section', () => {
      expect(skillMd).toContain('## Verification Checklist');
    });

    it('should include "Relationship to Other Skills" section', () => {
      expect(skillMd).toContain('## Relationship to Other Skills');
    });

    it('should reference all sub-skills in relationship section', () => {
      expect(skillMd).toContain('documenting-features');
      expect(skillMd).toContain('reviewing-requirements');
      expect(skillMd).toContain('creating-implementation-plans');
      expect(skillMd).toContain('documenting-qa');
      expect(skillMd).toContain('implementing-plan-phases');
      expect(skillMd).toContain('executing-qa');
      expect(skillMd).toContain('finalizing-workflow');
    });

    it('should document main-context steps (1, 5, 6+N+4)', () => {
      expect(skillMd).toContain('Main-Context Steps');
      expect(skillMd).toContain('main');
    });

    it('should document forked steps via Agent tool', () => {
      expect(skillMd).toContain('Forked Steps');
      expect(skillMd).toContain('Agent tool');
    });

    it('should document pause points', () => {
      expect(skillMd).toContain('Plan Approval');
      expect(skillMd).toContain('PR Review');
      expect(skillMd).toContain('pause');
    });

    it('should document PR suppression instruction for implementing-plan-phases', () => {
      expect(skillMd).toContain('Do NOT create a pull request at the end');
    });

    it('should document error handling', () => {
      expect(skillMd).toContain('## Error Handling');
    });
  });

  describe('ai-skills-manager validation', () => {
    it('should pass validate() with all checks', async () => {
      const result = (await validate(SKILL_DIR, {
        detailed: true,
      })) as DetailedValidateResult;
      expect(result.valid).toBe(true);
      if (Array.isArray(result.checks)) {
        expect(result.checks.every((c) => c.passed)).toBe(true);
      }
    });
  });

  describe('scripts', () => {
    it('should have workflow-state.sh', () => {
      expect(existsSync(STATE_SCRIPT)).toBe(true);
    });

    it('should have stop-hook.sh', () => {
      expect(existsSync(STOP_HOOK)).toBe(true);
    });
  });
});

// --- Integration Tests ---

let testDir: string;
const execOpts = (): ExecSyncOptionsWithStringEncoding => ({
  cwd: testDir,
  encoding: 'utf-8' as const,
  stdio: ['pipe', 'pipe', 'pipe'] as const,
  env: { ...process.env, PATH: process.env.PATH },
});

function stateCmd(args: string): string {
  return execSync(`bash "${join(process.cwd(), STATE_SCRIPT)}" ${args}`, execOpts()).trim();
}

function stateJSON(args: string): Record<string, unknown> {
  return JSON.parse(stateCmd(args));
}

function runHook(): { exitCode: number; stderr: string } {
  try {
    execSync(`bash "${join(process.cwd(), STOP_HOOK)}"`, execOpts());
    return { exitCode: 0, stderr: '' };
  } catch (err) {
    const error = err as { status?: number; stderr?: string };
    return {
      exitCode: error.status ?? 1,
      stderr: (error.stderr ?? '').trim(),
    };
  }
}

function createPlan(id: string, phases: number): void {
  const dir = join(testDir, 'requirements/implementation');
  mkdirSync(dir, { recursive: true });
  let content = `# Implementation Plan\n\n`;
  for (let i = 1; i <= phases; i++) {
    content += `### Phase ${i}: Phase ${i} Name\n**Status:** Pending\n\n`;
  }
  writeFileSync(join(dir, `${id}-test-plan.md`), content);
}

describe('integration tests', () => {
  beforeEach(() => {
    testDir = mkdtempSync(join(tmpdir(), 'wf-integ-'));
  });

  afterEach(() => {
    rmSync(testDir, { recursive: true, force: true });
  });

  describe('full workflow lifecycle', () => {
    it('init → advance → pause → resume → advance → complete', () => {
      // Init
      const initState = stateJSON('init FEAT-001 feature');
      expect(initState.status).toBe('in-progress');
      expect(initState.currentStep).toBe(0);

      // Advance step 0
      stateCmd('advance FEAT-001 "requirements/features/FEAT-001.md"');

      // Advance step 1
      stateCmd('advance FEAT-001');

      // Advance step 2
      stateCmd('advance FEAT-001 "requirements/implementation/FEAT-001.md"');

      // Pause at step 3 (plan approval)
      const pauseState = stateJSON('pause FEAT-001 plan-approval');
      expect(pauseState.status).toBe('paused');
      expect(pauseState.currentStep).toBe(3);

      // Resume
      const resumeState = stateJSON('resume FEAT-001');
      expect(resumeState.status).toBe('in-progress');
      expect(resumeState.pauseReason).toBeNull();
      expect(resumeState.lastResumedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);

      // Advance step 3
      stateCmd('advance FEAT-001');

      // Complete
      const completeState = stateJSON('complete FEAT-001');
      expect(completeState.status).toBe('complete');
      expect(completeState.completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });
  });

  describe('error recovery', () => {
    it('fail → resume → retry cycle', () => {
      stateJSON('init FEAT-001 feature');
      stateCmd('advance FEAT-001');

      // Fail at step 1
      const failState = stateJSON('fail FEAT-001 "Review crashed"');
      expect(failState.status).toBe('failed');
      expect(failState.error).toBe('Review crashed');
      const steps = failState.steps as Array<Record<string, unknown>>;
      expect(steps[1].status).toBe('failed');

      // Resume (retry)
      const resumeState = stateJSON('resume FEAT-001');
      expect(resumeState.status).toBe('in-progress');
      expect(resumeState.lastResumedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);

      // Retry the step — advance succeeds this time
      const retryState = stateJSON('advance FEAT-001');
      expect(retryState.currentStep).toBe(2);
    });
  });

  describe('phase loop state transitions', () => {
    it('tracks phase count and per-phase completion', () => {
      createPlan('FEAT-001', 3);

      stateJSON('init FEAT-001 feature');

      // Verify phase count
      const count = stateCmd('phase-count FEAT-001');
      expect(count).toBe('3');

      // Advance through steps 0-5 (pre-phase steps)
      for (let i = 0; i < 6; i++) {
        stateCmd('advance FEAT-001');
      }

      const state = stateJSON('status FEAT-001');
      expect(state.currentStep).toBe(6);

      // Verify all 6 initial steps are complete
      const steps = state.steps as Array<Record<string, unknown>>;
      for (let i = 0; i < 6; i++) {
        expect(steps[i].status).toBe('complete');
      }
    });
  });

  describe('stop hook behavior', () => {
    it('exits 0 when no .active file exists', () => {
      const result = runHook();
      expect(result.exitCode).toBe(0);
    });

    it('exits 0 when .active file is empty', () => {
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), '');
      const result = runHook();
      expect(result.exitCode).toBe(0);
    });

    it('exits 2 for in-progress workflow', () => {
      stateJSON('init FEAT-001 feature');
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'FEAT-001');

      const result = runHook();
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('in-progress');
      expect(result.stderr).toContain('Document feature requirements');
    });

    it('exits 0 for paused workflow', () => {
      stateJSON('init FEAT-001 feature');
      stateCmd('pause FEAT-001 plan-approval');
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'FEAT-001');

      const result = runHook();
      expect(result.exitCode).toBe(0);
    });

    it('exits 0 for complete workflow', () => {
      stateJSON('init FEAT-001 feature');
      stateCmd('complete FEAT-001');
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'FEAT-001');

      const result = runHook();
      expect(result.exitCode).toBe(0);
    });

    it('cleans up stale .active file and exits 0', () => {
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'FEAT-999');

      const result = runHook();
      expect(result.exitCode).toBe(0);
      // .active should be removed
      expect(existsSync(join(testDir, '.sdlc/workflows/.active'))).toBe(false);
    });

    it('exits 2 for failed workflow', () => {
      stateJSON('init FEAT-001 feature');
      stateCmd('fail FEAT-001 "step broke"');
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'FEAT-001');

      const result = runHook();
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('failed');
    });
  });

  describe('PR metadata', () => {
    it('set-pr records metadata accessible via status', () => {
      stateJSON('init FEAT-001 feature');
      stateCmd('set-pr FEAT-001 42 feat/FEAT-001-test');

      const state = stateJSON('status FEAT-001');
      expect(state.prNumber).toBe(42);
      expect(state.branch).toBe('feat/FEAT-001-test');
    });
  });

  // --- Chore Chain Integration Tests ---

  describe('chore chain lifecycle', () => {
    it('init → advance through all 9 steps → pause at step 5 → resume → advance remaining → complete', () => {
      // Init chore chain
      const initState = stateJSON('init CHORE-001 chore');
      expect(initState.status).toBe('in-progress');
      expect(initState.currentStep).toBe(0);
      expect(initState.type).toBe('chore');
      const initSteps = initState.steps as Array<Record<string, unknown>>;
      expect(initSteps).toHaveLength(9);

      // Advance steps 0-4 (Document chore through Execute chore)
      stateCmd('advance CHORE-001 "requirements/chores/CHORE-001-test.md"'); // step 0: Document chore
      stateCmd('advance CHORE-001'); // step 1: Review requirements
      stateCmd('advance CHORE-001'); // step 2: Document QA test plan
      stateCmd('advance CHORE-001'); // step 3: Reconcile test plan
      stateCmd('advance CHORE-001'); // step 4: Execute chore

      // Now at step 5 (PR review pause point)
      const prePause = stateJSON('status CHORE-001');
      expect(prePause.currentStep).toBe(5);
      const prePauseSteps = prePause.steps as Array<Record<string, unknown>>;
      expect(prePauseSteps[5].name).toBe('PR review');
      expect(prePauseSteps[5].context).toBe('pause');

      // Pause at step 5 (PR review)
      const pauseState = stateJSON('pause CHORE-001 pr-review');
      expect(pauseState.status).toBe('paused');
      expect(pauseState.pauseReason).toBe('pr-review');
      expect(pauseState.currentStep).toBe(5);

      // Resume
      const resumeState = stateJSON('resume CHORE-001');
      expect(resumeState.status).toBe('in-progress');
      expect(resumeState.pauseReason).toBeNull();
      expect(resumeState.lastResumedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);

      // Advance steps 5-8 (PR review through Finalize)
      stateCmd('advance CHORE-001'); // step 5: PR review
      stateCmd('advance CHORE-001'); // step 6: Reconcile post-review
      stateCmd('advance CHORE-001'); // step 7: Execute QA
      stateCmd('advance CHORE-001'); // step 8: Finalize

      // Complete
      const completeState = stateJSON('complete CHORE-001');
      expect(completeState.status).toBe('complete');
      expect(completeState.completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);

      // Verify all steps are complete
      const finalSteps = completeState.steps as Array<Record<string, unknown>>;
      for (let i = 0; i < 9; i++) {
        expect(finalSteps[i].status).toBe('complete');
      }
    });
  });

  describe('chore chain PR metadata', () => {
    it('set-pr records metadata accessible via status for chore chain', () => {
      stateJSON('init CHORE-001 chore');
      stateCmd('set-pr CHORE-001 55 chore/CHORE-001-test');

      const state = stateJSON('status CHORE-001');
      expect(state.prNumber).toBe(55);
      expect(state.branch).toBe('chore/CHORE-001-test');
    });
  });

  describe('chore chain has no phase loop', () => {
    it('state file has exactly 9 steps from init with no dynamic insertion needed', () => {
      const state = stateJSON('init CHORE-001 chore');
      const steps = state.steps as Array<Record<string, unknown>>;

      // Exactly 9 steps — no populate-phases needed
      expect(steps).toHaveLength(9);

      // Verify no step has phaseNumber (no phase loop steps)
      for (const step of steps) {
        expect(step).not.toHaveProperty('phaseNumber');
      }

      // Verify step names match the fixed 9-step sequence
      const expectedNames = [
        'Document chore',
        'Review requirements (standard)',
        'Document QA test plan',
        'Reconcile test plan',
        'Execute chore',
        'PR review',
        'Reconcile post-review',
        'Execute QA',
        'Finalize',
      ];
      for (let i = 0; i < 9; i++) {
        expect(steps[i].name).toBe(expectedNames[i]);
      }
    });
  });

  describe('chore chain has no plan-approval pause', () => {
    it('chore chain has only pr-review pause step; no plan-approval step exists', () => {
      const state = stateJSON('init CHORE-001 chore');
      const steps = state.steps as Array<Record<string, unknown>>;

      // Find all pause steps
      const pauseSteps = steps.filter((s) => s.context === 'pause');
      expect(pauseSteps).toHaveLength(1);
      expect(pauseSteps[0].name).toBe('PR review');

      // Verify no step is named plan-approval or Plan approval
      const planApprovalSteps = steps.filter(
        (s) =>
          s.name === 'Plan approval' ||
          s.name === 'plan-approval' ||
          (s as Record<string, unknown>).skill === 'plan-approval'
      );
      expect(planApprovalSteps).toHaveLength(0);
    });
  });

  describe('chore chain error recovery', () => {
    it('fail at step 4 (executing-chores) → resume → retry → advance succeeds', () => {
      stateJSON('init CHORE-001 chore');

      // Advance to step 4 (Execute chore)
      stateCmd('advance CHORE-001'); // step 0
      stateCmd('advance CHORE-001'); // step 1
      stateCmd('advance CHORE-001'); // step 2
      stateCmd('advance CHORE-001'); // step 3

      // Verify we're at step 4
      const atStep4 = stateJSON('status CHORE-001');
      expect(atStep4.currentStep).toBe(4);
      const steps4 = atStep4.steps as Array<Record<string, unknown>>;
      expect(steps4[4].name).toBe('Execute chore');
      expect(steps4[4].skill).toBe('executing-chores');

      // Fail at step 4
      const failState = stateJSON('fail CHORE-001 "Chore execution crashed"');
      expect(failState.status).toBe('failed');
      expect(failState.error).toBe('Chore execution crashed');
      const failSteps = failState.steps as Array<Record<string, unknown>>;
      expect(failSteps[4].status).toBe('failed');

      // Resume (retry)
      const resumeState = stateJSON('resume CHORE-001');
      expect(resumeState.status).toBe('in-progress');
      expect(resumeState.lastResumedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
      expect(resumeState.error).toBeNull();

      // Retry the step — advance succeeds this time
      const retryState = stateJSON('advance CHORE-001');
      expect(retryState.currentStep).toBe(5);
      const retrySteps = retryState.steps as Array<Record<string, unknown>>;
      expect(retrySteps[4].status).toBe('complete');
    });
  });

  describe('chore chain stop hook behavior', () => {
    it('exits 2 for in-progress chore chain', () => {
      stateJSON('init CHORE-001 chore');
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'CHORE-001');

      const result = runHook();
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('in-progress');
    });

    it('exits 0 for paused chore chain', () => {
      stateJSON('init CHORE-001 chore');
      stateCmd('pause CHORE-001 pr-review');
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'CHORE-001');

      const result = runHook();
      expect(result.exitCode).toBe(0);
    });

    it('exits 0 for complete chore chain', () => {
      stateJSON('init CHORE-001 chore');
      stateCmd('complete CHORE-001');
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'CHORE-001');

      const result = runHook();
      expect(result.exitCode).toBe(0);
    });
  });

  describe('bug chain lifecycle', () => {
    it('init → advance through all 9 steps → pause at step 5 → resume → advance remaining → complete', () => {
      const initState = stateJSON('init BUG-001 bug');
      expect(initState.type).toBe('bug');
      expect(initState.steps).toHaveLength(9);

      // Advance steps 0-4
      stateCmd('advance BUG-001');
      stateCmd('advance BUG-001');
      stateCmd('advance BUG-001');
      stateCmd('advance BUG-001');
      stateCmd('advance BUG-001');

      // At step 5 (PR review pause)
      const atPause = stateJSON('status BUG-001');
      expect(atPause.currentStep).toBe(5);
      const pauseSteps = atPause.steps as Array<Record<string, unknown>>;
      expect(pauseSteps[5].name).toBe('PR review');
      expect(pauseSteps[5].context).toBe('pause');

      // Pause and resume
      stateCmd('pause BUG-001 pr-review');
      const pausedState = stateJSON('status BUG-001');
      expect(pausedState.status).toBe('paused');
      expect(pausedState.pauseReason).toBe('pr-review');

      const resumedState = stateJSON('resume BUG-001');
      expect(resumedState.status).toBe('in-progress');
      expect(resumedState.lastResumedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);

      // Advance remaining steps 5-8
      stateCmd('advance BUG-001');
      stateCmd('advance BUG-001');
      stateCmd('advance BUG-001');
      stateCmd('advance BUG-001');

      // Complete
      const completedState = stateJSON('complete BUG-001');
      expect(completedState.status).toBe('complete');
      expect(completedState.completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);

      const finalSteps = completedState.steps as Array<Record<string, unknown>>;
      for (let i = 0; i < 9; i++) {
        expect(finalSteps[i].status).toBe('complete');
      }
    });
  });

  describe('bug chain PR metadata', () => {
    it('set-pr records metadata accessible via status for bug chain', () => {
      stateJSON('init BUG-001 bug');
      stateCmd('set-pr BUG-001 77 fix/BUG-001-test');

      const state = stateJSON('status BUG-001');
      expect(state.prNumber).toBe(77);
      expect(state.branch).toBe('fix/BUG-001-test');
    });
  });

  describe('bug chain has no phase loop', () => {
    it('state file has exactly 9 steps from init with no dynamic insertion needed', () => {
      const state = stateJSON('init BUG-001 bug');
      const steps = state.steps as Array<Record<string, unknown>>;

      expect(steps).toHaveLength(9);

      const expectedNames = [
        'Document bug',
        'Review requirements (standard)',
        'Document QA test plan',
        'Reconcile test plan',
        'Execute bug fix',
        'PR review',
        'Reconcile post-review',
        'Execute QA',
        'Finalize',
      ];
      for (let i = 0; i < 9; i++) {
        expect(steps[i].name).toBe(expectedNames[i]);
      }
    });
  });

  describe('bug chain has no plan-approval pause', () => {
    it('bug chain has only pr-review pause step; no plan-approval step exists', () => {
      const state = stateJSON('init BUG-001 bug');
      const steps = state.steps as Array<Record<string, unknown>>;

      const pauseSteps = steps.filter((s) => s.context === 'pause');
      expect(pauseSteps).toHaveLength(1);
      expect(pauseSteps[0].name).toBe('PR review');

      const planApprovalSteps = steps.filter(
        (s) =>
          s.name === 'Plan approval' ||
          s.name === 'plan-approval' ||
          (s as Record<string, unknown>).skill === 'plan-approval'
      );
      expect(planApprovalSteps).toHaveLength(0);
    });
  });

  describe('bug chain error recovery', () => {
    it('fail at step 4 (executing-bug-fixes) → resume → retry → advance succeeds', () => {
      stateJSON('init BUG-001 bug');

      stateCmd('advance BUG-001');
      stateCmd('advance BUG-001');
      stateCmd('advance BUG-001');
      stateCmd('advance BUG-001');

      const atStep4 = stateJSON('status BUG-001');
      expect(atStep4.currentStep).toBe(4);
      const steps4 = atStep4.steps as Array<Record<string, unknown>>;
      expect(steps4[4].name).toBe('Execute bug fix');
      expect(steps4[4].skill).toBe('executing-bug-fixes');

      const failState = stateJSON('fail BUG-001 "Bug fix execution crashed"');
      expect(failState.status).toBe('failed');
      expect(failState.error).toBe('Bug fix execution crashed');

      const resumeState = stateJSON('resume BUG-001');
      expect(resumeState.status).toBe('in-progress');
      expect(resumeState.lastResumedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);

      const retryState = stateJSON('advance BUG-001');
      expect(retryState.currentStep).toBe(5);
      const retrySteps = retryState.steps as Array<Record<string, unknown>>;
      expect(retrySteps[4].status).toBe('complete');
    });
  });

  describe('bug chain stop hook behavior', () => {
    it('exits 2 for in-progress bug chain', () => {
      stateJSON('init BUG-001 bug');
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'BUG-001');

      const result = runHook();
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('in-progress');
    });

    it('exits 0 for paused bug chain', () => {
      stateJSON('init BUG-001 bug');
      stateCmd('pause BUG-001 pr-review');
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'BUG-001');

      const result = runHook();
      expect(result.exitCode).toBe(0);
    });

    it('exits 0 for complete bug chain', () => {
      stateJSON('init BUG-001 bug');
      stateCmd('complete BUG-001');
      mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
      writeFileSync(join(testDir, '.sdlc/workflows/.active'), 'BUG-001');

      const result = runHook();
      expect(result.exitCode).toBe(0);
    });
  });

  // --- FEAT-014 Phase 3 Adaptive Model Selection Integration Tests ---
  //
  // These tests drive workflow-state.sh end-to-end against the synthetic
  // fixtures from Phase 2 to verify the tier-resolution, audit-trail write,
  // and post-plan re-classification pathways wired into the orchestrator
  // SKILL.md call sites. They map directly onto Worked Examples A, B, C from
  // requirements/features/FEAT-014-adaptive-model-selection.md lines 449-527.
  describe('FEAT-014 adaptive model selection', () => {
    const FIXTURES_DIR = join(process.cwd(), 'scripts/__tests__/fixtures/feat-014');
    const fx = (name: string): string => join(FIXTURES_DIR, name);

    // Seed a synthetic requirement artifact at the canonical location so
    // classify-init can read it. For this test it's enough to copy the
    // fixture contents into the expected path.
    function seedArtifact(rel: string, fixtureFile: string): void {
      const abs = join(testDir, rel);
      mkdirSync(join(abs, '..'), { recursive: true });
      // Use Node fs since the fixture may be outside testDir.
      const content = execSync(`cat "${fx(fixtureFile)}"`, { encoding: 'utf-8' });
      writeFileSync(abs, content);
    }

    function seedPlan(id: string, fixtureFile: string): void {
      const dir = join(testDir, 'requirements/implementation');
      mkdirSync(dir, { recursive: true });
      const content = execSync(`cat "${fx(fixtureFile)}"`, { encoding: 'utf-8' });
      writeFileSync(join(dir, `${id}-test-plan.md`), content);
    }

    function resolveTier(id: string, step: string): string {
      return stateCmd(`resolve-tier ${id} ${step}`);
    }

    function recordSelection(
      id: string,
      stepIndex: number,
      skill: string,
      mode: string,
      phase: string,
      tier: string
    ): void {
      const stage = (stateJSON(`status ${id}`).complexityStage as string) || 'init';
      stateCmd(
        `record-model-selection ${id} ${stepIndex} ${skill} ${mode} ${phase} ${tier} ${stage} 2026-04-11T00:00:00Z`
      );
    }

    describe('Example A — low-complexity chore (zero Opus)', () => {
      it('medium chore → every fork resolves sonnet or haiku; no opus', () => {
        const id = 'CHORE-101';
        stateJSON(`init ${id} chore`);
        seedArtifact(`requirements/chores/${id}-example-a.md`, 'chore-medium.md');

        const initTier = stateCmd(`classify-init ${id} requirements/chores/${id}-example-a.md`);
        expect(initTier).toBe('medium');
        stateCmd(`set-complexity ${id} ${initTier}`);

        // Every chore-chain fork step and its expected tier per Example A.
        const forkSteps: Array<[number, string, string, string]> = [
          // [stepIndex, step-name, mode, expected tier]
          [1, 'reviewing-requirements', 'standard', 'sonnet'],
          [3, 'reviewing-requirements', 'test-plan', 'sonnet'],
          [4, 'executing-chores', 'null', 'sonnet'],
          [6, 'reviewing-requirements', 'code-review', 'sonnet'],
          [8, 'finalizing-workflow', 'null', 'haiku'],
        ];

        for (const [stepIndex, step, mode, expected] of forkSteps) {
          const tier = resolveTier(id, step);
          expect(tier).toBe(expected);
          recordSelection(id, stepIndex, step, mode, 'null', tier);
        }

        const finalState = stateJSON(`status ${id}`);
        const selections = finalState.modelSelections as Array<Record<string, unknown>>;
        expect(selections).toHaveLength(5);

        // Zero Opus tier invocations.
        const opusCount = selections.filter((s) => s.tier === 'opus').length;
        expect(opusCount).toBe(0);

        // All non-final forks at sonnet; finalizing at haiku.
        expect(selections.filter((s) => s.tier === 'sonnet')).toHaveLength(4);
        expect(selections.filter((s) => s.tier === 'haiku')).toHaveLength(1);

        // Every audit entry is stamped with init stage (chore chains never upgrade).
        for (const sel of selections) {
          expect(sel.complexityStage).toBe('init');
        }
      });
    });

    describe('Example B — low-severity bug (zero Opus; Sonnet baseline floor)', () => {
      it('low bug → every non-final fork is sonnet via baseline floor; finalize is haiku', () => {
        const id = 'BUG-101';
        stateJSON(`init ${id} bug`);
        seedArtifact(`requirements/bugs/${id}-example-b.md`, 'bug-low.md');

        const initTier = stateCmd(`classify-init ${id} requirements/bugs/${id}-example-b.md`);
        expect(initTier).toBe('low');
        stateCmd(`set-complexity ${id} ${initTier}`);

        // Bug-chain fork steps per Example B.
        const forkSteps: Array<[number, string, string, string]> = [
          [1, 'reviewing-requirements', 'standard', 'sonnet'],
          [3, 'reviewing-requirements', 'test-plan', 'sonnet'],
          [4, 'executing-bug-fixes', 'null', 'sonnet'],
          [6, 'reviewing-requirements', 'code-review', 'sonnet'],
          [8, 'finalizing-workflow', 'null', 'haiku'],
        ];

        for (const [stepIndex, step, mode, expected] of forkSteps) {
          const tier = resolveTier(id, step);
          expect(tier).toBe(expected);
          recordSelection(id, stepIndex, step, mode, 'null', tier);
        }

        const finalState = stateJSON(`status ${id}`);
        const selections = finalState.modelSelections as Array<Record<string, unknown>>;
        expect(selections).toHaveLength(5);
        expect(selections.filter((s) => s.tier === 'opus')).toHaveLength(0);
        expect(selections.filter((s) => s.tier === 'sonnet')).toHaveLength(4);
        expect(selections.filter((s) => s.tier === 'haiku')).toHaveLength(1);
      });
    });

    describe('Example C — two-stage feature (init sonnet → post-plan opus)', () => {
      it('feature with init medium + 4-phase plan upgrades to high; audit trail shows stage transition', () => {
        const id = 'FEAT-101';
        stateJSON(`init ${id} feature`);
        seedArtifact(`requirements/features/${id}-example-c.md`, 'feature-medium-no-bump.md');

        // Init classification (8 FRs without a perf/security/auth NFR → medium).
        const initTier = stateCmd(`classify-init ${id} requirements/features/${id}-example-c.md`);
        expect(initTier).toBe('medium');
        stateCmd(`set-complexity ${id} ${initTier}`);

        // Steps 2 and 3 resolve on init stage → sonnet (baseline) + medium → sonnet.
        const t2 = resolveTier(id, 'reviewing-requirements');
        expect(t2).toBe('sonnet');
        recordSelection(id, 1, 'reviewing-requirements', 'standard', 'null', t2);

        const t3 = resolveTier(id, 'creating-implementation-plans');
        expect(t3).toBe('sonnet');
        recordSelection(id, 2, 'creating-implementation-plans', 'null', 'null', t3);

        // Post-plan re-classification (FR-2b): 4-phase plan → high → opus.
        seedPlan(id, 'feature-low-plan-4phase.md');
        const postPlanTier = stateCmd(`classify-post-plan ${id}`);
        expect(postPlanTier).toBe('high');

        // Verify complexityStage transitioned.
        const midState = stateJSON(`status ${id}`);
        expect(midState.complexity).toBe('high');
        expect(midState.complexityStage).toBe('post-plan');

        // Downstream forks (step 6 onward) resolve on post-plan stage → opus.
        const t6 = resolveTier(id, 'reviewing-requirements');
        expect(t6).toBe('opus');
        recordSelection(id, 5, 'reviewing-requirements', 'test-plan', 'null', t6);

        // Phase loop: 4 phases of implementing-plan-phases → opus.
        for (let phase = 1; phase <= 4; phase++) {
          const tPhase = resolveTier(id, 'implementing-plan-phases');
          expect(tPhase).toBe('opus');
          recordSelection(id, 5 + phase, 'implementing-plan-phases', 'null', String(phase), tPhase);
        }

        // PR creation (baseline-locked haiku) and code-review reconcile (opus post-plan).
        const tPr = resolveTier(id, 'pr-creation');
        expect(tPr).toBe('haiku');
        recordSelection(id, 10, 'pr-creation', 'null', 'null', tPr);

        const tReconcile = resolveTier(id, 'reviewing-requirements');
        expect(tReconcile).toBe('opus');
        recordSelection(id, 12, 'reviewing-requirements', 'code-review', 'null', tReconcile);

        // Finalize (baseline-locked haiku).
        const tFinal = resolveTier(id, 'finalizing-workflow');
        expect(tFinal).toBe('haiku');
        recordSelection(id, 14, 'finalizing-workflow', 'null', 'null', tFinal);

        // Audit trail assertions.
        const finalState = stateJSON(`status ${id}`);
        const selections = finalState.modelSelections as Array<Record<string, unknown>>;
        expect(selections).toHaveLength(10);

        // Steps 2 and 3 are init-stage; everything after post-plan recomputation is post-plan.
        const initEntries = selections.filter((s) => s.complexityStage === 'init');
        const postPlanEntries = selections.filter((s) => s.complexityStage === 'post-plan');
        expect(initEntries).toHaveLength(2);
        expect(postPlanEntries).toHaveLength(8);

        // Init entries are sonnet (baseline floor).
        for (const s of initEntries) {
          expect(s.tier).toBe('sonnet');
        }

        // Post-plan non-locked entries are opus (review, plan phases × 4, code-review).
        const nonLockedPostPlan = postPlanEntries.filter(
          (s) => s.skill !== 'finalizing-workflow' && s.skill !== 'pr-creation'
        );
        expect(nonLockedPostPlan).toHaveLength(6);
        for (const s of nonLockedPostPlan) {
          expect(s.tier).toBe('opus');
        }

        // Baseline-locked post-plan entries stay at haiku.
        const locked = postPlanEntries.filter(
          (s) => s.skill === 'finalizing-workflow' || s.skill === 'pr-creation'
        );
        expect(locked).toHaveLength(2);
        for (const s of locked) {
          expect(s.tier).toBe('haiku');
        }
      });
    });
  });
});

// --- Chore Chain SKILL.md Validation Tests ---

describe('orchestrating-workflows SKILL.md chore chain content', () => {
  let skillMd: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
  });

  it('should contain "Chore Chain Step Sequence" section', () => {
    expect(skillMd).toContain('## Chore Chain Step Sequence');
  });

  it('should reference documenting-chores sub-skill', () => {
    expect(skillMd).toContain('documenting-chores');
  });

  it('should reference executing-chores sub-skill', () => {
    expect(skillMd).toContain('executing-chores');
  });

  it('should document chore chain in "Relationship to Other Skills" section', () => {
    // Extract the Relationship section content
    const relationshipIdx = skillMd.indexOf('## Relationship to Other Skills');
    expect(relationshipIdx).toBeGreaterThan(-1);
    const relationshipSection = skillMd.slice(relationshipIdx);

    expect(relationshipSection).toContain('Chore chain');
    expect(relationshipSection).toContain('documenting-chores');
    expect(relationshipSection).toContain('executing-chores');
  });
});

// --- Bug Chain SKILL.md Validation Tests ---

describe('orchestrating-workflows SKILL.md bug chain content', () => {
  let skillMd: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
  });

  it('should contain "Bug Chain Step Sequence" section', () => {
    expect(skillMd).toContain('## Bug Chain Step Sequence');
  });

  it('should reference documenting-bugs sub-skill', () => {
    expect(skillMd).toContain('documenting-bugs');
  });

  it('should reference executing-bug-fixes sub-skill', () => {
    expect(skillMd).toContain('executing-bug-fixes');
  });

  it('should document bug chain in "Relationship to Other Skills" section', () => {
    const relationshipIdx = skillMd.indexOf('## Relationship to Other Skills');
    expect(relationshipIdx).toBeGreaterThan(-1);
    const relationshipSection = skillMd.slice(relationshipIdx);

    expect(relationshipSection).toContain('Bug chain');
    expect(relationshipSection).toContain('documenting-bugs');
    expect(relationshipSection).toContain('executing-bug-fixes');
  });
});

// --- Managing Work Items Integration Tests ---

describe('orchestrating-workflows SKILL.md managing-work-items integration', () => {
  let skillMd: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
  });

  it('should reference managing-work-items skill', () => {
    expect(skillMd).toContain('managing-work-items');
  });

  it('should document issue reference extraction via FR-7', () => {
    expect(skillMd).toContain('Issue Reference Extraction');
    expect(skillMd).toContain('FR-7');
  });

  it('should document skip behavior when no issue reference found', () => {
    expect(skillMd).toContain('Skip Behavior');
    expect(skillMd).toContain('skipped');
  });

  it('should contain managing-work-items invocation points for feature chain', () => {
    // Phase start/completion comments around implementing-plan-phases
    expect(skillMd).toContain('phase-start');
    expect(skillMd).toContain('phase-completion');
    // FR-6 issue link at PR creation
    expect(skillMd).toContain('FR-6');
  });

  it('should contain managing-work-items invocation points for chore chain', () => {
    expect(skillMd).toContain('work-start');
    expect(skillMd).toContain('work-complete');
  });

  it('should contain managing-work-items invocation points for bug chain', () => {
    expect(skillMd).toContain('bug-start');
    expect(skillMd).toContain('bug-complete');
  });

  it('should document fetch operation for issue data retrieval', () => {
    expect(skillMd).toContain('managing-work-items fetch');
  });

  it('should document comment operation at correct workflow points', () => {
    expect(skillMd).toContain('managing-work-items comment');
  });

  it('should include managing-work-items in relationship chain diagrams', () => {
    const relationshipIdx = skillMd.indexOf('## Relationship to Other Skills');
    expect(relationshipIdx).toBeGreaterThan(-1);
    const relationshipSection = skillMd.slice(relationshipIdx);

    // All three chain diagrams should reference managing-work-items
    expect(relationshipSection).toContain('managing-work-items');
  });

  it('should include managing-work-items in all three chain skill tables', () => {
    const relationshipIdx = skillMd.indexOf('## Relationship to Other Skills');
    expect(relationshipIdx).toBeGreaterThan(-1);
    const relationshipSection = skillMd.slice(relationshipIdx);

    // Count managing-work-items rows in the skill tables (one per chain)
    const tableRowMatches = relationshipSection.match(
      /\| Issue tracking.*\| `managing-work-items`/g
    );
    expect(tableRowMatches).not.toBeNull();
    expect(tableRowMatches!.length).toBe(3);
  });

  it('should include managing-work-items checks in verification checklist', () => {
    const checklistIdx = skillMd.indexOf('## Verification Checklist');
    expect(checklistIdx).toBeGreaterThan(-1);
    const checklistSection = skillMd.slice(checklistIdx);

    expect(checklistSection).toContain('Managing Work Items Checks');
    expect(checklistSection).toContain('Issue reference extracted');
    expect(checklistSection).toContain('gracefully skipped');
  });
});
