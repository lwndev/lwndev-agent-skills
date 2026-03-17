import { join } from 'node:path';

export const PLUGINS_DIR = 'plugins';

export function getPluginDir(pluginName: string): string {
  return join(PLUGINS_DIR, pluginName);
}

export function getPluginSkillsDir(pluginName: string): string {
  return join(PLUGINS_DIR, pluginName, 'skills');
}

export function getPluginManifestDir(pluginName: string): string {
  return join(PLUGINS_DIR, pluginName, '.claude-plugin');
}
