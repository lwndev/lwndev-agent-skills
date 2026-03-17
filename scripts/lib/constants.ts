import { join } from 'node:path';

export const PLUGINS_SOURCE_DIR = 'src/plugins';
export const DIST_DIR = 'dist';

export function getPluginSourceDir(pluginName: string): string {
  return join(PLUGINS_SOURCE_DIR, pluginName);
}

export function getPluginSkillsSourceDir(pluginName: string): string {
  return join(PLUGINS_SOURCE_DIR, pluginName, 'skills');
}

export function getPluginOutputDir(pluginName: string): string {
  return join(DIST_DIR, `${pluginName}-plugin`);
}

export function getPluginSkillsOutputDir(pluginName: string): string {
  return join(getPluginOutputDir(pluginName), 'skills');
}

export function getPluginManifestOutputDir(pluginName: string): string {
  return join(getPluginOutputDir(pluginName), '.claude-plugin');
}
