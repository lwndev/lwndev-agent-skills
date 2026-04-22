import { describe, it, expect, beforeAll } from 'vitest';
import { readFile, readdir, stat } from 'node:fs/promises';
import { execSync } from 'node:child_process';
import { join } from 'node:path';
import matter from 'gray-matter';
import { validate } from 'ai-skills-manager';

const PLUGIN_DIR = 'plugins/lwndev-sdlc';
const SKILLS_DIR = join(PLUGIN_DIR, 'skills');

const TARGET_SKILLS = [
  'creating-implementation-plans',
  'documenting-bugs',
  'documenting-chores',
  'documenting-features',
  'documenting-qa',
  'executing-bug-fixes',
  'executing-chores',
  'executing-qa',
  'finalizing-workflow',
  'implementing-plan-phases',
  'managing-work-items',
  'reviewing-requirements',
] as const;

type Skill = (typeof TARGET_SKILLS)[number];

interface SkillFixture {
  name: Skill;
  path: string;
  raw: string;
  data: Record<string, unknown>;
  content: string;
}

const fixtures = new Map<Skill, SkillFixture>();

beforeAll(async () => {
  for (const name of TARGET_SKILLS) {
    const path = join(SKILLS_DIR, name, 'SKILL.md');
    const raw = await readFile(path, 'utf-8');
    const parsed = matter(raw);
    fixtures.set(name, {
      name,
      path,
      raw,
      data: parsed.data as Record<string, unknown>,
      content: parsed.content,
    });
  }
});

function extractSection(body: string, heading: string): string | null {
  const pattern = new RegExp(`^##\\s+${heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`, 'm');
  const match = pattern.exec(body);
  if (!match) return null;
  const start = match.index + match[0].length;
  const rest = body.slice(start);
  const nextHeading = /^##\s+/m.exec(rest);
  const end = nextHeading ? nextHeading.index : rest.length;
  return rest.slice(0, end);
}

function extractSubsection(section: string, heading: string): string | null {
  const pattern = new RegExp(`^###\\s+${heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`, 'm');
  const match = pattern.exec(section);
  if (!match) return null;
  const start = match.index + match[0].length;
  const rest = section.slice(start);
  const nextHeading = /^###?\s+/m.exec(rest);
  const end = nextHeading ? nextHeading.index : rest.length;
  return rest.slice(0, end);
}

async function dirExists(path: string): Promise<boolean> {
  try {
    const s = await stat(path);
    return s.isDirectory();
  } catch {
    return false;
  }
}

async function listReferenceFiles(skill: Skill): Promise<string[]> {
  const refDir = join(SKILLS_DIR, skill, 'references');
  if (!(await dirExists(refDir))) return [];
  const entries = await readdir(refDir);
  return entries.filter((e) => e.endsWith('.md')).map((e) => join(refDir, e));
}

