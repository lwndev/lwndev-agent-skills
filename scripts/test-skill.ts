#!/usr/bin/env tsx
import { parseArgs } from 'node:util';
import { cp, rm, mkdir, access, readdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import {
  getPluginSkillsDir,
  getPluginAgentsDir,
  PROJECT_SKILLS_DIR,
  PROJECT_AGENTS_DIR,
} from './lib/constants.js';
import { getSourcePlugins } from './lib/skill-utils.js';
import { printSuccess, printError, printInfo, printWarning } from './lib/prompts.js';

interface ParsedArgs {
  name: string;
  plugin: string;
  agent: boolean;
  remove: boolean;
}

async function parseCliArgs(): Promise<ParsedArgs> {
  const { values, positionals } = parseArgs({
    options: {
      plugin: { type: 'string' },
      agent: { type: 'boolean', default: false },
      remove: { type: 'boolean', default: false },
      help: { type: 'boolean', short: 'h', default: false },
    },
    allowPositionals: true,
    strict: true,
  });

  if (values.help) {
    console.log(`Usage: tsx scripts/test-skill.ts <name> [--plugin <plugin>] [--agent] [--remove]

Copy a plugin skill or agent into project scope for local testing.

Arguments:
  <name>              Skill or agent name

Options:
  --plugin <plugin>   Plugin name (auto-detected if only one exists)
  --agent             Copy an agent instead of a skill
  --remove            Remove from project scope instead of copying
  -h, --help          Show this help

Examples:
  tsx scripts/test-skill.ts reviewing-requirements
  tsx scripts/test-skill.ts qa-verifier --agent
  tsx scripts/test-skill.ts reviewing-requirements --remove
  tsx scripts/test-skill.ts qa-verifier --agent --remove`);
    process.exit(0);
  }

  const name = positionals[0];
  if (!name) {
    printError('Missing skill/agent name');
    console.log('Usage: tsx scripts/test-skill.ts <name> [--plugin <plugin>] [--agent] [--remove]');
    process.exit(1);
  }

  // Auto-detect plugin
  let plugin = values.plugin;
  if (!plugin) {
    const plugins = await getSourcePlugins();
    if (plugins.length === 0) {
      printError('No plugins found in plugins/');
      process.exit(1);
    } else if (plugins.length === 1) {
      plugin = plugins[0];
    } else {
      printError(`Multiple plugins found. Use --plugin to specify: ${plugins.join(', ')}`);
      process.exit(1);
    }
  }

  return {
    name,
    plugin,
    agent: values.agent ?? false,
    remove: values.remove ?? false,
  };
}

function getSourcePath(args: ParsedArgs): string {
  if (args.agent) {
    return join(getPluginAgentsDir(args.plugin), `${args.name}.md`);
  }
  return join(getPluginSkillsDir(args.plugin), args.name);
}

function getDestPath(args: ParsedArgs): string {
  if (args.agent) {
    return join(PROJECT_AGENTS_DIR, `${args.name}.md`);
  }
  return join(PROJECT_SKILLS_DIR, args.name);
}

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function listAvailable(dir: string, isAgent: boolean): Promise<string[]> {
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    if (isAgent) {
      return entries
        .filter((e) => e.isFile() && e.name.endsWith('.md'))
        .map((e) => e.name.replace(/\.md$/, ''));
    }
    return entries.filter((e) => e.isDirectory() && !e.name.startsWith('.')).map((e) => e.name);
  } catch {
    return [];
  }
}

export async function testSkill(args: ParsedArgs): Promise<void> {
  const type = args.agent ? 'agent' : 'skill';
  const source = getSourcePath(args);
  const dest = getDestPath(args);

  if (args.remove) {
    if (!(await exists(dest))) {
      printInfo(`Nothing to remove: ${dest} does not exist`);
      return;
    }
    if (args.agent) {
      await rm(dest);
    } else {
      await rm(dest, { recursive: true });
    }
    printSuccess(`Removed ${type} '${args.name}' from project scope`);
    return;
  }

  // Validate source exists
  if (!(await exists(source))) {
    const sourceDir = args.agent
      ? getPluginAgentsDir(args.plugin)
      : getPluginSkillsDir(args.plugin);
    const available = await listAvailable(sourceDir, args.agent);
    const availableMsg =
      available.length > 0 ? `\n  Available ${type}s: ${available.join(', ')}` : '';
    throw new Error(`${type} '${args.name}' not found in plugin '${args.plugin}'${availableMsg}`);
  }

  if (await exists(dest)) {
    printWarning(`'${args.name}' already exists in project scope, overwriting`);
    if (args.agent) {
      await rm(dest);
    } else {
      await rm(dest, { recursive: true });
    }
  }

  // Copy
  await mkdir(dirname(dest), { recursive: true });
  if (args.agent) {
    await cp(source, dest);
  } else {
    await cp(source, dest, { recursive: true });
  }

  printSuccess(`Copied ${type} '${args.name}' from plugin '${args.plugin}' to project scope`);
  printInfo(`Source: ${source}`);
  printInfo(`Dest:   ${dest}`);
  console.log('');
  printInfo(`Invoke /${args.name} to test. When done:`);
  printInfo(`  tsx scripts/test-skill.ts ${args.name}${args.agent ? ' --agent' : ''} --remove`);
}

async function main(): Promise<void> {
  const args = await parseCliArgs();
  await testSkill(args);
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
