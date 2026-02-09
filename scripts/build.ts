#!/usr/bin/env tsx
import { mkdir } from 'node:fs/promises';
import {
  validate,
  createPackage,
  ValidationError,
  type DetailedValidateResult,
} from 'ai-skills-manager';
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

    // Step 1: Validate using programmatic API (detailed mode)
    try {
      const validation: DetailedValidateResult = await validate(skill.path, { detailed: true });
      const checkEntries = Object.entries(validation.checks);
      const passed = checkEntries.filter(([, c]) => c.passed).length;
      const total = checkEntries.length;

      if (!validation.valid) {
        const failed = checkEntries.filter(([, c]) => !c.passed);
        for (const [name, check] of failed) {
          printError(`  ${name}: ${check.error}`);
        }
        result.error = `Validation failed: ${failed.length}/${total} checks failed`;
        results.push(result);
        continue;
      }

      result.validated = true;
      printSuccess(`  Validated (${passed}/${total} checks passed)`);

      if (validation.warnings && validation.warnings.length > 0) {
        for (const warning of validation.warnings) {
          printWarning(`  ${warning}`);
        }
      }
    } catch (err: unknown) {
      if (err instanceof ValidationError) {
        result.error = `Validation failed: ${err.message}`;
      } else {
        const error = err as { message?: string };
        result.error = `Validation failed: ${error.message}`;
      }
      printError('  Validation failed');
      results.push(result);
      continue;
    }

    // Step 2: Package using programmatic API
    try {
      const packageResult = await createPackage({
        path: skill.path,
        output: DIST_DIR,
        force: true,
      });
      result.packaged = true;
      printSuccess(`  Packaged to ${packageResult.packagePath}`);
    } catch (err: unknown) {
      const error = err as { message?: string };
      result.error = `Packaging failed: ${error.message}`;
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
