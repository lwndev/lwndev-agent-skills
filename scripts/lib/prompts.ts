import { select, checkbox, confirm } from '@inquirer/prompts';
import chalk from 'chalk';
import type { Scope } from './constants.js';
import type { SkillInfo } from './skill-utils.js';

export async function promptForScope(): Promise<Scope> {
  return await select({
    message: 'Select installation scope:',
    choices: [
      { name: 'Project (.claude/skills/)', value: 'project' as Scope },
      { name: 'Personal (~/.claude/skills/)', value: 'personal' as Scope },
    ],
  });
}

export async function promptForSkillSelection(
  skills: SkillInfo[],
  message: string,
  allowAll = true
): Promise<string[]> {
  const choices = skills.map((skill) => ({
    name: `${skill.name} - ${truncate(skill.description, 60)}`,
    value: skill.name,
  }));

  if (allowAll) {
    const selectAll = await confirm({
      message: 'Select all skills?',
      default: false,
    });

    if (selectAll) {
      return skills.map((s) => s.name);
    }
  }

  return await checkbox({
    message,
    choices,
    required: true,
  });
}

export async function promptForSingleSkill(skills: SkillInfo[], message: string): Promise<string> {
  return await select({
    message,
    choices: skills.map((skill) => ({
      name: `${skill.name} - ${truncate(skill.description, 60)}`,
      value: skill.name,
    })),
  });
}

export function truncate(str: string, maxLength: number): string {
  if (str.length <= maxLength) return str;
  return str.slice(0, maxLength - 3) + '...';
}

export function printSuccess(message: string): void {
  console.log(chalk.green('\u2713'), message);
}

export function printError(message: string): void {
  console.log(chalk.red('\u2717'), message);
}

export function printInfo(message: string): void {
  console.log(chalk.blue('i'), message);
}

export function printWarning(message: string): void {
  console.log(chalk.yellow('!'), message);
}
