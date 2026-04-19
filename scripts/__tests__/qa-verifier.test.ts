import { describe, it, expect, beforeAll } from 'vitest';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const AGENT_PATH = join('plugins', 'lwndev-sdlc', 'agents', 'qa-verifier.md');
const RECON_AGENT_PATH = join('plugins', 'lwndev-sdlc', 'agents', 'qa-reconciliation-agent.md');

describe('qa-verifier agent', () => {
  let agentMd: string;

  beforeAll(async () => {
    agentMd = await readFile(AGENT_PATH, 'utf-8');
  });

  describe('agent definition file', () => {
    it('should exist and have content', () => {
      expect(agentMd).toBeDefined();
      expect(agentMd.length).toBeGreaterThan(0);
    });

    it('should have frontmatter with model: sonnet', () => {
      expect(agentMd).toMatch(/^---\s*\n[\s\S]*?model:\s*sonnet[\s\S]*?---/);
    });

    it('should declare tools in frontmatter', () => {
      expect(agentMd).toMatch(/^---\s*\n[\s\S]*?tools:[\s\S]*?---/);
    });

    it('should include Bash, Read, Grep, Glob tools', () => {
      const frontmatter = agentMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('- Bash');
      expect(frontmatter).toContain('- Read');
      expect(frontmatter).toContain('- Grep');
      expect(frontmatter).toContain('- Glob');
    });

    it('should NOT include Write, Edit, or Agent tools', () => {
      const frontmatter = agentMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toContain('- Write');
      expect(frontmatter).not.toContain('- Edit');
      expect(frontmatter).not.toContain('- Agent');
    });
  });

  describe('adversarial-coverage role', () => {
    it('should frame the role as adversarial coverage verification', () => {
      expect(agentMd).toMatch(/adversarial coverage/i);
    });

    it('should disclaim the old closed-loop consistency role', () => {
      // New agent must NOT describe itself as per-entry PASS/FAIL closed-loop
      // verification of every FR-N against the spec.
      expect(agentMd).not.toMatch(/Primary Mode: Direct Verification/);
      expect(agentMd).not.toMatch(/Per-Entry Results/);
      expect(agentMd).not.toMatch(/Verify Each Entry Directly/);
      expect(agentMd).not.toMatch(/RC-N/);
      expect(agentMd).not.toMatch(/verify each FR-N/i);
    });

    it('should explicitly defer spec-vs-plan reconciliation to qa-reconciliation-agent', () => {
      expect(agentMd).toContain('qa-reconciliation-agent');
    });

    it('should name all five adversarial dimensions', () => {
      expect(agentMd).toContain('Inputs');
      expect(agentMd).toContain('State transitions');
      expect(agentMd).toContain('Environment');
      expect(agentMd).toContain('Dependency failure');
      expect(agentMd).toContain('Cross-cutting');
    });

    it('should require priority labels P0/P1/P2 on scenarios', () => {
      expect(agentMd).toMatch(/P0/);
      expect(agentMd).toMatch(/P1/);
      expect(agentMd).toMatch(/P2/);
    });

    it('should require execution modes test-framework and exploratory', () => {
      expect(agentMd).toContain('test-framework');
      expect(agentMd).toContain('exploratory');
    });

    it('should honor the empty-findings-is-suspicious directive (FR-6, FR-8)', () => {
      expect(agentMd).toMatch(/empty findings/i);
    });

    it('should forbid spec-reference drift in plan scenarios', () => {
      expect(agentMd).toMatch(/no[- ]spec drift/i);
    });

    it('should accept QA plan and/or QA results artifact as input', () => {
      expect(agentMd).toContain('QA-plan-');
      expect(agentMd).toContain('QA-results-');
    });

    it('should NOT read the requirements document', () => {
      // Matches "You do **not** read the requirements document." or similar.
      expect(agentMd).toMatch(/do\s+\*?\*?not\*?\*?\s+read the requirements document/i);
    });

    it('should return a COVERAGE-ADEQUATE or COVERAGE-GAPS verdict', () => {
      expect(agentMd).toContain('COVERAGE-ADEQUATE');
      expect(agentMd).toContain('COVERAGE-GAPS');
    });
  });
});

describe('qa-reconciliation-agent', () => {
  let agentMd: string;

  beforeAll(async () => {
    agentMd = await readFile(RECON_AGENT_PATH, 'utf-8');
  });

  describe('agent definition file', () => {
    it('should exist and have content', () => {
      expect(agentMd).toBeDefined();
      expect(agentMd.length).toBeGreaterThan(0);
    });

    it('should have frontmatter with name: qa-reconciliation-agent', () => {
      expect(agentMd).toMatch(/^---\s*\n[\s\S]*?name:\s*qa-reconciliation-agent[\s\S]*?---/);
    });

    it('should have frontmatter with a description mentioning bidirectional delta', () => {
      const frontmatter = agentMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toMatch(/description:/);
      expect(frontmatter).toMatch(/bidirectional/i);
    });

    it('should declare tools in frontmatter including Read and Grep', () => {
      const frontmatter = agentMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('tools:');
      expect(frontmatter).toContain('- Read');
      expect(frontmatter).toContain('- Grep');
    });

    it('should NOT include Write or Edit tools', () => {
      const frontmatter = agentMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toContain('- Write');
      expect(frontmatter).not.toContain('- Edit');
    });
  });

  describe('reconciliation role', () => {
    it('should describe producing a bidirectional coverage-surplus / coverage-gap delta', () => {
      expect(agentMd).toContain('coverage-surplus');
      expect(agentMd).toContain('coverage-gap');
    });

    it('should state that it runs exactly once per execution run', () => {
      expect(agentMd).toMatch(/exactly once/i);
    });

    it('should describe reading both a QA results artifact and a requirements document', () => {
      expect(agentMd).toContain('QA-results-');
      expect(agentMd).toMatch(/requirements\/features\//);
      expect(agentMd).toMatch(/requirements\/chores\//);
      expect(agentMd).toMatch(/requirements\/bugs\//);
    });

    it('should handle a missing requirements document gracefully', () => {
      expect(agentMd).toContain('Reconciliation delta skipped');
    });

    it('should emit the exact three-subsection output structure', () => {
      expect(agentMd).toContain('## Reconciliation Delta');
      expect(agentMd).toContain('### Coverage beyond requirements');
      expect(agentMd).toContain('### Coverage gaps');
      expect(agentMd).toContain('### Summary');
    });

    it('should explicitly refuse to grade surplus or gap', () => {
      expect(agentMd).toMatch(/do not grade/i);
    });

    it('should explicitly refuse to modify the spec or the results artifact', () => {
      // "## What You Do NOT Do" section contains a "Modify ..." bullet.
      expect(agentMd).toMatch(/What You Do NOT Do/);
      expect(agentMd).toMatch(/Modify the requirements document or the results artifact/i);
    });

    it('should forbid reading the requirements doc during planning', () => {
      expect(agentMd).toMatch(/during\s+QA\s+\*?\*?planning/i);
    });
  });
});
