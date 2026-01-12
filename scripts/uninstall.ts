#!/usr/bin/env tsx
import { confirm } from '@inquirer/prompts';
import { uninstall as uninstallSkill, type ApiScope } from 'ai-skills-manager';
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

  // Uninstall using programmatic API
  try {
    const result = await uninstallSkill({
      names: selectedNames,
      scope: scope as ApiScope,
      force: true,
    });

    for (const name of result.removed) {
      printSuccess(`Uninstalled: ${name}`);
    }

    for (const name of result.notFound) {
      printWarning(`Not found: ${name}`);
    }

    // Summary
    console.log('');
    printInfo(
      `Uninstallation complete: ${result.removed.length} succeeded, ${result.notFound.length} not found`
    );

    if (result.notFound.length > 0 && result.removed.length === 0) {
      process.exit(1);
    }
  } catch (err: unknown) {
    const error = err as { message?: string };
    printError(`Failed to uninstall: ${error.message}`);
    process.exit(1);
  }
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
