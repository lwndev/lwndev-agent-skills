import { join } from 'node:path';
import {
  SKILLS_SOURCE_DIR,
  DIST_DIR,
  PLUGIN_NAME,
  PLUGIN_OUTPUT_DIR,
  PLUGIN_SKILLS_DIR,
  PLUGIN_MANIFEST_DIR,
  PLUGIN_SOURCE_DIR,
} from '../lib/constants.js';

describe('constants', () => {
  describe('path constants', () => {
    it('should have correct SKILLS_SOURCE_DIR', () => {
      expect(SKILLS_SOURCE_DIR).toBe('src/skills');
    });

    it('should have correct DIST_DIR', () => {
      expect(DIST_DIR).toBe('dist');
    });
  });

  describe('plugin constants', () => {
    it('should have correct PLUGIN_NAME', () => {
      expect(PLUGIN_NAME).toBe('lwndev-sdlc');
    });

    it('should have correct PLUGIN_OUTPUT_DIR', () => {
      expect(PLUGIN_OUTPUT_DIR).toBe(join('dist', 'lwndev-sdlc-plugin'));
    });

    it('should have correct PLUGIN_SKILLS_DIR', () => {
      expect(PLUGIN_SKILLS_DIR).toBe(join('dist', 'lwndev-sdlc-plugin', 'skills'));
    });

    it('should have correct PLUGIN_MANIFEST_DIR', () => {
      expect(PLUGIN_MANIFEST_DIR).toBe(join('dist', 'lwndev-sdlc-plugin', '.claude-plugin'));
    });

    it('should have correct PLUGIN_SOURCE_DIR', () => {
      expect(PLUGIN_SOURCE_DIR).toBe(join('src', 'plugin'));
    });
  });
});
