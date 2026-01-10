#!/usr/bin/env tsx
import { confirm } from '@inquirer/prompts';
import { execSync } from 'node:child_process';
import { getSourceSkills, packagedSkillExists, getPackagedSkillPath } from './lib/skill-utils.js';
import {
  promptForScope,
  promptForSkillSelection,
  printSuccess,
  printError,
  printInfo,
  printWarning,
} from './lib/prompts.js';

async function main(): Promise<void> {
  printInfo('Install skills from dist/ to Claude Code');

  // Get available skills from source
  const skills = await getSourceSkills();

  if (skills.length === 0) {
    printError('No skills found in src/skills/');
    process.exit(1);
  }

  // Check which skills have been packaged
  const availableSkills = [];
  const missingPackages = [];

  for (const skill of skills) {
    if (await packagedSkillExists(skill.name)) {
      availableSkills.push(skill);
    } else {
      missingPackages.push(skill.name);
    }
  }

  if (missingPackages.length > 0) {
    printWarning("The following skills have not been packaged (run 'npm run build' first):");
    for (const name of missingPackages) {
      console.log(`  - ${name}`);
    }
    console.log('');
  }

  if (availableSkills.length === 0) {
    printError('No packaged skills available. Run "npm run build" first.');
    process.exit(1);
  }

  // Prompt for skill selection
  const selectedNames = await promptForSkillSelection(availableSkills, 'Select skills to install:');

  if (selectedNames.length === 0) {
    printInfo('No skills selected.');
    return;
  }

  // Prompt for scope
  const scope = await promptForScope();

  // Confirm
  console.log('');
  printInfo(`Installing ${selectedNames.length} skill(s) to ${scope} scope:`);
  for (const name of selectedNames) {
    console.log(`  - ${name}`);
  }
  console.log('');

  const proceed = await confirm({
    message: 'Proceed with installation?',
    default: true,
  });

  if (!proceed) {
    printInfo('Cancelled.');
    return;
  }

  // Install each skill
  let successCount = 0;
  let failCount = 0;

  for (const name of selectedNames) {
    const packagePath = getPackagedSkillPath(name);
    const command = `asm install "${packagePath}" --scope ${scope} --force`;

    try {
      execSync(command, { stdio: 'pipe' });
      printSuccess(`Installed: ${name}`);
      successCount++;
    } catch (err: unknown) {
      const error = err as { stderr?: string; message?: string };
      printError(`Failed to install ${name}: ${error.stderr || error.message}`);
      failCount++;
    }
  }

  // Summary
  console.log('');
  printInfo(`Installation complete: ${successCount} succeeded, ${failCount} failed`);

  if (failCount > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
