import { describe, it, expect, beforeAll } from 'vitest';
import { readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/managing-source-control';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const SCRIPTS_DIR = join(SKILL_DIR, 'scripts');
const REFERENCES_DIR = join(SKILL_DIR, 'references');
const BACKEND_DETECT_PATH = join(SCRIPTS_DIR, 'backend-detect.sh');
const BRANCH_CONVENTIONS_PATH = join(REFERENCES_DIR, 'branch-conventions.md');
const COMMIT_CONVENTIONS_PATH = join(REFERENCES_DIR, 'commit-conventions.md');

async function exists(path: string): Promise<boolean> {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

describe('managing-source-control skill', () => {
  let skillMd: string;
  let branchConventions: string;
  let commitConventions: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    branchConventions = await readFile(BRANCH_CONVENTIONS_PATH, 'utf-8');
    commitConventions = await readFile(COMMIT_CONVENTIONS_PATH, 'utf-8');
  });

  describe('skill directory structure', () => {
    it('should have SKILL.md at the expected path', () => {
      expect(skillMd.length).toBeGreaterThan(0);
    });

    it('should have scripts/ directory', async () => {
      expect(await exists(SCRIPTS_DIR)).toBe(true);
    });

    it('should have references/ directory', async () => {
      expect(await exists(REFERENCES_DIR)).toBe(true);
    });

    it('should have scripts/backend-detect.sh', async () => {
      expect(await exists(BACKEND_DETECT_PATH)).toBe(true);
    });

    it('should have references/branch-conventions.md', () => {
      expect(branchConventions.length).toBeGreaterThan(0);
    });

    it('should have references/commit-conventions.md', () => {
      expect(commitConventions.length).toBeGreaterThan(0);
    });
  });

  describe('SKILL.md frontmatter', () => {
    it('should have frontmatter with name: managing-source-control', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*managing-source-control[\s\S]*?---/);
    });

    it('should have frontmatter with non-empty description', () => {
      const match = skillMd.match(/^---\s*\n[\s\S]*?description:\s*(.+)[\s\S]*?---/);
      expect(match).not.toBeNull();
      expect(match![1].trim().length).toBeGreaterThan(0);
    });

    it('should have allowed-tools including Read, Write, Edit, Bash, Glob, Grep', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('- Read');
      expect(frontmatter).toContain('- Write');
      expect(frontmatter).toContain('- Edit');
      expect(frontmatter).toContain('- Bash');
      expect(frontmatter).toContain('- Glob');
      expect(frontmatter).toContain('- Grep');
    });

    it('should have argument-hint with operation', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('argument-hint:');
      expect(frontmatter).toMatch(/argument-hint:.*operation/);
    });
  });

  describe('SKILL.md content', () => {
    it('should document backend detection (FR-1)', () => {
      expect(skillMd).toContain('Backend Detection');
      expect(skillMd).toContain('github');
      expect(skillMd).toContain('azdo');
      expect(skillMd).toContain('SDLC_SCM_BACKEND');
    });

    it('should document the GitHub URL forms (HTTPS + SSH)', () => {
      expect(skillMd).toContain('github.com');
      expect(skillMd).toContain('git@github.com');
    });

    it('should document the Azure DevOps URL forms', () => {
      expect(skillMd).toContain('dev.azure.com');
      expect(skillMd).toContain('visualstudio.com');
      expect(skillMd).toContain('ssh.dev.azure.com');
    });

    it('should document inline-execution semantics', () => {
      expect(skillMd).toContain('inline');
      expect(skillMd).toContain('NOT spawned via the Agent tool');
    });

    it('should document graceful degradation (NFR-1) with the matrix', () => {
      expect(skillMd).toContain('Graceful Degradation');
      expect(skillMd).toContain('never');
      expect(skillMd).toContain('block workflow');
      expect(skillMd).toContain('GitHub CLI (gh) not found on PATH');
      expect(skillMd).toContain('Azure CLI (az) not found on PATH');
      expect(skillMd).toContain('az devops extension');
      expect(skillMd).toContain('No recognized SCM backend');
    });

    it('should document lite narration rules and load-bearing carve-outs', () => {
      expect(skillMd).toContain('Lite narration rules');
      expect(skillMd).toContain('Load-bearing carve-outs');
      expect(skillMd).toContain('No emoji');
    });

    it('should document output format examples for JSON and tagged logs', () => {
      expect(skillMd).toContain('Output Format');
      expect(skillMd).toContain('"backend":"github"');
      expect(skillMd).toContain('"backend":"azdo"');
      expect(skillMd).toContain('[info]');
      expect(skillMd).toContain('[warn]');
    });

    it('should list all 9 script entry points', () => {
      expect(skillMd).toContain('backend-detect.sh');
      expect(skillMd).toContain('ensure-branch.sh');
      expect(skillMd).toContain('build-branch-name.sh');
      expect(skillMd).toContain('commit-work.sh');
      expect(skillMd).toContain('create-pr.sh');
      expect(skillMd).toContain('merge-pr.sh');
      expect(skillMd).toContain('view-pr.sh');
      expect(skillMd).toContain('list-pr.sh');
      expect(skillMd).toContain('pr-diff.sh');
    });
  });

  describe('references/branch-conventions.md', () => {
    it('should document branch prefixes feat/, chore/, fix/', () => {
      expect(branchConventions).toContain('feat/');
      expect(branchConventions).toContain('chore/');
      expect(branchConventions).toContain('fix/');
    });

    it('should document the naming format', () => {
      expect(branchConventions).toMatch(/<prefix>\/<WORK-ID>-<slug>/);
    });

    it('should document slug rules', () => {
      expect(branchConventions).toContain('kebab-case');
      expect(branchConventions).toContain('Lowercase');
    });
  });

  describe('references/commit-conventions.md', () => {
    it('should document conventional commit format', () => {
      expect(commitConventions).toContain('<type>(<scope>): <subject>');
    });

    it('should document type → branch-prefix mapping', () => {
      expect(commitConventions).toContain('feat');
      expect(commitConventions).toContain('chore');
      expect(commitConventions).toContain('fix');
      expect(commitConventions).toContain('BUG-');
    });

    it('should provide example commits for feat / chore / fix', () => {
      expect(commitConventions).toMatch(/feat\(FEAT-\d+\)/);
      expect(commitConventions).toMatch(/chore\(CHORE-\d+\)/);
      expect(commitConventions).toMatch(/fix\(BUG-\d+\)/);
    });
  });

  describe('validation API', () => {
    it('should pass ai-skills-manager validation', async () => {
      const result: DetailedValidateResult = await validate(SKILL_DIR, {
        detailed: true,
      });
      expect(result.valid).toBe(true);
    });
  });
});
