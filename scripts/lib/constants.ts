import { join } from 'node:path';

export const PLUGINS_DIR = 'plugins';
export const PROJECT_SKILLS_DIR = join('.claude', 'skills');
export const PROJECT_AGENTS_DIR = join('.claude', 'agents');

export function getPluginDir(pluginName: string): string {
  return join(PLUGINS_DIR, pluginName);
}

export function getPluginSkillsDir(pluginName: string): string {
  return join(PLUGINS_DIR, pluginName, 'skills');
}

export function getPluginAgentsDir(pluginName: string): string {
  return join(PLUGINS_DIR, pluginName, 'agents');
}

export function getPluginManifestDir(pluginName: string): string {
  return join(PLUGINS_DIR, pluginName, '.claude-plugin');
}
