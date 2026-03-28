#!/usr/bin/env tsx
import { parseArgs } from 'node:util';
import { readFile, writeFile, access } from 'node:fs/promises';
import { join } from 'node:path';
import { execSync } from 'node:child_process';
import semver from 'semver';
import { getSourcePlugins } from './lib/skill-utils.js';
import { getPluginDir } from './lib/constants.js';
import {
  readPluginManifest,
  writePluginManifest,
  readMarketplaceManifest,
  writeMarketplaceManifest,
  getMarketplacePluginEntry,
} from './lib/plugin-manifest.js';
import {
  isWorkingTreeClean,
  getCurrentBranch,
  getDefaultBranch,
  getLatestTagForPlugin,
  getCommitsSinceTag,
  filterNoiseCommits,
} from './lib/git-utils.js';
import { printSuccess, printError, printInfo, printWarning } from './lib/prompts.js';
import type { ParsedCommit } from './lib/git-utils.js';

type BumpType = 'patch' | 'minor' | 'major';
const VALID_BUMPS: BumpType[] = ['patch', 'minor', 'major'];
const REPO_URL = 'https://github.com/lwndev/lwndev-marketplace';

function parseCliArgs(): { plugin?: string; bump?: string; version?: string } {
  const { values } = parseArgs({
    options: {
      plugin: { type: 'string' },
      bump: { type: 'string' },
      version: { type: 'string' },
    },
    strict: false,
  });
  return values as { plugin?: string; bump?: string; version?: string };
}

function validateArgs(args: { bump?: string; version?: string }):
  | {
      mode: 'bump';
      bump: BumpType;
    }
  | {
      mode: 'explicit';
      version: string;
    } {
  if (args.bump && args.version) {
    printError('Specify either --bump or --version, not both');
    process.exit(1);
  }

  if (!args.bump && !args.version) {
    printError('Specify --bump <patch|minor|major> or --version <x.y.z>');
    process.exit(1);
  }

  if (args.bump) {
    if (!VALID_BUMPS.includes(args.bump as BumpType)) {
      printError(`Invalid bump type "${args.bump}". Must be one of: ${VALID_BUMPS.join(', ')}`);
      process.exit(1);
    }
    return { mode: 'bump', bump: args.bump as BumpType };
  }

  if (!semver.valid(args.version!)) {
    printError(`"${args.version}" is not a valid semver version`);
    process.exit(1);
  }

  return { mode: 'explicit', version: args.version! };
}

async function selectPlugin(pluginFlag?: string): Promise<string> {
  const plugins = await getSourcePlugins();

  if (plugins.length === 0) {
    printError('No plugins found in plugins/');
    process.exit(1);
  }

  if (pluginFlag) {
    if (!plugins.includes(pluginFlag)) {
      printError(`Plugin "${pluginFlag}" not found. Available plugins: ${plugins.join(', ')}`);
      process.exit(1);
    }
    return pluginFlag;
  }

  if (plugins.length === 1) {
    printInfo(`Using plugin: ${plugins[0]}`);
    return plugins[0];
  }

  printError(
    `Multiple plugins found. Specify --plugin <name>. Available plugins: ${plugins.join(', ')}`
  );
  process.exit(1);
}

function computeNewVersion(
  currentVersion: string,
  versionArg: ReturnType<typeof validateArgs>
): string {
  if (versionArg.mode === 'bump') {
    const newVersion = semver.inc(currentVersion, versionArg.bump);
    if (!newVersion) {
      printError(`Failed to compute ${versionArg.bump} bump from ${currentVersion}`);
      process.exit(1);
    }
    return newVersion;
  }

  if (!semver.gt(versionArg.version, currentVersion)) {
    printError(
      `New version ${versionArg.version} must be greater than current version ${currentVersion}`
    );
    process.exit(1);
  }

  return versionArg.version;
}