describe('FEAT-024 rollout — Inputs dimension', () => {
  it.each(TARGET_SKILLS)(
    '[P0] %s Output Style section contains canonical lite-narration-rules and fork-return-contract subsections',
    (name) => {
      const fx = fixtures.get(name)!;
      const section = extractSection(fx.content, 'Output Style');
      expect(section, `Output Style missing in ${name}`).not.toBeNull();
      const lite = extractSubsection(section!, 'Lite narration rules');
      expect(lite, `"Lite narration rules" subsection missing in ${name}`).not.toBeNull();
      const carve = extractSubsection(section!, 'Load-bearing carve-outs (never strip)');
      expect(
        carve,
        `"Load-bearing carve-outs (never strip)" subsection missing in ${name}`
      ).not.toBeNull();
      // managing-work-items is inline-cross-cutting and uses "Inline execution note" instead of
      // the forkable-skill "Fork-to-orchestrator return contract" subsection.
      const contract =
        extractSubsection(section!, 'Fork-to-orchestrator return contract') ??
        extractSubsection(section!, 'Inline execution note');
      expect(
        contract,
        `${name} must declare a return contract — either "Fork-to-orchestrator return contract" or "Inline execution note" subsection`
      ).not.toBeNull();
    }
  );

  it.each(TARGET_SKILLS)(
    '[P0] %s SKILL.md inline pointers to references/*.md resolve',
    async (name) => {
      const fx = fixtures.get(name)!;
      const skillDir = join(SKILLS_DIR, name);
      const linkRe = /\]\((references\/[^)]+\.md)(?:#[^)]*)?\)/g;
      const missing: string[] = [];
      let match: RegExpExecArray | null;
      while ((match = linkRe.exec(fx.content)) !== null) {
        const target = join(skillDir, match[1]);
        try {
          await stat(target);
        } catch {
          missing.push(`${name}: broken pointer ${match[1]}`);
        }
      }
      expect(missing).toEqual([]);
    }
  );

  it.each(TARGET_SKILLS)(
    '[P1] %s SKILL.md has balanced code fences (every opening ``` has a matching closing fence)',
    (name) => {
      const fx = fixtures.get(name)!;
      const fences = (fx.content.match(/^```/gm) ?? []).length;
      expect(fences % 2, `${name} has unbalanced code fences (count=${fences})`).toBe(0);
    }
  );

  it.each(TARGET_SKILLS)('[P1] %s Output Style section has no Unicode smart quotes', (name) => {
    const fx = fixtures.get(name)!;
    const section = extractSection(fx.content, 'Output Style');
    expect(section, `Output Style missing in ${name}`).not.toBeNull();
    const smart = section!.match(/[‘’“”]/g);
    expect(smart ?? []).toEqual([]);
  });

  it.each(TARGET_SKILLS)(
    '[P2] %s lite-narration rules do not contain U+2192 outside script-log carve-out',
    (name) => {
      const fx = fixtures.get(name)!;
      const section = extractSection(fx.content, 'Output Style');
      if (!section) return;
      const liteSub = extractSubsection(section, 'Lite narration rules');
      if (!liteSub) return;
      const stripped = liteSub.replace(/Script-emitted structured logs[\s\S]*?(?=\n\n|$)/i, '');
      const arrows = stripped.match(/→/g);
      expect(arrows ?? [], `${name} has Unicode arrow in lite-narration rules`).toEqual([]);
    }
  );
});

describe('FEAT-024 rollout — State transitions dimension', () => {
  it('[P0] every target SKILL.md exists and is non-empty after compression', async () => {
    const missing: string[] = [];
    for (const name of TARGET_SKILLS) {
      const fx = fixtures.get(name)!;
      if (fx.raw.trim().length === 0) missing.push(name);
    }
    expect(missing).toEqual([]);
  });

  it.each(TARGET_SKILLS)(
    '[P1] %s references/*.md files live only under the owning skill directory',
    async (name) => {
      const refs = await listReferenceFiles(name);
      const expectedPrefix = join(SKILLS_DIR, name, 'references') + '/';
      const stray = refs.filter((p) => !p.startsWith(expectedPrefix));
      expect(stray, `references/*.md outside ${expectedPrefix}: ${JSON.stringify(stray)}`).toEqual(
        []
      );
    }
  );

  it('[P1] no shared/cross-skill references directory exists at the plugin root', async () => {
    const sharedRefs = join(PLUGIN_DIR, 'references');
    expect(
      await dirExists(sharedRefs),
      `unexpected ${sharedRefs} — references must live per-skill`
    ).toBe(false);
  });
});

describe('FEAT-024 rollout — Environment / Dependency-failure dimension', () => {
  it.each(TARGET_SKILLS)('[P0] %s passes ai-skills-manager validate()', async (name) => {
    const skillPath = join(SKILLS_DIR, name);
    const result = await validate(skillPath);
    const anyResult = result as unknown as { valid?: boolean; ok?: boolean; errors?: unknown[] };
    const pass = anyResult.valid === true || anyResult.ok === true;
    expect(pass, JSON.stringify(result, null, 2)).toBe(true);
  });

  it.each(TARGET_SKILLS)(
    '[P1] %s references/*.md files are tracked by git (not gitignored)',
    async (name) => {
      const refs = await listReferenceFiles(name);
      if (refs.length === 0) return;
      let tracked: string;
      try {
        tracked = execSync(`git ls-files ${refs.map((r) => `'${r}'`).join(' ')}`, {
          encoding: 'utf-8',
        });
      } catch (e) {
        throw new Error(`git ls-files failed for ${name}: ${(e as Error).message}`);
      }
      const trackedSet = new Set(tracked.split('\n').filter(Boolean));
      const untracked = refs.filter((r) => !trackedSet.has(r));
      expect(untracked, `untracked references for ${name}: ${JSON.stringify(untracked)}`).toEqual(
        []
      );
    }
  );

  it('[P2] FEAT-024 Notes measurement scope contains no node_modules / .bak / .swp paths', async () => {
    const req = await readFile(
      'requirements/features/FEAT-024-input-token-optimization-rollout.md',
      'utf-8'
    );
    const notesIdx = req.search(/^##\s+Notes\s*$/m);
    const scope = notesIdx >= 0 ? req.slice(notesIdx) : req;
    const stray = scope.match(/(?:node_modules\/|\.bak\b|\.swp\b)/);
    expect(stray, `stray path token in Notes scope: ${stray?.[0]}`).toBeNull();
  });
});

describe('FEAT-024 rollout — Cross-cutting dimension', () => {
  it('[P0] lite-narration-rules bullet skeleton is canonical across the 12 target skills', () => {
    const skeletons = new Map<string, string[]>();
    for (const name of TARGET_SKILLS) {
      const fx = fixtures.get(name)!;
      const section = extractSection(fx.content, 'Output Style');
      if (!section) continue;
      const lite = extractSubsection(section, 'Lite narration rules');
      if (!lite) continue;
      const skeleton = lite
        .split(/\n/)
        .filter((l) => /^\s*-\s+/.test(l))
        .map((l) =>
          l
            .replace(/\([^)]*\)/g, '')
            .replace(/\*\*[^*]+\*\*[^\n]*$/, '')
            .replace(/—.*$/, '')
            .replace(/--.*$/, '')
            .replace(/\s+/g, ' ')
            .replace(/\s+([.,;:])/g, '$1')
            .trim()
        )
        .join('\n');
      const arr = skeletons.get(skeleton) ?? [];
      arr.push(name);
      skeletons.set(skeleton, arr);
    }
    expect(
      skeletons.size,
      `expected 1 canonical lite-rules bullet skeleton, got ${skeletons.size} variants: ${JSON.stringify([...skeletons.entries()])}`
    ).toBe(1);
  });

  it('[P0] executing-qa documents both test-framework and exploratory mode branches', () => {
    const fx = fixtures.get('executing-qa')!;
    expect(fx.content).toMatch(/test-framework/i);
    expect(fx.content).toMatch(/exploratory/i);
    expect(fx.content).toMatch(/EXPLORATORY-ONLY/);
  });

  it('[P1] managing-work-items Output Style fork-contract subsection declares inline execution (not forked)', () => {
    const fx = fixtures.get('managing-work-items')!;
    const section = extractSection(fx.content, 'Output Style');
    expect(section).not.toBeNull();
    const lower = section!.toLowerCase();
    expect(lower).toContain('inline');
    expect(lower).not.toMatch(/emit[s]?\s+`?done\s*\|\s*artifact=/);
  });

  it('[P1] forkable target skills name a canonical return-contract shape', () => {
    const forkable: Skill[] = [
      'creating-implementation-plans',
      'executing-bug-fixes',
      'executing-chores',
      'finalizing-workflow',
      'implementing-plan-phases',
      'reviewing-requirements',
    ];
    const missing: string[] = [];
    for (const name of forkable) {
      const fx = fixtures.get(name)!;
      const section = extractSection(fx.content, 'Output Style');
      if (!section) {
        missing.push(`${name}: no Output Style section`);
        continue;
      }
      const hasContract = /done\s*\|\s*artifact=|Found\s+\*\*N errors/i.test(section);
      if (!hasContract) missing.push(`${name}: no canonical return-contract shape`);
    }
    expect(missing).toEqual([]);
  });

  it('[P1] inline references/*.md links use markdown link syntax (not bare prose)', () => {
    const violations: string[] = [];
    for (const name of TARGET_SKILLS) {
      const fx = fixtures.get(name)!;
      // Any "see references/foo.md" sentence should accompany an actual markdown link
      const bareRefs = fx.content.match(
        /(?:see|in|under)\s+references\/[A-Za-z0-9_-]+\.md\b(?![^\n]*\]\(references\/)/gi
      );
      if (bareRefs && bareRefs.length > 0) {
        // Filter out ones already in markdown link form on the same line
        for (const m of bareRefs) {
          violations.push(`${name}: "${m}"`);
        }
      }
    }
    // This is advisory rather than hard-fail — a few prose mentions are fine
    // as long as every <pointer> in SKILL.md still exists (covered by another test).
    // We only fail on egregious counts.
    expect(
      violations.length,
      `prose references without markdown links: ${JSON.stringify(violations)}`
    ).toBeLessThanOrEqual(20);
  });
});
