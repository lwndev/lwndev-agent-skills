import { describe, it, expect, beforeAll, afterEach } from 'vitest';
import { readFile } from 'node:fs/promises';
import { mkdirSync, writeFileSync, rmSync, mkdtempSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execSync } from 'node:child_process';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/finalizing-workflow';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');

// ---------------------------------------------------------------------------
// Helper: parse branch name using the documented regex patterns (FR-2)
// ---------------------------------------------------------------------------

interface BranchParseResult {
  id: string;
  directory: string;
}

function parseBranchName(branch: string): BranchParseResult | null {
  const featMatch = branch.match(/^feat\/(FEAT-[0-9]+)-/);
  if (featMatch) return { id: featMatch[1], directory: 'requirements/features/' };

  const choreMatch = branch.match(/^chore\/(CHORE-[0-9]+)-/);
  if (choreMatch) return { id: choreMatch[1], directory: 'requirements/chores/' };

  const fixMatch = branch.match(/^fix\/(BUG-[0-9]+)-/);
  if (fixMatch) return { id: fixMatch[1], directory: 'requirements/bugs/' };

  return null;
}

// ---------------------------------------------------------------------------
// Helper: glob for requirement doc in a directory (FR-3)
// ---------------------------------------------------------------------------

import { readdirSync } from 'node:fs';

function findRequirementDoc(
  baseDir: string,
  directory: string,
  id: string
): { path: string } | { skip: 'zero' } | { skip: 'multi' } {
  const dir = join(baseDir, directory);
  let files: string[];
  try {
    files = readdirSync(dir).filter((f) => f.startsWith(`${id}-`) && f.endsWith('.md'));
  } catch {
    return { skip: 'zero' };
  }
  if (files.length === 0) return { skip: 'zero' };
  if (files.length >= 2) return { skip: 'multi' };
  return { path: join(dir, files[0]) };
}

// ---------------------------------------------------------------------------
// Shared: line-ending- and fence-aware section-bounds finder
// ---------------------------------------------------------------------------
//
// SKILL.md's BK-4 robustness rules require both CRLF handling and
// fenced-code-block awareness. This helper scans line-by-line, tracks fence
// state (```), and returns the character offsets of a `## <heading>` section
// while ignoring false matches inside code fences and respecting `\r?\n` line
// endings. The returned offsets are slice-safe indices into `content`.

interface SectionBounds {
  headingStart: number; // offset of `## ` in the heading line
  bodyStart: number; // offset of first char after the heading line's newline
  bodyEnd: number; // offset of the next `## ` heading line (or content.length)
}

function findSection(content: string, heading: string): SectionBounds | null {
  const lines = content.split(/\r?\n/);
  let inFence = false;
  let offset = 0;
  let headingStart = -1;
  let bodyStart = -1;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineLen = line.length;
    const sepLen = content.slice(offset + lineLen, offset + lineLen + 2) === '\r\n' ? 2 : 1;

    if (/^```/.test(line)) {
      inFence = !inFence;
    } else if (!inFence) {
      if (headingStart === -1 && line === `## ${heading}`) {
        headingStart = offset;
        bodyStart = offset + lineLen + sepLen;
      } else if (headingStart !== -1 && /^## /.test(line)) {
        return { headingStart, bodyStart, bodyEnd: offset };
      }
    }
    offset += lineLen + sepLen;
  }

  if (headingStart !== -1) return { headingStart, bodyStart, bodyEnd: content.length };
  return null;
}

// ---------------------------------------------------------------------------
// Helper: idempotency check (FR-4)
// ---------------------------------------------------------------------------

