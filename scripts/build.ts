#!/usr/bin/env tsx
import { execSync } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { getSourceSkills } from './lib/skill-utils.js';
import { DIST_DIR } from './lib/constants.js';
import { printSuccess, printError, printInfo, printWarning } from './lib/prompts.js';

interface BuildResult {
  name: string;
  validated: boolean;
  packaged: boolean;
  error?: string;
}

async function main(): Promise<void> {
  printInfo('Building all skills from src/skills/');

  // Ensure dist directory exists
  await mkdir(DIST_DIR, { recursive: true });

  const skills = await getSourceSkills();

  if (skills.length === 0) {
    printWarning('No skills found in src/skills/');
    return;
  }

  printInfo(`Found ${skills.length} skill(s)`);
  console.log('');

  const results: BuildResult[] = [];

  for (const skill of skills) {
    const result: BuildResult = {
      name: skill.name,
      validated: false,
      packaged: false,
    };

    console.log(`Building: ${skill.name}`);

    // Step 1: Validate
    try {
      execSync(`asm validate "${skill.path}" --quiet`, {
        stdio: 'pipe',
        encoding: 'utf-8',
      });
      result.validated = true;
      printSuccess('  Validated');
    } catch (err: unknown) {
      const error = err as { stderr?: string; message?: string };
      result.error = `Validation failed: ${error.stderr || error.message}`;
      printError('  Validation failed');
      results.push(result);
      continue;
    }

    // Step 2: Package
    try {
      execSync(`asm package "${skill.path}" -o "${DIST_DIR}" -f`, {
        stdio: 'pipe',
        encoding: 'utf-8',
      });
      result.packaged = true;
      printSuccess(`  Packaged to ${DIST_DIR}/${skill.name}.skill`);
    } catch (err: unknown) {
      const error = err as { stderr?: string; message?: string };
      result.error = `Packaging failed: ${error.stderr || error.message}`;
      printError('  Packaging failed');
    }

    results.push(result);
  }

  // Summary
  console.log('');
  console.log('-'.repeat(50));
  console.log('Build Summary:');

  const successful = results.filter((r) => r.validated && r.packaged);
  const failed = results.filter((r) => !r.validated || !r.packaged);

  printInfo(`Total: ${results.length}`);
  printSuccess(`Successful: ${successful.length}`);

  if (failed.length > 0) {
    printError(`Failed: ${failed.length}`);
    console.log('');
    for (const f of failed) {
      printError(`  ${f.name}: ${f.error}`);
    }
    process.exit(1);
  }
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
