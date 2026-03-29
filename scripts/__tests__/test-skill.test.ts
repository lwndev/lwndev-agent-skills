import { describe, it, expect, beforeEach, afterAll } from 'vitest';
import { access, rm, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { execSync } from 'node:child_process';
import { PROJECT_SKILLS_DIR, PROJECT_AGENTS_DIR } from '../lib/constants.js';

const TEST_SKILL = 'documenting-features';
const TEST_AGENT = 'qa-verifier';
const COPIED_SKILL_PATH = join(PROJECT_SKILLS_DIR, TEST_SKILL);
const COPIED_AGENT_PATH = join(PROJECT_AGENTS_DIR, `${TEST_AGENT}.md`);

function run(args: string): string {
  return execSync(`tsx scripts/test-skill.ts ${args}`, {
    stdio: 'pipe',
    encoding: 'utf-8',
  });
}

describe('test-skill script', () => {
  beforeEach(async () => {
    // Clean up any leftover test artifacts
    await rm(COPIED_SKILL_PATH, { recursive: true, force: true }).catch(() => {});
    await rm(COPIED_AGENT_PATH, { force: true }).catch(() => {});
  });

  afterAll(async () => {
    await rm(COPIED_SKILL_PATH, { recursive: true, force: true }).catch(() => {});
    await rm(COPIED_AGENT_PATH, { force: true }).catch(() => {});
  });

  describe('copying skills', () => {
    it('should copy a plugin skill to project scope', async () => {
      const output = run(TEST_SKILL);

      expect(output).toContain('Copied skill');
      expect(output).toContain(TEST_SKILL);
      await expect(access(COPIED_SKILL_PATH)).resolves.toBeUndefined();
      await expect(access(join(COPIED_SKILL_PATH, 'SKILL.md'))).resolves.toBeUndefined();
    });

    it('should copy the full skill directory including subdirectories', async () => {
      run(TEST_SKILL);

      // The source skill should have SKILL.md at minimum
      const content = await readFile(join(COPIED_SKILL_PATH, 'SKILL.md'), 'utf-8');
      expect(content).toContain('name:');
      expect(content).toContain('description:');
    });

    it('should overwrite existing skill with warning', async () => {
      // Copy once
      run(TEST_SKILL);
      // Copy again — should warn and overwrite
      const output = run(TEST_SKILL);

      expect(output).toContain('already exists');
      expect(output).toContain('overwriting');
      await expect(access(COPIED_SKILL_PATH)).resolves.toBeUndefined();
    });

    it('should fail for nonexistent skill', () => {
      expect(() => run('nonexistent-skill-xyz')).toThrow();
    });

    it('should list available skills on error', () => {
      try {
        run('nonexistent-skill-xyz');
        expect.fail('should have thrown');
      } catch (err: unknown) {
        const error = err as { stdout: string };
        expect(error.stdout).toContain('Available skill');
      }
    });
  });

  describe('copying agents', () => {
    it('should copy a plugin agent to project scope', async () => {
      const output = run(`${TEST_AGENT} --agent`);

      expect(output).toContain('Copied agent');
      expect(output).toContain(TEST_AGENT);
      await expect(access(COPIED_AGENT_PATH)).resolves.toBeUndefined();
    });

    it('should copy agent as a single .md file', async () => {
      run(`${TEST_AGENT} --agent`);

      const content = await readFile(COPIED_AGENT_PATH, 'utf-8');
      expect(content).toContain('---');
      // qa-verifier has model: sonnet in frontmatter
      expect(content).toContain('model:');
    });

    it('should fail for nonexistent agent', () => {
      expect(() => run('nonexistent-agent-xyz --agent')).toThrow();
    });
  });

  describe('removing', () => {
    it('should remove a copied skill', async () => {
      run(TEST_SKILL);
      await expect(access(COPIED_SKILL_PATH)).resolves.toBeUndefined();

      const output = run(`${TEST_SKILL} --remove`);

      expect(output).toContain('Removed skill');
      await expect(access(COPIED_SKILL_PATH)).rejects.toThrow();
    });

    it('should remove a copied agent', async () => {
      run(`${TEST_AGENT} --agent`);
      await expect(access(COPIED_AGENT_PATH)).resolves.toBeUndefined();

      const output = run(`${TEST_AGENT} --agent --remove`);

      expect(output).toContain('Removed agent');
      await expect(access(COPIED_AGENT_PATH)).rejects.toThrow();
    });

    it('should handle removing nonexistent skill gracefully', () => {
      const output = run(`${TEST_SKILL} --remove`);
      expect(output).toContain('Nothing to remove');
    });

    it('should handle removing nonexistent agent gracefully', () => {
      const output = run(`${TEST_AGENT} --agent --remove`);
      expect(output).toContain('Nothing to remove');
    });
  });

  describe('help', () => {
    it('should print usage and exit 0 with --help', () => {
      const output = execSync('tsx scripts/test-skill.ts --help', {
        stdio: 'pipe',
        encoding: 'utf-8',
      });
      expect(output).toContain('Usage:');
      expect(output).toContain('--plugin');
      expect(output).toContain('--agent');
      expect(output).toContain('--remove');
    });
  });

  describe('plugin auto-detection', () => {
    it('should auto-detect the single plugin', () => {
      // Should work without --plugin flag since there's only one plugin
      const output = run(TEST_SKILL);
      expect(output).toContain('lwndev-sdlc');
    });

    it('should accept explicit --plugin flag', () => {
      const output = run(`${TEST_SKILL} --plugin lwndev-sdlc`);
      expect(output).toContain('lwndev-sdlc');
    });
  });
});
