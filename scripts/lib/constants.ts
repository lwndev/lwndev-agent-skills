import { join } from 'node:path';

export const SKILLS_SOURCE_DIR = 'src/skills';
export const DIST_DIR = 'dist';

export const PLUGIN_NAME = 'lwndev-sdlc';
export const PLUGIN_OUTPUT_DIR = join(DIST_DIR, `${PLUGIN_NAME}-plugin`);
export const PLUGIN_SKILLS_DIR = join(PLUGIN_OUTPUT_DIR, 'skills');
export const PLUGIN_MANIFEST_DIR = join(PLUGIN_OUTPUT_DIR, '.claude-plugin');
export const PLUGIN_SOURCE_DIR = join('src', 'plugin');
