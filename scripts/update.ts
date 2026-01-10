#!/usr/bin/env tsx
import { confirm } from '@inquirer/prompts';
import { execSync } from 'node:child_process';
import { getSourceSkills, packagedSkillExists, getPackagedSkillPath } from './lib/skill-utils.js';
import { promptForScope, promptForSingleSkill, printSuccess, printError, printInfo } from './lib/prompts.js';

async function main(): Promise<void> {
  printInfo('Update an installed skill from dist/');

  // Get available skills from source that have been packaged
  const skills = await getSourceSkills();
  const availableSkills = [];

  for (const skill of skills) {
    if (await packagedSkillExists(skill.name)) {
      availableSkills.push(skill);
    }
  }

  if (availableSkills.length === 0) {
    printError('No packaged skills available. Run "npm run build" first.');
    process.exit(1);
  }

  // Prompt for skill selection
  const selectedName = await promptForSingleSkill(availableSkills, 'Select skill to update:');

  // Prompt for scope
  const scope = await promptForScope();

  // Confirm
  const packagePath = getPackagedSkillPath(selectedName);

  console.log('');
  printInfo(`Updating skill "${selectedName}" in ${scope} scope`);
  printInfo(`Package: ${packagePath}`);
  console.log('');

  const proceed = await confirm({
    message: 'Proceed with update?',
    default: true,
  });

  if (!proceed) {
    printInfo('Cancelled.');
    return;
  }

  // Execute update
  const command = `npx asm update "${selectedName}" "${packagePath}" --scope ${scope} --force`;

  try {
    execSync(command, { stdio: 'inherit' });
    printSuccess(`Successfully updated: ${selectedName}`);
  } catch {
    printError(`Failed to update ${selectedName}`);
    process.exit(1);
  }
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
