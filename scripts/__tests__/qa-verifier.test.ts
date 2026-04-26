import { describe, it, expect, beforeAll } from 'vitest';
import { readFile, access } from 'node:fs/promises';
import { join } from 'node:path';

// FEAT-030 Phase 3: both agent files were deleted; the behavior they described
// is now implemented in scripts. These tests verify the replacement scripts
// exist and honor the behavioral contract previously documented by the agents.

const VERIFY_SCRIPT_PATH = join(
  'plugins',
  'lwndev-sdlc',
  'skills',
  'executing-qa',
  'scripts',
  'qa-verify-coverage.sh'
);
const RECONCILE_SCRIPT_PATH = join(
  'plugins',
  'lwndev-sdlc',
  'skills',
  'executing-qa',
  'scripts',
  'qa-reconcile-delta.sh'
);
const AGENTS_DIR = join('plugins', 'lwndev-sdlc', 'agents');

describe('qa-verifier replacement (qa-verify-coverage.sh)', () => {
  let scriptSh: string;

  beforeAll(async () => {
    scriptSh = await readFile(VERIFY_SCRIPT_PATH, 'utf-8');
  });

  describe('script file', () => {
    it('should exist and have content', () => {
      expect(scriptSh).toBeDefined();
      expect(scriptSh.length).toBeGreaterThan(0);
    });

    it('should be a bash script', () => {
      expect(scriptSh).toMatch(/^#!.*bash/);
    });
  });

  describe('behavioral contract', () => {
    it('should reference all five adversarial dimensions', () => {
      expect(scriptSh).toContain('Inputs');
      expect(scriptSh).toContain('State transitions');
      expect(scriptSh).toContain('Environment');
      expect(scriptSh).toContain('Dependency failure');
      expect(scriptSh).toContain('Cross-cutting');
    });

    it('should validate priority labels P0/P1/P2', () => {
      expect(scriptSh).toMatch(/P0/);
      expect(scriptSh).toMatch(/P1/);
      expect(scriptSh).toMatch(/P2/);
    });

    it('should validate execution modes test-framework and exploratory', () => {
      expect(scriptSh).toContain('test-framework');
      expect(scriptSh).toContain('exploratory');
    });

    it('should implement the empty-findings-is-suspicious directive', () => {
      expect(scriptSh).toMatch(/empty.?findings|zero findings/i);
    });

    it('should implement no-spec drift detection', () => {
      expect(scriptSh).toMatch(/FR-|spec.*drift|drift/i);
    });

    it('should emit COVERAGE-ADEQUATE or COVERAGE-GAPS verdict', () => {
      expect(scriptSh).toContain('COVERAGE-ADEQUATE');
      expect(scriptSh).toContain('COVERAGE-GAPS');
    });

    it('should exit 2 on missing/invalid args', () => {
      expect(scriptSh).toContain('exit 2');
    });
  });
});

describe('qa-reconciliation-agent replacement (qa-reconcile-delta.sh)', () => {
  let scriptSh: string;

  beforeAll(async () => {
    scriptSh = await readFile(RECONCILE_SCRIPT_PATH, 'utf-8');
  });

  describe('script file', () => {
    it('should exist and have content', () => {
      expect(scriptSh).toBeDefined();
      expect(scriptSh.length).toBeGreaterThan(0);
    });

    it('should be a bash script', () => {
      expect(scriptSh).toMatch(/^#!.*bash/);
    });
  });

  describe('behavioral contract', () => {
    it('should emit coverage-surplus and coverage-gap output', () => {
      expect(scriptSh).toContain('coverage-surplus');
      expect(scriptSh).toContain('coverage-gap');
    });

    it('should handle missing requirements doc gracefully', () => {
      // exit 1 path for missing requirements doc
      expect(scriptSh).toContain('exit 1');
    });

    it('should emit the three-subsection reconciliation delta structure', () => {
      expect(scriptSh).toContain('Coverage beyond requirements');
      expect(scriptSh).toContain('Coverage gaps');
      expect(scriptSh).toContain('Summary');
    });
  });
});

describe('agent files deleted (FEAT-030 Phase 3)', () => {
  it('qa-verifier.md must not exist', async () => {
    const path = join(AGENTS_DIR, 'qa-verifier.md');
    await expect(access(path)).rejects.toThrow();
  });

  it('qa-reconciliation-agent.md must not exist', async () => {
    const path = join(AGENTS_DIR, 'qa-reconciliation-agent.md');
    await expect(access(path)).rejects.toThrow();
  });
});
