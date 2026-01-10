#!/usr/bin/env tsx
import { input, confirm } from '@inquirer/prompts';
import { execSync } from 'node:child_process';
import { accessSync } from 'node:fs';
import { SKILLS_SOURCE_DIR } from './lib/constants.js';
import { printSuccess, printError, printInfo } from './lib/prompts.js';

async function main(): Promise<void> {
  printInfo('Create a new skill in src/skills/');

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

  // Prompt for allowed tools (optional)
  const wantAllowedTools = await confirm({
    message: 'Specify allowed tools? (optional)',
    default: false,
  });

  let allowedTools = '';
  if (wantAllowedTools) {
    allowedTools = await input({
      message: 'Allowed tools (comma-separated, e.g., Read,Write,Bash):',
    });
  }

  // Check if skill already exists
  const skillPath = `${SKILLS_SOURCE_DIR}/${name}`;
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

  // Build command
  const args = [
    'asm',
    'scaffold',
    name,
    '-d',
    JSON.stringify(description),
    '-o',
    SKILLS_SOURCE_DIR,
  ];

  if (allowedTools) {
    args.push('-t', allowedTools);
  }

  if (force) {
    args.push('-f');
  }

  const command = args.join(' ');

  printInfo(`Running: ${command}`);

  try {
    execSync(command, { stdio: 'inherit' });
    printSuccess(`Skill "${name}" created at ${skillPath}`);
  } catch {
    printError('Failed to create skill');
    process.exit(1);
  }
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
