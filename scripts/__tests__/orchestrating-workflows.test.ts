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
const REFERENCES_DIR = join(SKILL_DIR, 'references');
const MODEL_SELECTION_REF = join(REFERENCES_DIR, 'model-selection.md');
const ISSUE_TRACKING_REF = join(REFERENCES_DIR, 'issue-tracking.md');
const CHAIN_PROCEDURES_REF = join(REFERENCES_DIR, 'chain-procedures.md');
const STEP_EXECUTION_DETAILS_REF = join(REFERENCES_DIR, 'step-execution-details.md');
const VERIFICATION_REF = join(REFERENCES_DIR, 'verification-and-relationships.md');

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
      expect(prefixedRefs!.length).toBe(18);
    });

    it('should include "When to Use This Skill" section', () => {
      expect(skillMd).toContain('## When to Use This Skill');
    });

    it('should include "Quick Start" section', () => {
      expect(skillMd).toContain('## Quick Start');
    });

    it('should include "Verification Checklist and Skill Relationships" section with link to reference', () => {
      expect(skillMd).toContain('## Verification Checklist and Skill Relationships');
      expect(skillMd).toContain('references/verification-and-relationships.md');
    });

    it('should reference all sub-skills in step sequence tables', () => {
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

    it('should document pause points in step sequence tables', () => {
      expect(skillMd).toContain('Plan approval');
      expect(skillMd).toContain('PR review');
      expect(skillMd).toContain('pause');
    });

    it('should document PR suppression instruction in step execution details reference', async () => {
      const refContent = await readFile(
        join(SKILL_DIR, 'references/step-execution-details.md'),
        'utf-8'
      );
      expect(refContent).toContain('Do NOT create a pull request at the end');
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

  describe('extracted reference files', () => {
    it('should have references/issue-tracking.md', () => {
      expect(existsSync(ISSUE_TRACKING_REF)).toBe(true);
    });

    it('should have references/chain-procedures.md', () => {
      expect(existsSync(CHAIN_PROCEDURES_REF)).toBe(true);
    });

    it('should have references/step-execution-details.md', () => {
      expect(existsSync(STEP_EXECUTION_DETAILS_REF)).toBe(true);
    });

    it('should have references/verification-and-relationships.md', () => {
      expect(existsSync(VERIFICATION_REF)).toBe(true);
    });

    it('issue-tracking.md should contain the full issue tracking protocol', async () => {
      const content = await readFile(ISSUE_TRACKING_REF, 'utf-8');
      expect(content).toContain('## Issue Tracking via `managing-work-items`');
      expect(content).toContain('How to Invoke `managing-work-items`');
      expect(content).toContain('Mechanism-Failure Logging');
    });

    it('chain-procedures.md should contain all workflow procedures', async () => {
      const content = await readFile(CHAIN_PROCEDURES_REF, 'utf-8');
      expect(content).toContain('## New Feature Workflow Procedure');
      expect(content).toContain('## New Chore Workflow Procedure');
      expect(content).toContain('## New Bug Workflow Procedure');
      expect(content).toContain('## Resume Procedure');
    });

    it('step-execution-details.md should contain chain-specific fork instructions', async () => {
      const content = await readFile(STEP_EXECUTION_DETAILS_REF, 'utf-8');
      expect(content).toContain('Feature Chain Step-Specific Fork Instructions');
      expect(content).toContain('Chore Chain Step-Specific Fork Instructions');
      expect(content).toContain('Bug Chain Step-Specific Fork Instructions');
      expect(content).toContain('Pause Steps');
      expect(content).toContain('Phase Loop');
      expect(content).toContain('PR Creation');
    });

    it('verification-and-relationships.md should contain checklists and relationship section', async () => {
      const content = await readFile(VERIFICATION_REF, 'utf-8');
      expect(content).toContain('## Verification Checklist');
      expect(content).toContain('## Relationship to Other Skills');
      expect(content).toContain('Feature Chain Skills');
      expect(content).toContain('Chore Chain Skills');
      expect(content).toContain('Bug Chain Skills');
    });
  });

  describe('FEAT-014 Phase 5 Model Selection documentation', () => {
    let refMd: string;

    beforeAll(async () => {
      refMd = await readFile(MODEL_SELECTION_REF, 'utf-8');
    });

    describe('references/model-selection.md', () => {
      it('should exist as a file under references/', () => {
        expect(existsSync(REFERENCES_DIR)).toBe(true);
        expect(existsSync(MODEL_SELECTION_REF)).toBe(true);
      });

      it('should contain the FR-3 classification algorithm pseudocode', () => {
        expect(refMd).toContain('FR-3');
        expect(refMd).toContain('resolve-tier');
        expect(refMd).toContain('walk the override chain');
        expect(refMd).toContain('step_baseline(step_name)');
        expect(refMd).toContain('complexity_to_tier');
        expect(refMd).toContain('first non-null wins');
      });

      it('should contain tuning guidance for per-step baselines', () => {
        expect(refMd).toContain('Tuning per-step baselines');
        expect(refMd).toContain('Raising a baseline');
        expect(refMd).toContain('Lowering a baseline');
      });

      it('should explain how to read the modelSelections audit trail field-by-field', () => {
        expect(refMd).toContain('Reading the `modelSelections` audit trail');
        expect(refMd).toContain('`stepIndex`');
        expect(refMd).toContain('`skill`');
        expect(refMd).toContain('`mode`');
        expect(refMd).toContain('`phase`');
        expect(refMd).toContain('`tier`');
        expect(refMd).toContain('`complexityStage`');
        expect(refMd).toContain('`startedAt`');
      });

      it('should document known limitations', () => {
        expect(refMd).toContain('Known limitations');
        expect(refMd).toContain('Haiku is never selected for `implementing-plan-phases`');
      });

      it('should provide migration guidance for the old inherit-parent behavior', () => {
        expect(refMd).toContain('Migration guidance');
        expect(refMd).toContain('--model opus');
        expect(refMd).toContain('wrapper');
      });

      it('should cross-reference FR-5 for why requirement docs have no complexity/model-override frontmatter', () => {
        expect(refMd).toContain('FR-5');
        expect(refMd).toContain('frontmatter');
        expect(refMd).toContain('requirement doc');
      });
    });

    describe('SKILL.md "Model Selection" section', () => {
      it('should have "## Model Selection" as a top-level section', () => {
        expect(skillMd).toMatch(/^## Model Selection$/m);
      });

      it('should be positioned between "## Step Execution" and "## Error Handling"', () => {
        const stepExecIdx = skillMd.indexOf('\n## Step Execution\n');
        const modelSelIdx = skillMd.indexOf('\n## Model Selection\n');
        const errorIdx = skillMd.indexOf('\n## Error Handling\n');
        expect(stepExecIdx).toBeGreaterThan(-1);
        expect(modelSelIdx).toBeGreaterThan(-1);
        expect(errorIdx).toBeGreaterThan(-1);
        expect(modelSelIdx).toBeGreaterThan(stepExecIdx);
        expect(modelSelIdx).toBeLessThan(errorIdx);
      });

      it('should not retain the temporary "Phase 2 prose" heading', () => {
        expect(skillMd).not.toContain('Model Selection — Algorithm Reference (Phase 2 prose)');
        expect(skillMd).not.toContain('Phase-5 move note');
      });

      it('should summarize step baseline matrix (Axis 1) with link to reference', () => {
        const start = skillMd.indexOf('\n## Model Selection\n');
        const end = skillMd.indexOf('\n## Error Handling\n', start);
        const section = skillMd.slice(start, end);
        expect(section).toContain('Axis 1');
        expect(section).toContain('Step baseline');
        expect(section).toContain('references/model-selection.md');
      });

      it('should summarize work-item complexity signal matrix (Axis 2) with link to reference', () => {
        const start = skillMd.indexOf('\n## Model Selection\n');
        const end = skillMd.indexOf('\n## Error Handling\n', start);
        const section = skillMd.slice(start, end);
        expect(section).toContain('Axis 2');
        expect(section).toContain('complexity');
        expect(section).toContain('references/model-selection.md');
      });

      it('should document override precedence (Axis 3) with hard vs soft distinction', () => {
        const start = skillMd.indexOf('\n## Model Selection\n');
        const end = skillMd.indexOf('\n## Error Handling\n', start);
        const section = skillMd.slice(start, end);
        expect(section).toContain('Axis 3');
        expect(section).toContain('`--model-for');
        expect(section).toContain('`--model <tier>`');
        expect(section).toContain('`--complexity');
        expect(section).toContain('modelOverride');
        expect(section).toContain('hard');
        expect(section).toContain('soft');
      });

      it('should document baseline-locked step exceptions', () => {
        const start = skillMd.indexOf('\n## Model Selection\n');
        const end = skillMd.indexOf('\n## Error Handling\n', start);
        const section = skillMd.slice(start, end);
        expect(section).toContain('Baseline-locked');
        expect(section).toContain('finalizing-workflow');
        expect(section).toContain('PR-creation');
      });

      it('should not contain worked examples (moved to reference)', () => {
        const start = skillMd.indexOf('\n## Model Selection\n');
        const end = skillMd.indexOf('\n## Error Handling\n', start);
        const section = skillMd.slice(start, end);
        expect(section).not.toContain('Example A');
        expect(section).not.toContain('Example B');
        expect(section).not.toContain('Example C');
        expect(section).not.toContain('Example D');
      });

      it('should link to references/model-selection.md for deep detail', () => {
        const start = skillMd.indexOf('\n## Model Selection\n');
        const end = skillMd.indexOf('\n## Error Handling\n', start);
        const section = skillMd.slice(start, end);
        expect(section).toContain('references/model-selection.md');
      });
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

    // --- FEAT-014 Phase 4: retry, resume, and version compatibility ---
    //
    // These tests drive the Phase 4 workflow-state.sh subcommands end-to-end
    // to verify the FR-11 retry-with-tier-upgrade progression, the FR-12
    // stage-aware upgrade-only resume re-computation, and the NFR-6 Agent-tool
    // fallback warning + Claude Code version check. The orchestrator-level
    // prose (per-call-site NFR-6 wrapper, FR-11 classifier handling) is
    // exercised indirectly — the shell helpers that back those prose
    // instructions are the load-bearing automation.
    describe('Phase 4 retry, resume, and version compatibility', () => {
      describe('FR-11 next-tier-up helper', () => {
        it('escalates haiku → sonnet', () => {
          expect(stateCmd('next-tier-up haiku')).toBe('sonnet');
        });

        it('escalates sonnet → opus', () => {
          expect(stateCmd('next-tier-up sonnet')).toBe('opus');
        });

        it('exits non-zero at opus (retry exhausted)', () => {
          let caught = false;
          try {
            execSync(`bash "${join(process.cwd(), STATE_SCRIPT)}" next-tier-up opus`, execOpts());
          } catch (err) {
            caught = true;
            const error = err as { status?: number; stderr?: string };
            expect(error.status).toBe(2);
            expect(error.stderr ?? '').toContain('retry exhausted at opus');
          }
          expect(caught).toBe(true);
        });
      });

      describe('FR-11 retry-with-tier-upgrade audit trail', () => {
        it('appends a second modelSelections entry for the retry attempt', () => {
          // Simulate the SKILL.md retry flow: an initial haiku fork fails
          // classifier-flagged, the orchestrator walks next-tier-up, records
          // a new audit entry, re-invokes. The audit trail preserves both.
          const id = 'CHORE-201';
          stateJSON(`init ${id} chore`);
          stateCmd(`set-complexity ${id} low`);

          // Initial attempt at haiku. (executing-chores' Sonnet baseline would
          // normally floor this — for the retry test we simulate a deliberate
          // haiku attempt via the --cli-model hard override.)
          recordSelection(id, 4, 'executing-chores', 'null', 'null', 'haiku');

          // Classifier-flagged failure: empty artifact returned. Walk the
          // tier up and append a retry entry.
          const escalated = stateCmd('next-tier-up haiku');
          expect(escalated).toBe('sonnet');
          recordSelection(id, 4, 'executing-chores', 'null', 'null', escalated);

          const state = stateJSON(`status ${id}`);
          const selections = state.modelSelections as Array<Record<string, unknown>>;
          // Both the original haiku attempt and the sonnet retry are preserved.
          expect(selections).toHaveLength(2);
          expect(selections[0].tier).toBe('haiku');
          expect(selections[0].stepIndex).toBe(4);
          expect(selections[1].tier).toBe('sonnet');
          expect(selections[1].stepIndex).toBe(4);
        });

        it('records fail state after retry exhaustion at opus', () => {
          const id = 'FEAT-201';
          stateJSON(`init ${id} feature`);
          stateCmd(`set-complexity ${id} high`);
          // Advance to step 2 so fail() targets a real step.
          stateCmd(`advance ${id}`);
          stateCmd(`advance ${id}`);

          recordSelection(id, 2, 'creating-implementation-plans', 'null', 'null', 'opus');

          // Attempting to escalate past opus must fail.
          let caught = false;
          try {
            execSync(`bash "${join(process.cwd(), STATE_SCRIPT)}" next-tier-up opus`, execOpts());
          } catch (err) {
            caught = true;
            expect((err as { status?: number }).status).toBe(2);
          }
          expect(caught).toBe(true);

          // The orchestrator would then call `fail` — simulate that.
          stateCmd(`fail ${id} "retry exhausted at opus for step 2"`);
          const state = stateJSON(`status ${id}`);
          expect(state.status).toBe('failed');
          expect(state.error).toBe('retry exhausted at opus for step 2');
        });

        it('does not append retry entries for reviewing-requirements structured findings', () => {
          // Structured findings are NOT classifier-flagged failures; the
          // orchestrator flows them through findings-handling and does not
          // consult next-tier-up. We model that by recording the single
          // initial audit entry and then walking the findings path (which
          // does not touch modelSelections).
          const id = 'BUG-201';
          stateJSON(`init ${id} bug`);
          stateCmd(`set-complexity ${id} medium`);

          recordSelection(id, 1, 'reviewing-requirements', 'standard', 'null', 'sonnet');

          // Simulated subagent return: "Found 2 errors, 1 warnings, 0 info"
          // — orchestrator pauses for findings review, does not retry.
          const state = stateJSON(`status ${id}`);
          const selections = state.modelSelections as Array<Record<string, unknown>>;
          expect(selections).toHaveLength(1);
          expect(selections[0].tier).toBe('sonnet');
        });
      });

      describe('FR-12 resume-recompute (stage-aware upgrade-only)', () => {
        function seedFixture(rel: string, fixtureFile: string): void {
          const abs = join(testDir, rel);
          mkdirSync(join(abs, '..'), { recursive: true });
          const content = execSync(`cat "${fx(fixtureFile)}"`, { encoding: 'utf-8' });
          writeFileSync(abs, content);
        }

        it('silent when signals are unchanged', () => {
          const id = 'CHORE-301';
          stateJSON(`init ${id} chore`);
          seedFixture(`requirements/chores/${id}-medium.md`, 'chore-medium.md');
          stateCmd(`set-complexity ${id} medium`);

          // resume-recompute returns persisted tier, no upgrade log on stderr.
          const output = execSync(
            `bash "${join(process.cwd(), STATE_SCRIPT)}" resume-recompute ${id}`,
            { ...execOpts(), stdio: ['pipe', 'pipe', 'pipe'] }
          )
            .toString()
            .trim();
          expect(output).toBe('medium');

          const state = stateJSON(`status ${id}`);
          expect(state.complexity).toBe('medium');
          expect(state.complexityStage).toBe('init');
        });

        it('logs the upgrade message when signals are upgraded', () => {
          const id = 'CHORE-302';
          stateJSON(`init ${id} chore`);
          // Start at low, then swap the doc to a high-complexity chore.
          seedFixture(`requirements/chores/${id}-low.md`, 'chore-low.md');
          stateCmd(`set-complexity ${id} low`);
          // Now swap in the high fixture (user edited the doc between pause/resume).
          const highContent = execSync(`cat "${fx('chore-high.md')}"`, { encoding: 'utf-8' });
          writeFileSync(join(testDir, `requirements/chores/${id}-low.md`), highContent);

          // Capture stderr from the first (upgrading) resume-recompute call.
          const stderr = execSync(
            `bash "${join(process.cwd(), STATE_SCRIPT)}" resume-recompute ${id} 2>&1 1>/dev/null`,
            execOpts()
          ).toString();
          expect(stderr).toContain('[model] Work-item complexity upgraded since last invocation');
          expect(stderr).toContain('low');
          expect(stderr).toContain('high');

          const state = stateJSON(`status ${id}`);
          expect(state.complexity).toBe('high');
        });

        it('respects manual downgrade via set-complexity (escape hatch)', () => {
          const id = 'CHORE-303';
          stateJSON(`init ${id} chore`);
          seedFixture(`requirements/chores/${id}-high.md`, 'chore-high.md');
          stateCmd(`set-complexity ${id} high`);

          // User explicitly downgrades between pause and resume.
          stateCmd(`set-complexity ${id} low`);
          // resume-recompute would *re-compute* from the high doc and upgrade
          // back, because the upgrade-only rule re-applies the doc signals.
          // This is the documented FR-12 behaviour: set-complexity alone
          // survives resume only if the doc no longer justifies a higher tier.
          // To validate the escape hatch, we remove the doc before resume so
          // resume-recompute has no signal to upgrade from.
          rmSync(join(testDir, `requirements/chores/${id}-high.md`));

          const output = execSync(
            `bash "${join(process.cwd(), STATE_SCRIPT)}" resume-recompute ${id}`,
            execOpts()
          )
            .toString()
            .trim();
          // With no doc, the FR-10 fallback is `medium`. The resolver's
          // upgrade-only rule takes max(low, medium) → medium, so the user's
          // low downgrade is still respected when the doc would have pushed
          // us back up to high (which it no longer can).
          expect(output).toBe('medium');

          const state = stateJSON(`status ${id}`);
          expect(state.complexity).toBe('medium');
        });

        it('complexityStage never regresses', () => {
          const id = 'FEAT-301';
          stateJSON(`init ${id} feature`);
          seedFixture(`requirements/features/${id}-medium.md`, 'feature-medium-no-bump.md');
          stateCmd(`set-complexity ${id} medium`);

          // Manually simulate the post-plan transition that FR-2b would
          // perform: write a plan with 4 phases, then run classify-post-plan.
          const planDir = join(testDir, 'requirements/implementation');
          mkdirSync(planDir, { recursive: true });
          const planContent = execSync(`cat "${fx('feature-low-plan-4phase.md')}"`, {
            encoding: 'utf-8',
          });
          writeFileSync(join(planDir, `${id}-plan.md`), planContent);
          stateCmd(`classify-post-plan ${id}`);

          const midState = stateJSON(`status ${id}`);
          expect(midState.complexityStage).toBe('post-plan');
          expect(midState.complexity).toBe('high');

          // resume-recompute must preserve post-plan stage even if signals
          // unchanged. Run it; stage stays post-plan.
          stateCmd(`resume-recompute ${id}`);
          const postState = stateJSON(`status ${id}`);
          expect(postState.complexityStage).toBe('post-plan');
          expect(postState.complexity).toBe('high');
        });
      });

      describe('FR-13 backward compatibility + Phase 4 resume', () => {
        it('pre-FEAT-014 state file migrates, then resume-recompute populates complexity', () => {
          // Write a legacy state file (no FEAT-014 fields at all).
          const id = 'CHORE-401';
          const legacy = {
            id,
            type: 'chore',
            currentStep: 1,
            status: 'in-progress',
            pauseReason: null,
            steps: [
              {
                name: 'Document chore',
                skill: 'documenting-chores',
                context: 'main',
                status: 'complete',
                artifact: `requirements/chores/${id}.md`,
                completedAt: '2026-04-01T00:00:00Z',
              },
              {
                name: 'Review requirements (standard)',
                skill: 'reviewing-requirements',
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
          mkdirSync(join(testDir, '.sdlc/workflows'), { recursive: true });
          writeFileSync(join(testDir, '.sdlc/workflows', `${id}.json`), JSON.stringify(legacy));
          // Seed a high-complexity chore doc so resume-recompute has a signal.
          mkdirSync(join(testDir, 'requirements/chores'), { recursive: true });
          const highContent = execSync(`cat "${fx('chore-high.md')}"`, { encoding: 'utf-8' });
          writeFileSync(join(testDir, `requirements/chores/${id}.md`), highContent);

          // Status triggers FR-13 migration (adds the four fields with init defaults).
          const migrated = stateJSON(`status ${id}`);
          expect(migrated.complexity).toBeNull();
          expect(migrated.complexityStage).toBe('init');
          expect(migrated.modelOverride).toBeNull();
          expect(migrated.modelSelections).toEqual([]);

          // resume-recompute computes complexity on the first post-migration read.
          stateCmd(`resume-recompute ${id}`);
          const state = stateJSON(`status ${id}`);
          expect(state.complexity).toBe('high');
        });
      });

      describe('NFR-6 Claude Code version check', () => {
        it('exits 0 when claude CLI is unavailable (graceful fallback)', () => {
          // Run the check with a PATH that excludes `claude` so the subcommand
          // takes the "cannot determine version" branch.
          const result = execSync(
            `bash "${join(process.cwd(), STATE_SCRIPT)}" check-claude-version 2.1.72`,
            {
              cwd: testDir,
              encoding: 'utf-8',
              stdio: ['pipe', 'pipe', 'pipe'],
              env: { PATH: '/usr/bin:/bin' },
            }
          );
          // Non-zero would throw execSync; reaching here means exit 0.
          expect(result).toBeDefined();
        });

        it('emits the warning line when current version is below required', () => {
          // Stub a fake claude that reports an old version.
          const stubDir = join(testDir, 'stubs');
          mkdirSync(stubDir, { recursive: true });
          const stub = join(stubDir, 'claude');
          writeFileSync(stub, '#!/usr/bin/env bash\necho "1.0.0 (Claude Code)"\n');
          execSync(`chmod +x "${stub}"`);

          let stderr = '';
          let status: number | undefined;
          try {
            execSync(`bash "${join(process.cwd(), STATE_SCRIPT)}" check-claude-version 2.1.72`, {
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
          expect(stderr).toContain('NFR-6 wrapper');
        });

        it('exits 0 silently when current version meets or exceeds required', () => {
          const stubDir = join(testDir, 'stubs');
          mkdirSync(stubDir, { recursive: true });
          const stub = join(stubDir, 'claude');
          writeFileSync(stub, '#!/usr/bin/env bash\necho "2.5.0 (Claude Code)"\n');
          execSync(`chmod +x "${stub}"`);

          const result = execSync(
            `bash "${join(process.cwd(), STATE_SCRIPT)}" check-claude-version 2.1.72`,
            {
              cwd: testDir,
              encoding: 'utf-8',
              stdio: ['pipe', 'pipe', 'pipe'],
              env: { PATH: `${stubDir}:/usr/bin:/bin` },
            }
          );
          expect(result).toBe('');
        });
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

  it('should document chore chain in verification-and-relationships reference', async () => {
    const refContent = await readFile(VERIFICATION_REF, 'utf-8');
    const relationshipIdx = refContent.indexOf('## Relationship to Other Skills');
    expect(relationshipIdx).toBeGreaterThan(-1);
    const relationshipSection = refContent.slice(relationshipIdx);

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

  it('should document bug chain in verification-and-relationships reference', async () => {
    const refContent = await readFile(VERIFICATION_REF, 'utf-8');
    const relationshipIdx = refContent.indexOf('## Relationship to Other Skills');
    expect(relationshipIdx).toBeGreaterThan(-1);
    const relationshipSection = refContent.slice(relationshipIdx);

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

  it('should document issue reference extraction via FR-7 in issue-tracking reference', async () => {
    const refContent = await readFile(ISSUE_TRACKING_REF, 'utf-8');
    expect(refContent).toContain('Issue Reference Extraction');
    expect(refContent).toContain('FR-7');
  });

  it('should document skip behavior in issue-tracking reference', async () => {
    const refContent = await readFile(ISSUE_TRACKING_REF, 'utf-8');
    expect(refContent).toContain('Skip Behavior');
    expect(refContent).toContain('skipped');
  });

  it('should contain managing-work-items invocation points for feature chain in step-execution-details reference', async () => {
    const refContent = await readFile(STEP_EXECUTION_DETAILS_REF, 'utf-8');
    // Phase start/completion comments around implementing-plan-phases
    expect(refContent).toContain('phase-start');
    expect(refContent).toContain('phase-completion');
    // FR-6 issue link at PR creation
    expect(refContent).toContain('FR-6');
  });

  it('should contain managing-work-items invocation points for chore chain in step-execution-details reference', async () => {
    const refContent = await readFile(STEP_EXECUTION_DETAILS_REF, 'utf-8');
    expect(refContent).toContain('work-start');
    expect(refContent).toContain('work-complete');
  });

  it('should contain managing-work-items invocation points for bug chain in step-execution-details reference', async () => {
    const refContent = await readFile(STEP_EXECUTION_DETAILS_REF, 'utf-8');
    expect(refContent).toContain('bug-start');
    expect(refContent).toContain('bug-complete');
  });

  it('should document fetch operation in issue-tracking reference', async () => {
    const refContent = await readFile(ISSUE_TRACKING_REF, 'utf-8');
    expect(refContent).toContain('managing-work-items fetch');
  });

  it('should document comment operation in step-execution-details reference', async () => {
    const refContent = await readFile(STEP_EXECUTION_DETAILS_REF, 'utf-8');
    expect(refContent).toContain('managing-work-items comment');
  });

  it('should include managing-work-items in relationship chain diagrams in reference', async () => {
    const refContent = await readFile(VERIFICATION_REF, 'utf-8');
    const relationshipIdx = refContent.indexOf('## Relationship to Other Skills');
    expect(relationshipIdx).toBeGreaterThan(-1);
    const relationshipSection = refContent.slice(relationshipIdx);

    // All three chain diagrams should reference managing-work-items
    expect(relationshipSection).toContain('managing-work-items');
  });

  it('should include managing-work-items in all three chain skill tables in reference', async () => {
    const refContent = await readFile(VERIFICATION_REF, 'utf-8');
    const relationshipIdx = refContent.indexOf('## Relationship to Other Skills');
    expect(relationshipIdx).toBeGreaterThan(-1);
    const relationshipSection = refContent.slice(relationshipIdx);

    // Count managing-work-items rows in the skill tables (one per chain)
    const tableRowMatches = relationshipSection.match(
      /\| Issue tracking.*\| `managing-work-items`/g
    );
    expect(tableRowMatches).not.toBeNull();
    expect(tableRowMatches!.length).toBe(3);
  });

  it('should include managing-work-items checks in verification reference', async () => {
    const refContent = await readFile(VERIFICATION_REF, 'utf-8');
    const checklistIdx = refContent.indexOf('## Verification Checklist');
    expect(checklistIdx).toBeGreaterThan(-1);
    const checklistSection = refContent.slice(checklistIdx);

    expect(checklistSection).toContain('Managing Work Items Checks');
    expect(checklistSection).toContain('Issue reference extracted');
    expect(checklistSection).toContain('gracefully skipped');
  });
});
