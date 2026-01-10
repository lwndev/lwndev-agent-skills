import { readdir, readFile, access } from 'node:fs/promises';
import { join } from 'node:path';
import matter from 'gray-matter';
import { SKILLS_SOURCE_DIR, DIST_DIR, getSkillsDir, type Scope } from './constants.js';

export interface SkillInfo {
  name: string;
  description: string;
  path: string;
}

/**
 * Get all skills from src/skills/ directory by reading SKILL.md frontmatter
 */
export async function getSourceSkills(): Promise<SkillInfo[]> {
  const skills: SkillInfo[] = [];

  try {
    const entries = await readdir(SKILLS_SOURCE_DIR, { withFileTypes: true });

    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith('.')) continue;

      const skillPath = join(SKILLS_SOURCE_DIR, entry.name);
      const skillMdPath = join(skillPath, 'SKILL.md');

      try {
        const content = await readFile(skillMdPath, 'utf-8');
        const { data } = matter(content);

        if (data.name && data.description) {
          skills.push({
            name: data.name,
            description: data.description,
            path: skillPath,
          });
        }
      } catch {
        // Skip directories without valid SKILL.md
      }
    }
  } catch (err) {
    throw new Error(`Failed to read skills directory: ${err}`);
  }

  return skills.sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Get installed skills from a scope (project or personal)
 */
export async function getInstalledSkills(scope: Scope): Promise<SkillInfo[]> {
  const skills: SkillInfo[] = [];
  const skillsDir = getSkillsDir(scope);

  try {
    await access(skillsDir);
    const entries = await readdir(skillsDir, { withFileTypes: true });

    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith('.')) continue;

      const skillPath = join(skillsDir, entry.name);
      const skillMdPath = join(skillPath, 'SKILL.md');

      try {
        const content = await readFile(skillMdPath, 'utf-8');
        const { data } = matter(content);

        skills.push({
          name: data.name || entry.name,
          description: data.description || 'No description',
          path: skillPath,
        });
      } catch {
        // Include directory even if SKILL.md is unreadable
        skills.push({
          name: entry.name,
          description: 'Unable to read description',
          path: skillPath,
        });
      }
    }
  } catch {
    // Directory doesn't exist or is inaccessible - return empty array
    return [];
  }

  return skills.sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Get the packaged skill file path
 */
export function getPackagedSkillPath(skillName: string): string {
  return join(DIST_DIR, `${skillName}.skill`);
}

/**
 * Check if a packaged skill exists in dist/
 */
export async function packagedSkillExists(skillName: string): Promise<boolean> {
  try {
    await access(getPackagedSkillPath(skillName));
    return true;
  } catch {
    return false;
  }
}
