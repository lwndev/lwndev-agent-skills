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
});
