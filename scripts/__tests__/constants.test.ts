import { describe, it, expect } from 'vitest';
import { join } from 'node:path';
import {
  PLUGINS_DIR,
  PROJECT_SKILLS_DIR,
  PROJECT_AGENTS_DIR,
  getPluginDir,
  getPluginSkillsDir,
  getPluginAgentsDir,
  getPluginManifestDir,
} from '../lib/constants.js';

describe('constants', () => {
  describe('path constants', () => {
    it('should have correct PLUGINS_DIR', () => {
      expect(PLUGINS_DIR).toBe('plugins');
    });
  });

  describe('plugin path helpers', () => {
    it('should return correct plugin dir', () => {
      expect(getPluginDir('lwndev-sdlc')).toBe(join('plugins', 'lwndev-sdlc'));
    });

    it('should return correct plugin skills dir', () => {
      expect(getPluginSkillsDir('lwndev-sdlc')).toBe(join('plugins', 'lwndev-sdlc', 'skills'));
    });

    it('should return correct plugin manifest dir', () => {
      expect(getPluginManifestDir('lwndev-sdlc')).toBe(
        join('plugins', 'lwndev-sdlc', '.claude-plugin')
      );
    });

    it('should return correct plugin agents dir', () => {
      expect(getPluginAgentsDir('lwndev-sdlc')).toBe(join('plugins', 'lwndev-sdlc', 'agents'));
    });

    it('should work with different plugin names', () => {
      expect(getPluginDir('another-plugin')).toBe(join('plugins', 'another-plugin'));
      expect(getPluginSkillsDir('another-plugin')).toBe(
        join('plugins', 'another-plugin', 'skills')
      );
      expect(getPluginAgentsDir('another-plugin')).toBe(
        join('plugins', 'another-plugin', 'agents')
      );
    });
  });

  describe('project path constants', () => {
    it('should have correct PROJECT_SKILLS_DIR', () => {
      expect(PROJECT_SKILLS_DIR).toBe(join('.claude', 'skills'));
    });

    it('should have correct PROJECT_AGENTS_DIR', () => {
      expect(PROJECT_AGENTS_DIR).toBe(join('.claude', 'agents'));
    });
  });
});
