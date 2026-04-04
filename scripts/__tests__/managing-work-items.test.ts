import { describe, it, expect, beforeAll } from 'vitest';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/managing-work-items';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const GITHUB_TEMPLATES_PATH = join(SKILL_DIR, 'references', 'github-templates.md');
const JIRA_TEMPLATES_PATH = join(SKILL_DIR, 'references', 'jira-templates.md');

describe('managing-work-items skill', () => {
  let skillMd: string;
  let githubTemplates: string;
  let jiraTemplates: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    githubTemplates = await readFile(GITHUB_TEMPLATES_PATH, 'utf-8');
    jiraTemplates = await readFile(JIRA_TEMPLATES_PATH, 'utf-8');
  });

  describe('skill directory structure', () => {
    it('should have SKILL.md at the expected path', () => {
      expect(skillMd).toBeDefined();
      expect(skillMd.length).toBeGreaterThan(0);
    });

    it('should have references/github-templates.md', () => {
      expect(githubTemplates).toBeDefined();
      expect(githubTemplates.length).toBeGreaterThan(0);
    });

    it('should have references/jira-templates.md', () => {
      expect(jiraTemplates).toBeDefined();
      expect(jiraTemplates.length).toBeGreaterThan(0);
    });
  });

  describe('SKILL.md frontmatter', () => {
    it('should have frontmatter with name: managing-work-items', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*managing-work-items[\s\S]*?---/);
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

    it('should have argument-hint with operation and issue-ref', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('argument-hint:');
      expect(frontmatter).toMatch(/argument-hint:.*operation/);
    });
  });

  describe('SKILL.md content', () => {
    it('should document backend detection logic (FR-1)', () => {
      expect(skillMd).toContain('Backend Detection');
      expect(skillMd).toContain('#N');
      expect(skillMd).toContain('PROJ-123');
    });

    it('should document GitHub Issues backend operations (FR-2)', () => {
      expect(skillMd).toContain('GitHub Issues Backend');
      expect(skillMd).toContain('gh issue view');
      expect(skillMd).toContain('gh issue comment');
    });

    it('should document comment type routing (FR-5)', () => {
      expect(skillMd).toContain('Comment Type Routing');
      expect(skillMd).toContain('phase-start');
      expect(skillMd).toContain('phase-completion');
      expect(skillMd).toContain('work-start');
      expect(skillMd).toContain('work-complete');
      expect(skillMd).toContain('bug-start');
      expect(skillMd).toContain('bug-complete');
    });

    it('should document PR body issue link generation (FR-6)', () => {
      expect(skillMd).toContain('PR Body Issue Link');
      expect(skillMd).toContain('Closes #N');
    });

    it('should document issue reference extraction (FR-7)', () => {
      expect(skillMd).toContain('Issue Reference Extraction');
      expect(skillMd).toContain('## GitHub Issue');
    });

    it('should document graceful degradation (NFR-1)', () => {
      expect(skillMd).toContain('Graceful Degradation');
      expect(skillMd).toContain('never');
      expect(skillMd).toContain('block workflow');
    });

    it('should document error handling (NFR-2)', () => {
      expect(skillMd).toContain('Error Handling');
      expect(skillMd).toContain('gh auth login');
    });

    it('should document idempotency (NFR-3)', () => {
      expect(skillMd).toContain('Idempotency');
      expect(skillMd).toContain('safe to retry');
    });

    it('should document Jira tiered fallback (FR-3)', () => {
      expect(skillMd).toContain('Jira Backend');
      expect(skillMd).toContain('Rovo MCP');
      expect(skillMd).toContain('acli');
      expect(skillMd).toContain('Tier 1');
      expect(skillMd).toContain('Tier 2');
      expect(skillMd).toContain('Tier 3');
    });
  });

  describe('references/github-templates.md', () => {
    it('should contain phase-start comment template', () => {
      expect(githubTemplates).toContain('### phase-start');
      expect(githubTemplates).toMatch(/Starting Phase.*Phase Name/);
    });

    it('should contain phase-completion comment template', () => {
      expect(githubTemplates).toContain('### phase-completion');
      expect(githubTemplates).toMatch(/Completed Phase.*Phase Name/);
    });

    it('should contain work-start comment template', () => {
      expect(githubTemplates).toContain('### work-start');
      expect(githubTemplates).toContain('Starting work on CHORE-XXX');
    });

    it('should contain work-complete comment template', () => {
      expect(githubTemplates).toContain('### work-complete');
      expect(githubTemplates).toContain('Completed CHORE-XXX');
    });

    it('should contain bug-start comment template', () => {
      expect(githubTemplates).toContain('### bug-start');
      expect(githubTemplates).toContain('Starting work on BUG-XXX');
    });

    it('should contain bug-complete comment template', () => {
      expect(githubTemplates).toContain('### bug-complete');
      expect(githubTemplates).toContain('Completed BUG-XXX');
    });

    it('should contain commit message templates', () => {
      expect(githubTemplates).toContain('## Commit Messages');
      expect(githubTemplates).toContain('Feature Commits');
      expect(githubTemplates).toContain('Chore Commits');
      expect(githubTemplates).toContain('Bug Fix Commits');
    });

    it('should contain PR body templates', () => {
      expect(githubTemplates).toContain('## Pull Request Templates');
      expect(githubTemplates).toContain('Closes #N');
    });

    it('should contain issue creation templates', () => {
      expect(githubTemplates).toContain('## Creating New Issues');
      expect(githubTemplates).toContain('Chore Issue');
      expect(githubTemplates).toContain('Bug Issue');
    });
  });

  describe('references/jira-templates.md', () => {
    it('should exist with content', () => {
      expect(jiraTemplates).toBeDefined();
      expect(jiraTemplates.length).toBeGreaterThan(0);
    });

    it('should reference ADF specification', () => {
      expect(jiraTemplates).toContain(
        'https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/'
      );
    });

    it('should contain all six comment type templates', () => {
      expect(jiraTemplates).toContain('### phase-start');
      expect(jiraTemplates).toContain('### phase-completion');
      expect(jiraTemplates).toContain('### work-start');
      expect(jiraTemplates).toContain('### work-complete');
      expect(jiraTemplates).toContain('### bug-start');
      expect(jiraTemplates).toContain('### bug-complete');
    });

    it('should not contain Phase 2 TODO placeholders (templates are now complete)', () => {
      expect(jiraTemplates).not.toContain('TODO: Phase 2');
    });

    it('should contain valid ADF JSON structure in templates', () => {
      expect(jiraTemplates).toContain('"version": 1');
      expect(jiraTemplates).toContain('"type": "doc"');
      expect(jiraTemplates).toContain('"content"');
    });

    it('should contain ADF heading nodes', () => {
      expect(jiraTemplates).toContain('"type": "heading"');
      expect(jiraTemplates).toContain('"level":');
    });

    it('should contain ADF marks for bold and italic', () => {
      expect(jiraTemplates).toContain('"type": "strong"');
      expect(jiraTemplates).toContain('"type": "em"');
    });

    it('should contain ADF bulletList and listItem nodes', () => {
      expect(jiraTemplates).toContain('"type": "bulletList"');
      expect(jiraTemplates).toContain('"type": "listItem"');
    });

    it('should contain ADF panel nodes for status callouts', () => {
      expect(jiraTemplates).toContain('"type": "panel"');
      expect(jiraTemplates).toContain('"panelType":');
    });

    it('should contain ADF code marks', () => {
      expect(jiraTemplates).toContain('"type": "code"');
    });

    it('should contain ADF orderedList nodes', () => {
      expect(jiraTemplates).toContain('"type": "orderedList"');
    });

    it('should have valid ADF structure for each comment type template', () => {
      // Extract all JSON blocks from the jira-templates.md
      const jsonBlocks = jiraTemplates.match(/```json\n([\s\S]*?)```/g) ?? [];
      expect(jsonBlocks.length).toBeGreaterThanOrEqual(6);

      for (const block of jsonBlocks) {
        const jsonStr = block.replace(/```json\n/, '').replace(/```$/, '');
        const parsed = JSON.parse(jsonStr);
        expect(parsed).toHaveProperty('version', 1);
        expect(parsed).toHaveProperty('type', 'doc');
        expect(parsed).toHaveProperty('content');
        expect(Array.isArray(parsed.content)).toBe(true);
        expect(parsed.content.length).toBeGreaterThan(0);
      }
    });

    it('should include work item ID traceability in phase templates', () => {
      expect(jiraTemplates).toContain('{workItemId}');
    });

    it('should include work item ID traceability in work templates', () => {
      expect(jiraTemplates).toContain('{choreId}');
    });

    it('should include work item ID traceability in bug templates', () => {
      expect(jiraTemplates).toContain('{bugId}');
    });

    it('should preserve RC-N tagging in bug templates', () => {
      expect(jiraTemplates).toContain('RC-1');
      expect(jiraTemplates).toContain('RC-2');
      expect(jiraTemplates).toContain('{rootCauses[');
      expect(jiraTemplates).toContain('{rootCauseResolutions[');
    });
  });

  describe('SKILL.md Jira backend content (Phase 2)', () => {
    it('should document Jira tiered fallback with all three tiers', () => {
      expect(skillMd).toContain('Tier 1 -- Rovo MCP');
      expect(skillMd).toContain('Tier 2 -- Atlassian CLI');
      expect(skillMd).toContain('Tier 3 -- Skip');
    });

    it('should document Rovo MCP tool names', () => {
      expect(skillMd).toContain('getJiraIssue');
      expect(skillMd).toContain('addCommentToJiraIssue');
    });

    it('should document acli CLI commands', () => {
      expect(skillMd).toContain('acli jira workitem view');
      expect(skillMd).toContain('acli jira workitem comment-create');
    });

    it('should document Jira fetch operation', () => {
      expect(skillMd).toContain('Jira Fetch Operation');
      expect(skillMd).toContain('getJiraIssue(cloudId, issueIdOrKey)');
      expect(skillMd).toContain('acli jira workitem view --key PROJ-123');
    });

    it('should document Jira comment operation', () => {
      expect(skillMd).toContain('Jira Comment Operation');
      expect(skillMd).toContain('addCommentToJiraIssue(cloudId, issueIdOrKey, commentBody)');
      expect(skillMd).toContain('acli jira workitem comment-create --key PROJ-123');
    });

    it('should document Jira PR body link generation', () => {
      expect(skillMd).toContain('Jira PR Body Link Generation');
      expect(skillMd).toContain('PROJ-123');
    });

    it('should document Jira-specific error handling', () => {
      expect(skillMd).toContain('Jira-Specific Error Handling');
      expect(skillMd).toContain('Rovo MCP authorization failed');
      expect(skillMd).toContain('acli CLI not found on PATH');
    });

    it('should document MCP failure fallthrough to acli', () => {
      expect(skillMd).toContain('Fall through to Tier 2');
    });

    it('should handle alphanumeric project keys (e.g., PROJ2-123)', () => {
      expect(skillMd).toContain('Alphanumeric Project Keys');
      expect(skillMd).toContain('PROJ2-');
      expect(skillMd).toContain('[A-Z][A-Z0-9]*');
    });

    it('should no longer contain the Phase 1 Jira deferral note', () => {
      expect(skillMd).not.toContain('Jira backend not yet implemented, skipping');
    });

    it('should document ADF format requirement for Rovo MCP comments', () => {
      expect(skillMd).toContain('ADF JSON format');
      expect(skillMd).toContain('commentBody');
    });

    it('should document that acli accepts markdown', () => {
      expect(skillMd).toContain('acli');
      expect(skillMd).toContain('markdown');
      expect(skillMd).toContain('ADF conversion internally');
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
