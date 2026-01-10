import { homedir } from 'node:os';
import { join } from 'node:path';
import {
  SKILLS_SOURCE_DIR,
  DIST_DIR,
  PROJECT_SKILLS_DIR,
  PERSONAL_SKILLS_DIR,
  getSkillsDir,
} from '../lib/constants.js';

describe('constants', () => {
  describe('path constants', () => {
    it('should have correct SKILLS_SOURCE_DIR', () => {
      expect(SKILLS_SOURCE_DIR).toBe('src/skills');
    });

    it('should have correct DIST_DIR', () => {
      expect(DIST_DIR).toBe('dist');
    });

    it('should have correct PROJECT_SKILLS_DIR', () => {
      expect(PROJECT_SKILLS_DIR).toBe('.claude/skills');
    });

    it('should have correct PERSONAL_SKILLS_DIR', () => {
      expect(PERSONAL_SKILLS_DIR).toBe(join(homedir(), '.claude', 'skills'));
    });
  });

  describe('getSkillsDir', () => {
    it('should return project path for project scope', () => {
      expect(getSkillsDir('project')).toBe('.claude/skills');
    });

    it('should return personal path for personal scope', () => {
      expect(getSkillsDir('personal')).toBe(join(homedir(), '.claude', 'skills'));
    });
  });
});
