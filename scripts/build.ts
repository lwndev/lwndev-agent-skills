#!/usr/bin/env tsx
import { validate, ValidationError, type DetailedValidateResult } from 'ai-skills-manager';
import { getSourcePlugins, getSourceSkills } from './lib/skill-utils.js';
import { getPluginDir } from './lib/constants.js';
import { printSuccess, printError, printInfo, printWarning } from './lib/prompts.js';

interface ValidateResult {
  name: string;
  valid: boolean;
  error?: string;
}

async function validatePlugin(pluginName: string): Promise<boolean> {
  const pluginDir = getPluginDir(pluginName);

  printInfo(`Validating plugin "${pluginName}" at ${pluginDir}/`);

  const skills = await getSourceSkills(pluginName);

  if (skills.length === 0) {
    printError(`No skills found for plugin "${pluginName}"`);
    return false;
  }

  printInfo(`Found ${skills.length} skill(s)`);
  console.log('');

  const results: ValidateResult[] = [];

  for (const skill of skills) {
    const result: ValidateResult = {
      name: skill.name,
      valid: false,
    };

    console.log(`Validating: ${skill.name}`);

    try {
      const validation: DetailedValidateResult = await validate(skill.path, { detailed: true });
      const checkEntries = Object.entries(validation.checks);
      const total = checkEntries.length;
      const failed = checkEntries.filter(([, c]) => !c.passed);
      const passed = total - failed.length;

      if (!validation.valid) {
        for (const [name, check] of failed) {
          printError(`  ${name}: ${check.error}`);
        }
        result.error = `Validation failed: ${failed.length}/${total} checks failed`;
        results.push(result);
        continue;
      }

      result.valid = true;
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
    }

    results.push(result);
  }

  // Summary
  console.log('');
  console.log('-'.repeat(50));
  console.log(`Validation Summary (${pluginName}):`);

  const successful = results.filter((r) => r.valid);
  const failed = results.filter((r) => !r.valid);

  printInfo(`Total: ${results.length}`);
  printSuccess(`Passed: ${successful.length}`);

  if (failed.length > 0) {
    printError(`Failed: ${failed.length}`);
    console.log('');
    for (const f of failed) {
      printError(`  ${f.name}: ${f.error}`);
    }
    return false;
  }

  console.log('');
  printSuccess(`Plugin "${pluginName}" validated successfully`);
  return true;
}

async function main(): Promise<void> {
  const plugins = await getSourcePlugins();

  if (plugins.length === 0) {
    printWarning('No plugins found in plugins/');
    return;
  }

  printInfo(`Found ${plugins.length} plugin(s): ${plugins.join(', ')}`);
  console.log('');

  let allSucceeded = true;

  for (const pluginName of plugins) {
    const success = await validatePlugin(pluginName);
    if (!success) {
      allSucceeded = false;
    }
    console.log('');
  }

  if (!allSucceeded) {
    printError('One or more plugins failed validation');
    process.exit(1);
  }
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
