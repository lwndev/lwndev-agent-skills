import { describe, it, expect, beforeAll } from 'vitest';
import { readFile } from 'node:fs/promises';
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
  const pattern = new RegExp(
    `^##\\s+${heading.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&')}\\s*$`,
    'm'
  );
  const match = pattern.exec(body);
  if (!match) return null;
  const start = match.index + match[0].length;
  const rest = body.slice(start);
  const nextHeading = /^##\s+/m.exec(rest);
  const end = nextHeading ? nextHeading.index : rest.length;
  return rest.slice(0, end);
}

function extractSubsection(section: string, heading: string): string | null {
  const pattern = new RegExp(
    `^###\\s+${heading.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&')}\\s*$`,
    'm'
  );
  const match = pattern.exec(section);
  if (!match) return null;
  const start = match.index + match[0].length;
  const rest = section.slice(start);
  const nextHeading = /^###?\s+/m.exec(rest);
  const end = nextHeading ? nextHeading.index : rest.length;
  return rest.slice(0, end);
}

describe('FEAT-023 rollout — Inputs dimension', () => {
  it.each(TARGET_SKILLS)('[P0] %s SKILL.md frontmatter parses to an object', (name) => {
    const fx = fixtures.get(name)!;
    expect(fx.data).toBeTypeOf('object');
    expect(fx.data).not.toBeNull();
    expect(fx.data.name).toBe(name);
    expect(typeof fx.data.description).toBe('string');
    expect((fx.data.description as string).trim().length).toBeGreaterThan(0);
  });

  it.each(TARGET_SKILLS)('[P0] %s preserves allowed-tools set vs main', (name) => {
    const fx = fixtures.get(name)!;
    const headRaw: string[] = Array.isArray(fx.data['allowed-tools'])
      ? (fx.data['allowed-tools'] as string[])
      : [];
    const headSet = new Set(headRaw.map((t) => t.trim()));

    let mainContent: string;
    try {
      mainContent = execSync(`git show main:${fx.path}`, { encoding: 'utf-8' });
    } catch {
      return;
    }
    const mainData = matter(mainContent).data as Record<string, unknown>;
    const mainRaw: string[] = Array.isArray(mainData['allowed-tools'])
      ? (mainData['allowed-tools'] as string[])
      : [];
    const mainSet = new Set(mainRaw.map((t) => t.trim()));

    if (mainSet.size === 0 && headSet.size === 0) return;
    expect([...headSet].sort()).toEqual([...mainSet].sort());
  });

  it.each(TARGET_SKILLS)('[P1] %s Output Style section has no Unicode smart quotes', (name) => {
    const fx = fixtures.get(name)!;
    const section = extractSection(fx.content, 'Output Style');
    expect(section, `Output Style section missing in ${name}`).not.toBeNull();
    const smart = section!.match(/[‘’“”]/g);
    expect(smart ?? []).toEqual([]);
  });

  it.each(TARGET_SKILLS)('[P1] %s has exactly one Output Style heading', (name) => {
    const fx = fixtures.get(name)!;
    const matches = fx.content.match(/^##\s+Output Style\s*$/gm) ?? [];
    expect(
      matches.length,
      `expected 1 "## Output Style" heading in ${name}, got ${matches.length}`
    ).toBe(1);
  });

  it.each(TARGET_SKILLS)(
    '[P1] %s Output Style precedes any ## Step N heading (if present)',
    (name) => {
      const fx = fixtures.get(name)!;
      const osIdx = fx.content.search(/^##\s+Output Style\s*$/m);
      const stepMatch = /^##\s+Step\s+\d+/m.exec(fx.content);
      if (!stepMatch) return;
      expect(osIdx).toBeGreaterThan(-1);
      expect(osIdx, `Output Style must precede "## Step N" in ${name}`).toBeLessThan(
        stepMatch.index
      );
    }
  );

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
      expect(arrows ?? []).toEqual([]);
    }
  );
});

describe('FEAT-023 rollout — State transitions dimension', () => {
  it('[P0] every target SKILL.md contains an Output Style section (no duplicate / missing heading)', () => {
    const missing: string[] = [];
    const duplicates: string[] = [];
    for (const name of TARGET_SKILLS) {
      const fx = fixtures.get(name)!;
      const matches = fx.content.match(/^##\s+Output Style\s*$/gm) ?? [];
      if (matches.length === 0) missing.push(name);
      else if (matches.length > 1) duplicates.push(name);
    }
    expect({ missing, duplicates }).toEqual({ missing: [], duplicates: [] });
  });
});

describe('FEAT-023 rollout — Environment / Dependency-failure dimension', () => {
  it.each(TARGET_SKILLS)('[P0] %s passes ai-skills-manager validate()', async (name) => {
    const skillPath = join(SKILLS_DIR, name);
    const result = await validate(skillPath);
    const anyResult = result as unknown as { valid?: boolean; ok?: boolean; errors?: unknown[] };
    const pass = anyResult.valid === true || anyResult.ok === true;
    expect(pass, JSON.stringify(result, null, 2)).toBe(true);
  });

  it('[P2] measurement table in requirements doc does not reference node_modules paths', async () => {
    const req = await readFile(
      'requirements/features/FEAT-023-output-token-optimization-rollout.md',
      'utf-8'
    );
    const notesIdx = req.search(/^##\s+Notes\s*$/m);
    const scope = notesIdx >= 0 ? req.slice(notesIdx) : req;
    const hit = scope.match(/node_modules\//);
    expect(hit, 'node_modules path found in Notes measurement scope').toBeNull();
  });
});

describe('FEAT-023 rollout — Cross-cutting dimension', () => {
  it('[P1] lite-narration-rules bullet skeleton is canonical across the 12 target skills (parenthetical examples stripped)', () => {
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

  it('[P1] managing-work-items Output Style fork-contract subsection declares inline execution', () => {
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
});
