import { describe, it, expect, beforeAll } from 'vitest';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const AGENT_PATH = join('plugins', 'lwndev-sdlc', 'agents', 'qa-verifier.md');

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

  describe('verification responsibilities', () => {
    it('should document test suite execution', () => {
      expect(agentMd).toContain('test suite');
    });

    it('should document test coverage analysis', () => {
      expect(agentMd).toContain('coverage');
    });

    it('should document acceptance criteria verification', () => {
      expect(agentMd).toContain('acceptance criteria');
    });

    it('should include FEAT-specific verification (FR-N)', () => {
      expect(agentMd).toContain('FR-N');
    });

    it('should include BUG-specific verification (RC-N)', () => {
      expect(agentMd).toContain('RC-N');
    });

    it('should include CHORE-specific verification (scope)', () => {
      expect(agentMd).toMatch(/scope/i);
    });

    it('should return structured pass/fail verdict', () => {
      expect(agentMd).toContain('PASS');
      expect(agentMd).toContain('FAIL');
    });
  });
});
