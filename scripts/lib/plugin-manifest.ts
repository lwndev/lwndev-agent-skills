import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { getPluginManifestDir } from './constants.js';

const MARKETPLACE_MANIFEST_PATH = join('.claude-plugin', 'marketplace.json');

export interface PluginManifest {
  name: string;
  version: string;
  description: string;
  author?: { name: string; email?: string };
  repository?: string;
  license?: string;
  keywords?: string[];
  [key: string]: unknown;
}

export interface MarketplacePluginEntry {
  name: string;
  source: string;
  description: string;
  version: string;
  [key: string]: unknown;
}

export interface MarketplaceManifest {
  name: string;
  owner: { name: string; email?: string };
  metadata?: { description?: string; pluginRoot?: string; [key: string]: unknown };
  plugins: MarketplacePluginEntry[];
  [key: string]: unknown;
}

export async function readPluginManifest(pluginName: string): Promise<PluginManifest> {
  const manifestPath = join(getPluginManifestDir(pluginName), 'plugin.json');
  const content = await readFile(manifestPath, 'utf-8');
  return JSON.parse(content) as PluginManifest;
}

export async function writePluginManifest(
  pluginName: string,
  manifest: PluginManifest
): Promise<void> {
  const manifestPath = join(getPluginManifestDir(pluginName), 'plugin.json');
  await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n', 'utf-8');
}

export async function readMarketplaceManifest(): Promise<MarketplaceManifest> {
  const content = await readFile(MARKETPLACE_MANIFEST_PATH, 'utf-8');
  return JSON.parse(content) as MarketplaceManifest;
}

export async function writeMarketplaceManifest(manifest: MarketplaceManifest): Promise<void> {
  await writeFile(MARKETPLACE_MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n', 'utf-8');
}

export function getMarketplacePluginEntry(
  marketplace: MarketplaceManifest,
  pluginName: string
): MarketplacePluginEntry | undefined {
  return marketplace.plugins.find((p) => p.name === pluginName);
}
