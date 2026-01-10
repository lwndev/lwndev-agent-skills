#!/usr/bin/env tsx
import { confirm } from '@inquirer/prompts';
import { execSync } from 'node:child_process';
import { getInstalledSkills } from './lib/skill-utils.js';
import {
  promptForScope,
  promptForSkillSelection,
  printSuccess,
  printError,
  printInfo,
  printWarning,
} from './lib/prompts.js';

async function main(): Promise<void> {
  printInfo('Uninstall skills from Claude Code');

  // Ask for scope first
  const scope = await promptForScope();

  // Get installed skills for that scope
  const installedSkills = await getInstalledSkills(scope);

  if (installedSkills.length === 0) {
    printWarning(`No skills installed in ${scope} scope.`);
    return;
  }

  printInfo(`Found ${installedSkills.length} installed skill(s) in ${scope} scope`);
  console.log('');

  // Prompt for skill selection
  const selectedNames = await promptForSkillSelection(
    installedSkills,
    'Select skills to uninstall:',
    true
  );

  if (selectedNames.length === 0) {
    printInfo('No skills selected.');
    return;
  }

  // Confirm
  console.log('');
  printWarning(`You are about to uninstall ${selectedNames.length} skill(s):`);
  for (const name of selectedNames) {
    console.log(`  - ${name}`);
  }
  console.log('');

  const proceed = await confirm({
    message: 'Are you sure you want to uninstall these skills?',
    default: false,
  });

  if (!proceed) {
    printInfo('Cancelled.');
    return;
  }

  // Uninstall each skill
  let successCount = 0;
  let failCount = 0;

  for (const name of selectedNames) {
    const command = `asm uninstall "${name}" --scope ${scope} --force`;

    try {
      execSync(command, { stdio: 'pipe' });
      printSuccess(`Uninstalled: ${name}`);
      successCount++;
    } catch (err: unknown) {
      const error = err as { stderr?: string; message?: string };
      printError(`Failed to uninstall ${name}: ${error.stderr || error.message}`);
      failCount++;
    }
  }

  // Summary
  console.log('');
  printInfo(`Uninstallation complete: ${successCount} succeeded, ${failCount} failed`);

  if (failCount > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
