#!/usr/bin/env tsx
import { cp, rm, mkdir, copyFile } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, ValidationError, type DetailedValidateResult } from 'ai-skills-manager';
import { getSourcePlugins, getSourceSkills } from './lib/skill-utils.js';
import {
  getPluginSourceDir,
  getPluginOutputDir,
  getPluginSkillsOutputDir,
  getPluginManifestOutputDir,
} from './lib/constants.js';
import { printSuccess, printError, printInfo, printWarning } from './lib/prompts.js';

interface BuildResult {
  name: string;
  validated: boolean;
  copied: boolean;
  error?: string;
}

async function buildPlugin(pluginName: string): Promise<boolean> {
  const pluginSourceDir = getPluginSourceDir(pluginName);
  const pluginOutputDir = getPluginOutputDir(pluginName);
  const pluginSkillsDir = getPluginSkillsOutputDir(pluginName);
  const pluginManifestDir = getPluginManifestOutputDir(pluginName);

  printInfo(`Building plugin "${pluginName}" from ${pluginSourceDir}/`);

  // Clean and create plugin output directories
  await rm(pluginOutputDir, { recursive: true, force: true });
  await mkdir(pluginManifestDir, { recursive: true });
  await mkdir(pluginSkillsDir, { recursive: true });

  const skills = await getSourceSkills(pluginName);

  if (skills.length === 0) {
    printWarning(`No skills found for plugin "${pluginName}"`);
    return true;
  }

  printInfo(`Found ${skills.length} skill(s)`);
  console.log('');

  const results: BuildResult[] = [];

  for (const skill of skills) {
    const result: BuildResult = {
      name: skill.name,
      validated: false,
      copied: false,
    };

    console.log(`Building: ${skill.name}`);

    // Step 1: Validate using programmatic API (detailed mode)
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

    // Step 2: Copy skill directory to plugin output
    try {
      const destPath = join(pluginSkillsDir, skill.name);
      await cp(skill.path, destPath, { recursive: true });
      result.copied = true;
      printSuccess(`  Copied to ${destPath}`);
    } catch (err: unknown) {
      const error = err as { message?: string };
      result.error = `Copy failed: ${error.message}`;
      printError('  Copy failed');
    }

    results.push(result);
  }

  // Summary
  console.log('');
  console.log('-'.repeat(50));
  console.log(`Build Summary (${pluginName}):`);

  const successful = results.filter((r) => r.validated && r.copied);
  const failed = results.filter((r) => !r.validated || !r.copied);

  printInfo(`Total: ${results.length}`);
  printSuccess(`Successful: ${successful.length}`);

  if (failed.length > 0) {
    printError(`Failed: ${failed.length}`);
    console.log('');
    for (const f of failed) {
      printError(`  ${f.name}: ${f.error}`);
    }
    // Clean up partial plugin output on failure
    await rm(pluginOutputDir, { recursive: true, force: true });
    return false;
  }

  // Copy plugin manifest and README only on full success
  await copyFile(join(pluginSourceDir, 'plugin.json'), join(pluginManifestDir, 'plugin.json'));
  printSuccess('Copied plugin.json');

  await copyFile(join(pluginSourceDir, 'README.md'), join(pluginOutputDir, 'README.md'));
  printSuccess('Copied README.md');

  console.log('');
  printSuccess(`Plugin built at ${pluginOutputDir}`);
  return true;
}

async function main(): Promise<void> {
  const plugins = await getSourcePlugins();

  if (plugins.length === 0) {
    printWarning('No plugins found in src/plugins/');
    return;
  }

  printInfo(`Found ${plugins.length} plugin(s): ${plugins.join(', ')}`);
  console.log('');

  let allSucceeded = true;

  for (const pluginName of plugins) {
    const success = await buildPlugin(pluginName);
    if (!success) {
      allSucceeded = false;
    }
    console.log('');
  }

  if (!allSucceeded) {
    printError('One or more plugins failed to build');
    process.exit(1);
  }
}

main().catch((err) => {
  printError(err.message);
  process.exit(1);
});
