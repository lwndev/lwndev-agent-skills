import chalk from 'chalk';

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
