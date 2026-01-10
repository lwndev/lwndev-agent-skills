import { homedir } from 'node:os';
import { join } from 'node:path';

export const SKILLS_SOURCE_DIR = 'src/skills';
export const DIST_DIR = 'dist';
export const PROJECT_SKILLS_DIR = '.claude/skills';
export const PERSONAL_SKILLS_DIR = join(homedir(), '.claude', 'skills');

export type Scope = 'project' | 'personal';

export function getSkillsDir(scope: Scope): string {
  return scope === 'project' ? PROJECT_SKILLS_DIR : PERSONAL_SKILLS_DIR;
}