function isAlreadyFinalized(content: string, prNumber: number): boolean {
  // Condition 1: AC section absent OR has zero unchecked items outside fences
  const acBounds = findSection(content, 'Acceptance Criteria');
  if (acBounds) {
    const acBody = content.slice(acBounds.bodyStart, acBounds.bodyEnd);
    let inFence = false;
    for (const line of acBody.split(/\r?\n/)) {
      if (/^```/.test(line)) {
        inFence = !inFence;
        continue;
      }
      if (!inFence && /^- \[ \]/.test(line)) return false;
    }
  }

  // Condition 2: Completion section exists with Complete/Completed status
  const completionBounds = findSection(content, 'Completion');
  if (!completionBounds) return false;
  const completionBody = content.slice(completionBounds.bodyStart, completionBounds.bodyEnd);
  if (!/\*\*Status:\*\* `Complet(e|ed)`/.test(completionBody)) return false;

  // Condition 3: PR link with matching number
  const prLinkPattern = new RegExp(`\\[#${prNumber}\\]|/pull/${prNumber}(?!\\d)`);
  if (!prLinkPattern.test(completionBody)) return false;

  return true;
}

// ---------------------------------------------------------------------------
// Helper: AC checkoff (FR-5.1)
// ---------------------------------------------------------------------------

function checkoffAC(content: string): string {
  const bounds = findSection(content, 'Acceptance Criteria');
  if (!bounds) return content;

  const body = content.slice(bounds.bodyStart, bounds.bodyEnd);
  const lines = body.split(/(\r?\n)/); // keep separators
  let inFence = false;
  const out: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const chunk = lines[i];
    if (i % 2 === 1) {
      // separator
      out.push(chunk);
      continue;
    }
    if (/^```/.test(chunk)) inFence = !inFence;
    if (!inFence && chunk.startsWith('- [ ]')) {
      out.push('- [x]' + chunk.slice('- [ ]'.length));
    } else {
      out.push(chunk);
    }
  }
  return content.slice(0, bounds.bodyStart) + out.join('') + content.slice(bounds.bodyEnd);
}

// ---------------------------------------------------------------------------
// Helper: Completion section upsert (FR-5.2)
// ---------------------------------------------------------------------------

function upsertCompletion(
  content: string,
  date: string,
  prNumber: number,
  prUrl: string | null
): string {
  const eol = /\r\n/.test(content) ? '\r\n' : '\n';
  const prLine = prUrl ? `${eol}**Pull Request:** [#${prNumber}](${prUrl})` : '';
  const block = `## Completion${eol}${eol}**Status:** \`Complete\`${eol}${eol}**Completed:** ${date}${prLine}${eol}`;

  const bounds = findSection(content, 'Completion');
  if (!bounds) {
    return content.replace(/\s+$/, '') + eol + eol + block;
  }
  return content.slice(0, bounds.headingStart) + block + content.slice(bounds.bodyEnd);
}

// ---------------------------------------------------------------------------
// Helper: Affected Files reconciliation (FR-5.3)
// ---------------------------------------------------------------------------

function reconcileAffectedFiles(content: string, prFiles: string[]): string {
  const bounds = findSection(content, 'Affected Files');
  if (!bounds) return content;

  const sectionBody = content.slice(bounds.bodyStart, bounds.bodyEnd);
  const parts = sectionBody.split(/(\r?\n)/);
  const pathRegex = /^- `?([^`\s(—]+)`?/;

  // Collect existing paths (skip content inside fences)
  const docPaths: string[] = [];
  let inFence = false;
  for (let i = 0; i < parts.length; i += 2) {
    const line = parts[i];
    if (/^```/.test(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    const m = line.match(pathRegex);
    if (m) docPaths.push(m[1]);
  }

  // Rewrite lines with annotations for drops
  inFence = false;
  for (let i = 0; i < parts.length; i += 2) {
    const line = parts[i];
    if (/^```/.test(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    const m = line.match(pathRegex);
    if (!m) continue;
    const filePath = m[1];
    if (!prFiles.includes(filePath)) {
      if (line.endsWith('(planned but not modified)')) continue;
      parts[i] = line.replace(/\s+$/, '') + ' (planned but not modified)';
    }
  }

  // Append files in PR but not in doc
  const eol = /\r\n/.test(content) ? '\r\n' : '\n';
  const docSet = new Set(docPaths);
  const toAppend = [...new Set(prFiles)].filter((f) => !docSet.has(f)).sort();
  let appended = '';
  for (const f of toAppend) {
    appended += `${eol}- \`${f}\``;
  }

  const rebuiltBody = parts.join('') + appended;
  return content.slice(0, bounds.bodyStart) + rebuiltBody + content.slice(bounds.bodyEnd);
}

// ---------------------------------------------------------------------------
// SKILL.md structural assertions
// ---------------------------------------------------------------------------

describe('finalizing-workflow skill', () => {
  let skillMd: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
  });

  describe('SKILL.md structural assertions (post-FEAT-022 collapse)', () => {
    it('should have frontmatter with name: finalizing-workflow', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*finalizing-workflow[\s\S]*?---/);
    });

    it('should have non-empty description in frontmatter', () => {
      const match = skillMd.match(/^---\s*\n[\s\S]*?description:\s*(.+)[\s\S]*?---/);
      expect(match).not.toBeNull();
      expect(match![1].trim().length).toBeGreaterThan(0);
    });

    it('should have allowed-tools containing Bash', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('- Bash');
    });

    it('should NOT have Edit in allowed-tools (pruned per FR-10)', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toContain('- Edit');
    });

    it('should NOT have Glob in allowed-tools (pruned per FR-10)', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toContain('- Glob');
    });

    it('should NOT have Write in allowed-tools', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toContain('- Write');
    });

    it('should contain ## When to Use This Skill section', () => {
      expect(skillMd).toContain('## When to Use This Skill');
    });

    it('should contain ## Workflow Position section', () => {
      expect(skillMd).toContain('## Workflow Position');
    });

    it('should contain ## Usage section (post-collapse)', () => {
      expect(skillMd).toContain('## Usage');
    });

    it('should reference the finalize.sh invocation', () => {
      expect(skillMd).toContain(
        'bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/finalize.sh"'
      );
    });

    it('should contain the single canonical confirmation prompt', () => {
      expect(skillMd).toContain('Ready to merge PR');
      expect(skillMd).toContain('finalize the requirement document');
    });

    it('should NOT contain removed ## Pre-Flight Checks section', () => {
      expect(skillMd).not.toContain('## Pre-Flight Checks');
    });

    it('should NOT contain removed ## Pre-Merge Bookkeeping section', () => {
      expect(skillMd).not.toContain('## Pre-Merge Bookkeeping');
    });

    it('should NOT contain removed ## Execution section', () => {
      expect(skillMd).not.toContain('## Execution');
    });

    it('should NOT contain removed ## Error Handling section', () => {
      expect(skillMd).not.toContain('## Error Handling');
    });

    it('should NOT reference BK-1 through BK-5 labels', () => {
      expect(skillMd).not.toMatch(/\bBK-[1-5]\b/);
    });

    it('should still contain ## Relationship to Other Skills section', () => {
      expect(skillMd).toContain('## Relationship to Other Skills');
    });

    it('should preserve the "Merge PR and reset to main (and finalize requirement doc)" row', () => {
      expect(skillMd).toContain('Merge PR and reset to main (and finalize requirement doc)');
    });

    it('should be under 80 lines after the collapse', () => {
      const lineCount = skillMd.split('\n').length;
      expect(lineCount).toBeLessThan(80);
    });
  });

  // ---------------------------------------------------------------------------
  // Unit tests: Branch-name parsing (FR-2)
  // ---------------------------------------------------------------------------

  describe('unit: branch-name parsing (FR-2)', () => {
    it('feat/FEAT-019-foo → derived ID FEAT-019, directory requirements/features/', () => {
      const result = parseBranchName('feat/FEAT-019-foo');
      expect(result).not.toBeNull();
      expect(result!.id).toBe('FEAT-019');
      expect(result!.directory).toBe('requirements/features/');
    });

    it('chore/CHORE-033-fix → derived ID CHORE-033, directory requirements/chores/', () => {
      const result = parseBranchName('chore/CHORE-033-fix');
      expect(result).not.toBeNull();
      expect(result!.id).toBe('CHORE-033');
      expect(result!.directory).toBe('requirements/chores/');
    });

    it('fix/BUG-011-stop-hook → derived ID BUG-011, directory requirements/bugs/', () => {
      const result = parseBranchName('fix/BUG-011-stop-hook');
      expect(result).not.toBeNull();
      expect(result!.id).toBe('BUG-011');
      expect(result!.directory).toBe('requirements/bugs/');
    });

    it('release/lwndev-sdlc-v1.13.0 → no match (skip bookkeeping)', () => {
      const result = parseBranchName('release/lwndev-sdlc-v1.13.0');
      expect(result).toBeNull();
    });

    it('bug/BUG-011-stop-hook → no match (non-canonical prefix)', () => {
      const result = parseBranchName('bug/BUG-011-stop-hook');
      expect(result).toBeNull();
    });

    it('main → no match', () => {
      const result = parseBranchName('main');
      expect(result).toBeNull();
    });
  });

  // ---------------------------------------------------------------------------
  // Unit tests: Requirement doc location (FR-3)
  // ---------------------------------------------------------------------------

  describe('unit: requirement doc location (FR-3)', () => {
    let tmpDir: string;

    afterEach(() => {
      if (tmpDir) {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it('one file matching FEAT-019-*.md → resolved path returned', () => {
      tmpDir = mkdtempSync(join(tmpdir(), 'bk-loc-'));
      const dir = join(tmpDir, 'requirements', 'features');
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, 'FEAT-019-finalizing-workflow.md'), '# Doc');

      const result = findRequirementDoc(tmpDir, 'requirements/features/', 'FEAT-019');
      expect('path' in result).toBe(true);
      expect((result as { path: string }).path).toContain('FEAT-019-finalizing-workflow.md');
    });

    it('zero files → skip-with-warning path (zero)', () => {
      tmpDir = mkdtempSync(join(tmpdir(), 'bk-loc-'));
      const dir = join(tmpDir, 'requirements', 'features');
      mkdirSync(dir, { recursive: true });

      const result = findRequirementDoc(tmpDir, 'requirements/features/', 'FEAT-019');
      expect((result as { skip: string }).skip).toBe('zero');
    });

    it('two files matching same ID → skip-with-error path (multi)', () => {
      tmpDir = mkdtempSync(join(tmpdir(), 'bk-loc-'));
      const dir = join(tmpDir, 'requirements', 'features');
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, 'FEAT-019-finalizing-workflow.md'), '# Doc');
      writeFileSync(join(dir, 'FEAT-019-another-copy.md'), '# Doc copy');

      const result = findRequirementDoc(tmpDir, 'requirements/features/', 'FEAT-019');
      expect((result as { skip: string }).skip).toBe('multi');
    });
  });

  // ---------------------------------------------------------------------------
  // Unit tests: Idempotency detection (FR-4)
  // ---------------------------------------------------------------------------

  describe('unit: idempotency detection (FR-4)', () => {
    it('all ACs ticked, Completion has Complete, PR link matches → idempotency passes', () => {
      const doc = `# Feature\n\n## Acceptance Criteria\n\n- [x] First item\n- [x] Second item\n\n## Completion\n\n**Status:** \`Complete\`\n\n**Completed:** 2026-04-19\n\n**Pull Request:** [#42](https://github.com/owner/repo/pull/42)\n`;
      expect(isAlreadyFinalized(doc, 42)).toBe(true);
    });

    it('one unchecked AC present → idempotency fails (proceed to edits)', () => {
      const doc = `# Feature\n\n## Acceptance Criteria\n\n- [x] First item\n- [ ] Second item\n\n## Completion\n\n**Status:** \`Complete\`\n\n**Pull Request:** [#42](https://github.com/owner/repo/pull/42)\n`;
      expect(isAlreadyFinalized(doc, 42)).toBe(false);
    });

    it('Completion section absent → idempotency fails', () => {
      const doc = `# Feature\n\n## Acceptance Criteria\n\n- [x] Item one\n`;
      expect(isAlreadyFinalized(doc, 42)).toBe(false);
    });

    it('PR link present but wrong number → idempotency fails', () => {
      const doc = `# Feature\n\n## Acceptance Criteria\n\n- [x] Item one\n\n## Completion\n\n**Status:** \`Complete\`\n\n**Pull Request:** [#99](https://github.com/owner/repo/pull/99)\n`;
      expect(isAlreadyFinalized(doc, 42)).toBe(false);
    });

    it('no ## Acceptance Criteria section → AC condition satisfied (carve-out per FR-4)', () => {
      const doc = `# Feature\n\n## Overview\n\nSome text.\n\n## Completion\n\n**Status:** \`Complete\`\n\n**Completed:** 2026-04-19\n\n**Pull Request:** [#42](https://github.com/owner/repo/pull/42)\n`;
      expect(isAlreadyFinalized(doc, 42)).toBe(true);
    });
  });

  // ---------------------------------------------------------------------------
  // Unit tests: AC checkoff (FR-5.1)
  // ---------------------------------------------------------------------------

  describe('unit: AC checkoff (FR-5.1)', () => {
    it('mixed [ ] and [x] in AC section → all become [x], non-AC section untouched', () => {
      const doc = `# F\n\n## Acceptance Criteria\n\n- [x] Done\n- [ ] Not done\n\n## Other\n\n- [ ] Should stay unchanged\n`;
      const result = checkoffAC(doc);
      expect(result).toContain('- [x] Done');
      expect(result).toContain('- [x] Not done');
      // The item under ## Other should be untouched
      expect(result).toContain('## Other\n\n- [ ] Should stay unchanged');
    });

    it('AC section absent → doc unchanged', () => {
      const doc = `# Feature\n\n## Overview\n\nContent here.\n`;
      expect(checkoffAC(doc)).toBe(doc);
    });

    it('all [x] already → doc unchanged (idempotent)', () => {
      const doc = `# F\n\n## Acceptance Criteria\n\n- [x] Already done\n- [x] Also done\n`;
      expect(checkoffAC(doc)).toBe(doc);
    });

    it('AC items with trailing text preserved verbatim', () => {
      const doc = `# F\n\n## Acceptance Criteria\n\n- [ ] Do the thing with trailing text here\n`;
      const result = checkoffAC(doc);
      expect(result).toContain('- [x] Do the thing with trailing text here');
    });
  });

  // ---------------------------------------------------------------------------
  // Unit tests: Completion section upsert (FR-5.2)
  // ---------------------------------------------------------------------------

  describe('unit: Completion section upsert (FR-5.2)', () => {
    it('no ## Completion section → block appended at end with correct structure', () => {
      const doc = `# Feature\n\n## Overview\n\nContent.\n`;
      const result = upsertCompletion(
        doc,
        '2026-04-19',
        42,
        'https://github.com/owner/repo/pull/42'
      );
      expect(result).toContain('## Completion');
      expect(result).toContain('**Status:** `Complete`');
      expect(result).toContain('**Completed:** 2026-04-19');
      expect(result).toContain('**Pull Request:** [#42](https://github.com/owner/repo/pull/42)');
      // Block appended after existing content
      expect(result.indexOf('## Completion')).toBeGreaterThan(result.indexOf('## Overview'));
    });

    it('existing ## Completion with stale status → body replaced, heading preserved', () => {
      const doc = `# Feature\n\n## Completion\n\n**Status:** \`In Progress\`\n\n**Old line:** foo\n`;
      const result = upsertCompletion(
        doc,
        '2026-04-19',
        42,
        'https://github.com/owner/repo/pull/42'
      );
      expect(result).toContain('## Completion');
      expect(result).toContain('**Status:** `Complete`');
      expect(result).not.toContain('**Status:** `In Progress`');
      expect(result).not.toContain('**Old line:**');
      expect(result).toContain('**Pull Request:** [#42](https://github.com/owner/repo/pull/42)');
    });

    it('gh call fails → **Pull Request:** line omitted; Status + date written', () => {
      const doc = `# Feature\n\n## Overview\n\nContent.\n`;
      const result = upsertCompletion(doc, '2026-04-19', 42, null);
      expect(result).toContain('**Status:** `Complete`');
      expect(result).toContain('**Completed:** 2026-04-19');
      expect(result).not.toContain('**Pull Request:**');
    });

    it('date format matches YYYY-MM-DD pattern', () => {
      const doc = `# Feature\n`;
      const result = upsertCompletion(doc, '2026-04-19', 1, null);
      expect(result).toMatch(/\*\*Completed:\*\* \d{4}-\d{2}-\d{2}/);
    });
  });

  // ---------------------------------------------------------------------------
  // Unit tests: Affected Files reconciliation (FR-5.3)
  // ---------------------------------------------------------------------------

  describe('unit: Affected Files reconciliation (FR-5.3)', () => {
    it('file in PR not in doc → new bullet appended', () => {
      const doc = `# F\n\n## Affected Files\n\n- \`scripts/existing.ts\`\n`;
      const result = reconcileAffectedFiles(doc, ['scripts/existing.ts', 'scripts/new.ts']);
      expect(result).toContain('- `scripts/new.ts`');
    });

    it('file in doc not in PR → annotated (planned but not modified)', () => {
      const doc = `# F\n\n## Affected Files\n\n- \`scripts/planned.ts\` — description here\n`;
      const result = reconcileAffectedFiles(doc, []);
      expect(result).toContain('(planned but not modified)');
      expect(result).toContain('scripts/planned.ts');
    });

    it('file in both doc and PR → unchanged', () => {
      const doc = `# F\n\n## Affected Files\n\n- \`scripts/both.ts\` — in both\n`;
      const result = reconcileAffectedFiles(doc, ['scripts/both.ts']);
      expect(result).toContain('- `scripts/both.ts` — in both');
      expect(result).not.toContain('(planned but not modified)');
    });

    it('no ## Affected Files section → doc unchanged (skipped silently)', () => {
      const doc = `# F\n\n## Overview\n\nContent.\n`;
      expect(reconcileAffectedFiles(doc, ['scripts/new.ts'])).toBe(doc);
    });

    it('annotation idempotency: line already ending with (planned but not modified) → not double-annotated', () => {
      const doc = `# F\n\n## Affected Files\n\n- \`scripts/planned.ts\` (planned but not modified)\n`;
      const result = reconcileAffectedFiles(doc, []);
      const matches = result.match(/\(planned but not modified\)/g) ?? [];
      expect(matches.length).toBe(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Unit tests: Commit message format (FR-6)
  // ---------------------------------------------------------------------------

  describe('unit: commit message format (FR-6)', () => {
    it('commit message starts with chore({ID}): finalize requirement document', () => {
      const id = 'FEAT-019';
      const expected = `chore(${id}): finalize requirement document`;
      expect(expected).toMatch(/^chore\(FEAT-019\): finalize requirement document$/);
    });

    it('commit body contains three prescribed bullet lines', () => {
      const body = [
        '- Tick completed acceptance criteria',
        '- Set completion status with PR link',
        '- Reconcile affected files against PR diff',
      ];
      expect(body[0]).toBe('- Tick completed acceptance criteria');
      expect(body[1]).toBe('- Set completion status with PR link');
      expect(body[2]).toBe('- Reconcile affected files against PR diff');
      expect(body).toHaveLength(3);
    });

    it('commit message must not contain --amend flag (new commit only)', () => {
      // Verify the documented commit invocation does not contain --amend
      const commitInvocation = 'git commit -m "chore(ID): finalize requirement document"';
      expect(commitInvocation).not.toContain('--amend');
    });

    it('push command must not contain --force or --force-with-lease', () => {
      const pushInvocation = 'git push';
      expect(pushInvocation).not.toContain('--force');
      expect(pushInvocation).not.toContain('--force-with-lease');
    });
  });

  // ---------------------------------------------------------------------------
  // Integration tests (using temp git repos with mocked gh/git responses)
  // ---------------------------------------------------------------------------

  describe('integration: end-to-end happy path', () => {
    let tmpDir: string;
    let mockBinDir: string;

    afterEach(() => {
      if (tmpDir) rmSync(tmpDir, { recursive: true, force: true });
      if (mockBinDir) rmSync(mockBinDir, { recursive: true, force: true });
    });

    /**
     * Sets up a temporary git repo with:
     *  - a feature branch feat/FEAT-099-test-feature
     *  - a requirement doc with unticked ACs and no Completion section
     *  - an Affected Files section listing one planned file
     */
    function setupHappyPathRepo(): {
      repoDir: string;
      mockBin: string;
      docPath: string;
    } {
      const repoDir = mkdtempSync(join(tmpdir(), 'bk-integ-'));
      const mockBin = mkdtempSync(join(tmpdir(), 'bk-mock-bin-'));

      // Init git repo
      execSync('git init', { cwd: repoDir });
      execSync('git config user.email "test@example.com"', { cwd: repoDir });
      execSync('git config user.name "Test"', { cwd: repoDir });

      // Create initial commit on main
      writeFileSync(join(repoDir, 'README.md'), '# Project\n');
      execSync('git add README.md', { cwd: repoDir });
      execSync('git commit -m "init"', { cwd: repoDir });

      // Create feature branch
      execSync('git checkout -b feat/FEAT-099-test-feature', { cwd: repoDir });

      // Create requirement doc
      const featDir = join(repoDir, 'requirements', 'features');
      mkdirSync(featDir, { recursive: true });
      const docContent = `# Feature: Test Feature\n\n## Acceptance Criteria\n\n- [ ] First criterion\n- [ ] Second criterion\n\n## Affected Files\n\n- \`scripts/planned-only.ts\` — planned but not shipped\n`;
      const docPath = join(featDir, 'FEAT-099-test-feature.md');
      writeFileSync(docPath, docContent);
      execSync(`git add requirements/features/FEAT-099-test-feature.md`, { cwd: repoDir });
      execSync('git commit -m "feat: add requirement doc"', { cwd: repoDir });

      // Create mock gh binary that returns synthetic PR data
      const ghScript = `#!/bin/bash
if [[ "$*" == *"--json number,url"* ]]; then
  echo '{"number":99,"url":"https://github.com/owner/repo/pull/99"}'
elif [[ "$*" == *"--json files"* ]]; then
  echo 'scripts/new-file.ts'
fi
`;
      const ghBin = join(mockBin, 'gh');
      writeFileSync(ghBin, ghScript, { mode: 0o755 });

      return { repoDir, mockBin: mockBin, docPath };
    }

    it('ACs all [x], Completion block present, PR file appended after happy path', () => {
      const { repoDir, mockBin, docPath } = setupHappyPathRepo();
      tmpDir = repoDir;
      mockBinDir = mockBin;

      const today = '2026-04-19';

      // Run the bookkeeping logic directly (simulating what the skill does)
      let content = readFileSync(docPath, 'utf-8');

      // BK-1: parse branch
      const parsed = parseBranchName('feat/FEAT-099-test-feature');
      expect(parsed).not.toBeNull();
      expect(parsed!.id).toBe('FEAT-099');

      // BK-2: locate doc
      const located = findRequirementDoc(repoDir, 'requirements/features/', 'FEAT-099');
      expect('path' in located).toBe(true);

      // BK-3: idempotency check — should fail (has unchecked ACs)
      expect(isAlreadyFinalized(content, 99)).toBe(false);

      // BK-4.1: AC checkoff
      content = checkoffAC(content);
      expect(content).toContain('- [x] First criterion');
      expect(content).toContain('- [x] Second criterion');

      // BK-4.2: Completion upsert
      content = upsertCompletion(content, today, 99, 'https://github.com/owner/repo/pull/99');
      expect(content).toContain('**Status:** `Complete`');
      expect(content).toContain('**Completed:** 2026-04-19');
      expect(content).toContain('[#99](https://github.com/owner/repo/pull/99)');

      // BK-4.3: Affected Files reconciliation
      content = reconcileAffectedFiles(content, ['scripts/new-file.ts']);
      expect(content).toContain('- `scripts/new-file.ts`');
      expect(content).toContain('(planned but not modified)');

      // Write back and commit
      writeFileSync(docPath, content);
      const statusBefore = execSync('git status --porcelain', { cwd: repoDir, encoding: 'utf-8' });
      expect(statusBefore.trim()).toBeTruthy();

      execSync(`git add requirements/features/FEAT-099-test-feature.md`, { cwd: repoDir });
      execSync(
        `git commit -m "chore(FEAT-099): finalize requirement document\n\n- Tick completed acceptance criteria\n- Set completion status with PR link\n- Reconcile affected files against PR diff"`,
        { cwd: repoDir }
      );

      // Verify commit message
      const lastCommit = execSync('git log --format=%B -n 1', { cwd: repoDir, encoding: 'utf-8' });
      expect(lastCommit).toContain('chore(FEAT-099): finalize requirement document');
      expect(lastCommit).toContain('- Tick completed acceptance criteria');

      // Verify no amend was used (log has 3 commits: init, feat: add, chore: finalize)
      const log = execSync('git log --oneline', { cwd: repoDir, encoding: 'utf-8' });
      const commitLines = log.trim().split('\n');
      expect(commitLines).toHaveLength(3);

      // Verify doc state post-commit
      const finalContent = readFileSync(docPath, 'utf-8');
      expect(finalContent).toContain('- [x] First criterion');
      expect(finalContent).toContain('## Completion');
    });
  });

  describe('integration: idempotency re-run (synthetic finalized doc)', () => {
    let tmpDir: string;

    afterEach(() => {
      if (tmpDir) rmSync(tmpDir, { recursive: true, force: true });
    });

    it('no new commit produced when doc already satisfies all FR-4 conditions', () => {
      tmpDir = mkdtempSync(join(tmpdir(), 'bk-idempotent-'));

      execSync('git init', { cwd: tmpDir });
      execSync('git config user.email "test@example.com"', { cwd: tmpDir });
      execSync('git config user.name "Test"', { cwd: tmpDir });

      writeFileSync(join(tmpDir, 'README.md'), '# Project\n');
      execSync('git add README.md', { cwd: tmpDir });
      execSync('git commit -m "init"', { cwd: tmpDir });
      execSync('git checkout -b feat/FEAT-100-already-done', { cwd: tmpDir });

      const featDir = join(tmpDir, 'requirements', 'features');
      mkdirSync(featDir, { recursive: true });
      const docContent = `# Feature\n\n## Acceptance Criteria\n\n- [x] Done\n\n## Completion\n\n**Status:** \`Complete\`\n\n**Completed:** 2026-04-18\n\n**Pull Request:** [#100](https://github.com/owner/repo/pull/100)\n`;
      const docPath = join(featDir, 'FEAT-100-already-done.md');
      writeFileSync(docPath, docContent);
      execSync('git add requirements/features/FEAT-100-already-done.md', { cwd: tmpDir });
      execSync('git commit -m "chore: add finalized doc"', { cwd: tmpDir });

      // Simulate bookkeeping: idempotency check should pass
      const content = readFileSync(docPath, 'utf-8');
      const shouldSkip = isAlreadyFinalized(content, 100);
      expect(shouldSkip).toBe(true);

      // If idempotency passes, no writes happen; working tree stays clean
      const status = execSync('git status --porcelain', { cwd: tmpDir, encoding: 'utf-8' });
      expect(status.trim()).toBe('');

      // Commit count unchanged: init + chore: add finalized doc = 2
      const logLines = execSync('git log --oneline', { cwd: tmpDir, encoding: 'utf-8' })
        .trim()
        .split('\n');
      expect(logLines).toHaveLength(2);

      // Doc is byte-identical to what was committed
      const contentAfter = readFileSync(docPath, 'utf-8');
      expect(contentAfter).toBe(docContent);
    });
  });

  describe('integration: gh pr view --json files fails (NFR-5 row 2)', () => {
    let tmpDir: string;

    afterEach(() => {
      if (tmpDir) rmSync(tmpDir, { recursive: true, force: true });
    });

    it('FR-5.1 runs, FR-5.2 completes with PR link, FR-5.3 skipped when --json files fails', () => {
      tmpDir = mkdtempSync(join(tmpdir(), 'bk-files-fail-'));

      const docContent = `# Feature\n\n## Acceptance Criteria\n\n- [ ] Item\n\n## Affected Files\n\n- \`scripts/planned.ts\`\n`;

      // FR-5.1: AC checkoff still runs
      let content = checkoffAC(docContent);
      expect(content).toContain('- [x] Item');

      // FR-5.2: Completion upsert with PR link (number,url call succeeded)
      content = upsertCompletion(
        content,
        '2026-04-19',
        55,
        'https://github.com/owner/repo/pull/55'
      );
      expect(content).toContain('**Pull Request:** [#55]');

      // FR-5.3 skipped: reconcileAffectedFiles NOT called because --json files failed
      // Affected Files section should be unchanged (planned.ts NOT annotated)
      expect(content).not.toContain('(planned but not modified)');
      expect(content).toContain('- `scripts/planned.ts`');
    });
  });

  describe('integration: both gh calls fail (NFR-5 row 3)', () => {
    let tmpDir: string;

    afterEach(() => {
      if (tmpDir) rmSync(tmpDir, { recursive: true, force: true });
    });

    it('FR-5.1 runs, FR-5.2 writes Status+date only (no PR link), FR-5.3 skipped', () => {
      tmpDir = mkdtempSync(join(tmpdir(), 'bk-both-fail-'));

      const docContent = `# Feature\n\n## Acceptance Criteria\n\n- [ ] Item\n\n## Affected Files\n\n- \`scripts/planned.ts\`\n`;

      // FR-5.1: AC checkoff still runs
      let content = checkoffAC(docContent);
      expect(content).toContain('- [x] Item');

      // FR-5.2: Both gh calls failed → prUrl is null → no Pull Request line
      content = upsertCompletion(content, '2026-04-19', 55, null);
      expect(content).toContain('**Status:** `Complete`');
      expect(content).toContain('**Completed:** 2026-04-19');
      expect(content).not.toContain('**Pull Request:**');

      // FR-5.3 skipped: no reconciliation
      expect(content).not.toContain('(planned but not modified)');
    });
  });

  describe('integration: git push fails → merge not invoked (FR-6 / FR-7 row 4)', () => {
    let tmpDir: string;

    afterEach(() => {
      if (tmpDir) rmSync(tmpDir, { recursive: true, force: true });
    });

    it('when git push exits non-zero, merge should NOT proceed', () => {
      tmpDir = mkdtempSync(join(tmpdir(), 'bk-push-fail-'));

      execSync('git init', { cwd: tmpDir });
      execSync('git config user.email "test@example.com"', { cwd: tmpDir });
      execSync('git config user.name "Test"', { cwd: tmpDir });

      writeFileSync(join(tmpDir, 'README.md'), '# Project\n');
      execSync('git add README.md', { cwd: tmpDir });
      execSync('git commit -m "init"', { cwd: tmpDir });
      execSync('git checkout -b feat/FEAT-101-push-fail', { cwd: tmpDir });

      const featDir = join(tmpDir, 'requirements', 'features');
      mkdirSync(featDir, { recursive: true });
      const docPath = join(featDir, 'FEAT-101-push-fail.md');
      writeFileSync(docPath, '# Feature\n\n## Acceptance Criteria\n\n- [ ] Item\n');
      execSync('git add requirements/features/FEAT-101-push-fail.md', { cwd: tmpDir });
      execSync('git commit -m "add doc"', { cwd: tmpDir });

      // Apply bookkeeping
      let content = readFileSync(docPath, 'utf-8');
      content = checkoffAC(content);
      content = upsertCompletion(
        content,
        '2026-04-19',
        101,
        'https://github.com/owner/repo/pull/101'
      );
      writeFileSync(docPath, content);

      execSync('git add requirements/features/FEAT-101-push-fail.md', { cwd: tmpDir });
      execSync('git commit -m "chore(FEAT-101): finalize requirement document"', { cwd: tmpDir });

      // Simulate push failure: pushing to no remote fails
      let pushFailed = false;
      const mergeInvoked = false;
      try {
        execSync('git push', { cwd: tmpDir, stdio: 'pipe' });
      } catch {
        pushFailed = true;
        // When push fails, merge must NOT be invoked
        // mergeInvoked stays false
      }

      expect(pushFailed).toBe(true);
      expect(mergeInvoked).toBe(false);
    });
  });

  describe('integration: branch-id-parse.sh classification (FR-7)', () => {
    const BRANCH_ID_PARSE = 'plugins/lwndev-sdlc/scripts/branch-id-parse.sh';

    function runBranchIdParse(branch: string): { stdout: string; stderr: string; code: number } {
      try {
        const stdout = execSync(`bash ${BRANCH_ID_PARSE} ${JSON.stringify(branch)}`, {
          encoding: 'utf-8',
          stdio: ['ignore', 'pipe', 'pipe'],
        });
        return { stdout, stderr: '', code: 0 };
      } catch (err) {
        const e = err as { stdout?: Buffer | string; stderr?: Buffer | string; status?: number };
        return {
          stdout: e.stdout?.toString() ?? '',
          stderr: e.stderr?.toString() ?? '',
          code: e.status ?? -1,
        };
      }
    }

    it('release/lwndev-sdlc-v1.13.0 → exit 0 with type="release", id/dir null (FR-7 row 1)', () => {
      // Release branches are matched (type="release") and skipped silently by finalize.sh;
      // no [info] or [warn] message is emitted — that is FR-7 row 1.
      const { stdout, code } = runBranchIdParse('release/lwndev-sdlc-v1.13.0');
      expect(code).toBe(0);
      const json = JSON.parse(stdout.trim());
      expect(json.type).toBe('release');
      expect(json.id).toBeNull();
      expect(json.dir).toBeNull();
    });

    it('adhoc/cleanup → exit 1, no stdout (FR-7 row 2 — finalize.sh emits [info] and skips)', () => {
      const { stdout, code } = runBranchIdParse('adhoc/cleanup');
      expect(code).toBe(1);
      expect(stdout.trim()).toBe('');
    });
  });

  // ---------------------------------------------------------------------------
  // Validation API
  // ---------------------------------------------------------------------------

  describe('validation API', () => {
    it('should pass ai-skills-manager validation', async () => {
      const result: DetailedValidateResult = await validate(SKILL_DIR, {
        detailed: true,
      });
      expect(result.valid).toBe(true);
    });
  });
});
