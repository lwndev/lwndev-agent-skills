import { readdir, readFile, access } from 'node:fs/promises';
import { join } from 'node:path';
import matter from 'gray-matter';
import { SKILLS_SOURCE_DIR, PLUGIN_MANIFEST_DIR } from './constants.js';

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
 * Check if the plugin has been built (plugin.json exists in output)
 */
export async function pluginBuildExists(): Promise<boolean> {
  try {
    await access(join(PLUGIN_MANIFEST_DIR, 'plugin.json'));
    return true;
  } catch {
    return false;
  }
}