function groupCommitsByType(commits: ParsedCommit[]): Map<string, ParsedCommit[]> {
  const groups = new Map<string, ParsedCommit[]>();
  const typeLabels: Record<string, string> = {
    feat: 'Features',
    fix: 'Bug Fixes',
    chore: 'Chores',
    docs: 'Documentation',
    refactor: 'Refactoring',
    test: 'Tests',
    ci: 'CI',
    style: 'Style',
    perf: 'Performance',
    other: 'Other',
  };

  for (const commit of commits) {
    const label = typeLabels[commit.type] ?? typeLabels['other'];
    const group = groups.get(label) ?? [];
    group.push(commit);
    groups.set(label, group);
  }

  return groups;
}

function collapseByScope(commits: ParsedCommit[]): ParsedCommit[] {
  // Pre-collect commits per scope
  const scopeGroups = new Map<string, ParsedCommit[]>();
  for (const commit of commits) {
    if (!commit.scope) continue;
    const group = scopeGroups.get(commit.scope) ?? [];
    group.push(commit);
    scopeGroups.set(commit.scope, group);
  }

  // Emit in original order; collapse at first occurrence of each scope
  const emitted = new Set<string>();
  const result: ParsedCommit[] = [];

  for (const commit of commits) {
    if (!commit.scope) {
      result.push(commit);
      continue;
    }
    if (emitted.has(commit.scope)) continue;
    emitted.add(commit.scope);

    const group = scopeGroups.get(commit.scope)!;
    if (group.length === 1) {
      result.push(group[0]);
    } else {
      result.push({
        hash: group[0].hash,
        type: group[0].type,
        scope: commit.scope,
        message: `${group[0].message} (+${group.length - 1} more)`,
        raw: group[0].raw,
      });
    }
  }

  return result;
}

function generateChangelog(
  newVersion: string,
  pluginName: string,
  commits: ParsedCommit[],
  previousTag: string | null
): string {
  const date = new Date().toISOString().split('T')[0];
  const newTag = `${pluginName}@${newVersion}`;

  const filtered = filterNoiseCommits(commits);

  let content = `## [${newVersion}] - ${date}\n\n`;

  if (filtered.length === 0) {
    content += '_No notable changes._\n';
  } else {
    const groups = groupCommitsByType(filtered);

    for (const [label, groupCommits] of groups) {
      const collapsed = collapseByScope(groupCommits);
      content += `### ${label}\n\n`;
      for (const commit of collapsed) {
        const scope = commit.scope ? `**${commit.scope}:** ` : '';
        content += `- ${scope}${commit.message}\n`;
      }
      content += '\n';
    }
  }

  if (previousTag) {
    content += `[${newVersion}]: ${REPO_URL}/compare/${previousTag}...${newTag}\n`;
  }

  return content;
}

async function updateChangelog(pluginName: string, newContent: string): Promise<string> {
  const changelogPath = join(getPluginDir(pluginName), 'CHANGELOG.md');
  let existing = '';

  try {
    await access(changelogPath);
    existing = await readFile(changelogPath, 'utf-8');
  } catch {
    // File doesn't exist, start fresh
  }

  const header = '# Changelog\n\n';
  let body = existing;

  if (existing.startsWith('# Changelog')) {
    body = existing.slice(existing.indexOf('\n\n') + 2);
  }

  const full = header + newContent + '\n' + body;
  await writeFile(changelogPath, full, 'utf-8');

  return changelogPath;
}

async function updateReadme(pluginName: string, newVersion: string): Promise<string | null> {
  const readmePath = join(getPluginDir(pluginName), 'README.md');
  let content: string;

  try {
    await access(readmePath);
    content = await readFile(readmePath, 'utf-8');
  } catch {
    return null;
  }
  const date = new Date().toISOString().split('T')[0];
  const versionLine = `**Version:** ${newVersion} | **Released:** ${date}`;

  // Check if version line already exists
  const versionPattern = /^\*\*Version:\*\*.+$/m;
  if (versionPattern.test(content)) {
    content = content.replace(versionPattern, versionLine);
  } else {
    // Insert after first heading
    const headingEnd = content.indexOf('\n');
    if (headingEnd !== -1) {
      content = content.slice(0, headingEnd) + '\n\n' + versionLine + content.slice(headingEnd);
    }
  }

  await writeFile(readmePath, content, 'utf-8');
  return readmePath;
}

