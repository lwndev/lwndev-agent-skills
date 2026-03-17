#!/usr/bin/env tsx
import { parseArgs } from 'node:util';
import { input, select, confirm } from '@inquirer/prompts';
import { accessSync } from 'node:fs';
import { join } from 'node:path';
import { scaffold as scaffoldSkill } from 'ai-skills-manager';
import type { ScaffoldTemplateOptions } from 'ai-skills-manager';
import { getPluginSkillsDir } from './lib/constants.js';
import { getSourcePlugins } from './lib/skill-utils.js';
import { printSuccess, printError, printInfo } from './lib/prompts.js';

type TemplateType = NonNullable<ScaffoldTemplateOptions['templateType']>;

function parsePluginFlag(): string | undefined {
  try {
    const { values } = parseArgs({
      options: { plugin: { type: 'string' } },
      strict: false,
    });
    return values.plugin as string | undefined;
  } catch {
    return undefined;
  }
}

async function main(): Promise<void> {
  // Discover available plugins
  const plugins = await getSourcePlugins();

  if (plugins.length === 0) {
    printError('No plugins found in plugins/');
    process.exit(1);
  }

  // Select plugin: --plugin flag > auto-select if only one > interactive prompt
  const pluginFlag = parsePluginFlag();
  let selectedPlugin: string;

  if (pluginFlag) {
    if (!plugins.includes(pluginFlag)) {
      printError(`Plugin "${pluginFlag}" not found. Available: ${plugins.join(', ')}`);
      process.exit(1);
    }
    selectedPlugin = pluginFlag;
    printInfo(`Using plugin: ${selectedPlugin}`);
  } else if (plugins.length === 1) {
    selectedPlugin = plugins[0];
    printInfo(`Using plugin: ${selectedPlugin}`);
  } else {
    selectedPlugin = await select<string>({
      message: 'Select plugin:',
      choices: plugins.map((p) => ({ name: p, value: p })),
    });
  }

  const skillsDir = getPluginSkillsDir(selectedPlugin);
  printInfo(`Create a new skill in ${skillsDir}/`);

  // Prompt for skill name
  const name = await input({
    message: 'Skill name (hyphen-case):',
    validate: (value) => {
      if (!value) return 'Name is required';
      if (!/^[a-z][a-z0-9-]*[a-z0-9]$/.test(value) && !/^[a-z]$/.test(value)) {
        return 'Name must be hyphen-case (lowercase letters, numbers, hyphens)';
      }
      if (value.length > 64) return 'Name must be 64 characters or less';
      return true;
    },
  });

  // Prompt for description
  const description = await input({
    message: 'Description:',
    validate: (value) => {
      if (!value) return 'Description is required';
      if (value.includes('<') || value.includes('>')) {
        return 'Description cannot contain angle brackets';
      }
      if (value.length > 1024) return 'Description must be 1024 characters or less';
      return true;
    },
  });

  // Prompt for template type
  const templateType = await select<TemplateType>({
    message: 'Template type:',
    choices: [
      { name: 'basic – General-purpose skill', value: 'basic' },
      { name: 'forked – Runs in isolated (fork) context', value: 'forked' },
      { name: 'with-hooks – Includes hook configuration examples', value: 'with-hooks' },
      { name: 'internal – Non-user-invocable helper skill', value: 'internal' },
      { name: 'agent – Autonomous agent with model/memory config', value: 'agent' },
    ],
    default: 'basic',
  });

  // Prompt for minimal toggle
  const minimal = await confirm({
    message: 'Minimal output? (concise SKILL.md without guidance comments)',
    default: false,
  });

  // Build template options, auto-setting fields based on template type
  const template: ScaffoldTemplateOptions = { templateType, minimal };

  if (templateType === 'forked') {
    template.context = 'fork';
  }

  if (templateType === 'agent') {
    template.agent = name;
  }

  // Prompt for memory scope (relevant for all template types)
  const wantMemory = await confirm({
    message: 'Configure memory scope?',
    default: false,
  });

  if (wantMemory) {
    template.memory = await select<NonNullable<ScaffoldTemplateOptions['memory']>>({
      message: 'Memory scope:',
      choices: [
        { name: 'project – Repo-specific, stored in .claude/', value: 'project' },
        { name: 'user – Cross-project, stored in ~/.claude/', value: 'user' },
        { name: 'local – Machine-specific, not committed', value: 'local' },
      ],
      default: 'project',
    });
  }

  // Prompt for model selection when agent template is chosen
  if (templateType === 'agent') {
    template.model = await select<string>({
      message: 'Agent model:',
      choices: [
        { name: 'sonnet (default)', value: 'sonnet' },
        { name: 'opus', value: 'opus' },
        { name: 'haiku', value: 'haiku' },
      ],
      default: 'sonnet',
    });
  }

  // Prompt for allowed tools (optional)
  const wantAllowedTools = await confirm({
    message: 'Specify allowed tools? (optional)',
    default: false,
  });

  let allowedTools: string[] = [];
  if (wantAllowedTools) {
    const toolsInput = await input({
      message: 'Allowed tools (comma-separated, e.g., Read,Write,Bash):',
    });
    if (toolsInput) {
      allowedTools = toolsInput.split(',').map((t) => t.trim());
    }
  }

  // Prompt for argument hint (optional)
  const wantArgumentHint = await confirm({
    message: 'Specify argument hint? (optional)',
    default: false,
  });

  if (wantArgumentHint) {
    const argumentHint = await input({
      message: 'Argument hint (e.g. "<query> [--deep]"):',
      validate: (value) => {
        if (!value) return 'Argument hint is required when enabled';
        if (value.length > 100) return 'Argument hint must be 100 characters or less';
        return true;
      },
    });
    template.argumentHint = argumentHint;
  }

  // Check if skill already exists
  const skillPath = join(skillsDir, name);
  let force = false;
  try {
    accessSync(skillPath);
    force = await confirm({
      message: `Skill "${name}" already exists. Overwrite?`,
      default: false,
    });
    if (!force) {
      printInfo('Cancelled.');
      process.exit(0);
    }
  } catch {
    // Skill doesn't exist, continue
  }

  // Create skill using programmatic API
  try {
    const result = await scaffoldSkill({
      name,
      description,
      output: skillsDir,
      allowedTools: allowedTools.length > 0 ? allowedTools : undefined,
      force,
      template,
    });
    printSuccess(`Skill "${name}" created at ${result.path}`);
    printInfo(`Files created: ${result.files.join(', ')}`);
  } catch (err: unknown) {
    const error = err as { message?: string };
    printError(`Failed to create skill: ${error.message}`);
    process.exit(1);
  }
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
