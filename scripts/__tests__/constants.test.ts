import { join } from 'node:path';
import {
  PLUGINS_SOURCE_DIR,
  DIST_DIR,
  getPluginSourceDir,
  getPluginSkillsSourceDir,
  getPluginOutputDir,
  getPluginSkillsOutputDir,
  getPluginManifestOutputDir,
} from '../lib/constants.js';

describe('constants', () => {
  describe('path constants', () => {
    it('should have correct PLUGINS_SOURCE_DIR', () => {
      expect(PLUGINS_SOURCE_DIR).toBe('src/plugins');
    });

    it('should have correct DIST_DIR', () => {
      expect(DIST_DIR).toBe('dist');
    });
  });

  describe('plugin path helpers', () => {
    it('should return correct plugin source dir', () => {
      expect(getPluginSourceDir('lwndev-sdlc')).toBe(join('src', 'plugins', 'lwndev-sdlc'));
    });

    it('should return correct plugin skills source dir', () => {
      expect(getPluginSkillsSourceDir('lwndev-sdlc')).toBe(
        join('src', 'plugins', 'lwndev-sdlc', 'skills')
      );
    });

    it('should return correct plugin output dir', () => {
      expect(getPluginOutputDir('lwndev-sdlc')).toBe(join('dist', 'lwndev-sdlc-plugin'));
    });

    it('should return correct plugin skills output dir', () => {
      expect(getPluginSkillsOutputDir('lwndev-sdlc')).toBe(
        join('dist', 'lwndev-sdlc-plugin', 'skills')
      );
    });

    it('should return correct plugin manifest output dir', () => {
      expect(getPluginManifestOutputDir('lwndev-sdlc')).toBe(
        join('dist', 'lwndev-sdlc-plugin', '.claude-plugin')
      );
    });

    it('should work with different plugin names', () => {
      expect(getPluginSourceDir('another-plugin')).toBe(join('src', 'plugins', 'another-plugin'));
      expect(getPluginOutputDir('another-plugin')).toBe(join('dist', 'another-plugin-plugin'));
    });
  });
});