async function main(): Promise<void> {
  // Parse and validate arguments
  const args = parseCliArgs();
  const versionArg = validateArgs(args);

  // Check working tree
  if (!isWorkingTreeClean()) {
    printError('Working tree has uncommitted changes. Commit or stash them first.');
    process.exit(1);
  }

  // Select plugin
  const pluginName = await selectPlugin(args.plugin);

  // Read current version
  const pluginManifest = await readPluginManifest(pluginName);
  const currentVersion = pluginManifest.version;

  // Compute new version
  const newVersion = computeNewVersion(currentVersion, versionArg);

  // Create release branch if on default branch
  const currentBranch = getCurrentBranch();
  const defaultBranch = getDefaultBranch();
  const releaseBranch = `release/${pluginName}-v${newVersion}`;

  if (currentBranch === defaultBranch) {
    try {
      execSync(`git checkout -b "${releaseBranch}"`, { stdio: 'pipe' });
    } catch (err) {
      const stderr = (err as { stderr?: Buffer | string }).stderr?.toString().trim() ?? '';
      if (stderr.includes('already exists')) {
        printError(
          `Branch "${releaseBranch}" already exists. Delete it first or switch to it manually.`
        );
      } else {
        printError(`Failed to create branch "${releaseBranch}": ${stderr}`);
      }
      process.exit(1);
    }
    printSuccess(`Created branch: ${releaseBranch}`);
  }

  // Verify plugin exists in marketplace
  const marketplace = await readMarketplaceManifest();
  const marketplaceEntry = getMarketplacePluginEntry(marketplace, pluginName);
  if (!marketplaceEntry) {
    printError(`Plugin "${pluginName}" not found in marketplace.json`);
    process.exit(1);
  }

  // Update plugin manifest
  pluginManifest.version = newVersion;
  await writePluginManifest(pluginName, pluginManifest);
  const pluginManifestPath = join(getPluginDir(pluginName), '.claude-plugin', 'plugin.json');
  printSuccess(`Updated: ${pluginManifestPath}`);

  // Update marketplace manifest
  marketplaceEntry.version = newVersion;
  if (marketplaceEntry.description !== pluginManifest.description) {
    printInfo(`Syncing description from plugin.json to marketplace.json`);
    marketplaceEntry.description = pluginManifest.description;
  }
  await writeMarketplaceManifest(marketplace);
  printSuccess(`Updated: .claude-plugin/marketplace.json`);

  // Generate changelog
  const previousTag = getLatestTagForPlugin(pluginName);
  const commits = getCommitsSinceTag(previousTag);
  if (commits.length === 0) {
    printWarning('No commits since last tag. Changelog section will be empty.');
  }
  const changelogContent = generateChangelog(newVersion, pluginName, commits, previousTag);
  const changelogPath = await updateChangelog(pluginName, changelogContent);
  printSuccess(`Updated: ${changelogPath}`);

  // Update README
  const readmePath = await updateReadme(pluginName, newVersion);
  if (readmePath) {
    printSuccess(`Updated: ${readmePath}`);
  } else {
    printWarning('No README.md found, skipping version update.');
  }

  // Git commit
  const filesToStage = [
    pluginManifestPath,
    '.claude-plugin/marketplace.json',
    changelogPath,
    ...(readmePath ? [readmePath] : []),
  ];
  execSync(`git add ${filesToStage.map((f) => `"${f}"`).join(' ')}`);
  const commitMessage = `release(${pluginName}): v${newVersion}`;
  // Skip pre-commit hook: release commits are machine-generated version bumps,
  // and the hook runs the full test suite which is redundant here.
  execSync(`git commit --no-verify -m "${commitMessage}"`);
  printSuccess(`Commit: ${commitMessage}`);

  // Summary
  console.log('');
  printSuccess(`Plugin:   ${pluginName}`);
  printSuccess(`Version:  ${currentVersion} → ${newVersion}`);
  console.log('');
  console.log('Next steps:');
  console.log('  1. Push branch and open a PR for review');
  console.log(`  2. After merge, run: npm run release:tag -- --plugin ${pluginName}`);
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
