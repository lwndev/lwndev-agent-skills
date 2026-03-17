import { readdir, readFile, access } from 'node:fs/promises';
import { join } from 'node:path';
import matter from 'gray-matter';
import { PLUGINS_DIR, getPluginSkillsDir } from './constants.js';

export interface SkillInfo {
  name: string;
  description: string;
  path: string;
}

/**
 * Discover all plugins under plugins/ by looking for directories with .claude-plugin/plugin.json
 */
export async function getSourcePlugins(): Promise<string[]> {
  const plugins: string[] = [];

  try {
    const entries = await readdir(PLUGINS_DIR, { withFileTypes: true });

    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith('.')) continue;

      const pluginJsonPath = join(PLUGINS_DIR, entry.name, '.claude-plugin', 'plugin.json');
      try {
        await access(pluginJsonPath);
        plugins.push(entry.name);
      } catch {
        // Skip directories without .claude-plugin/plugin.json
      }
    }
  } catch (err) {
    throw new Error(`Failed to read plugins directory: ${err}`);
  }

  return plugins.sort();
}

/**
 * Get all skills for a specific plugin by reading SKILL.md frontmatter
 */
export async function getSourceSkills(pluginName: string): Promise<SkillInfo[]> {
  const skills: SkillInfo[] = [];
  const skillsDir = getPluginSkillsDir(pluginName);

  try {
    const entries = await readdir(skillsDir, { withFileTypes: true });

    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith('.')) continue;

      const skillPath = join(skillsDir, entry.name);
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
    throw new Error(`Failed to read skills directory for plugin "${pluginName}": ${err}`);
  }

  return skills.sort((a, b) => a.name.localeCompare(b.name));
}
