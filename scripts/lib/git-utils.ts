import { execSync } from 'node:child_process';

export interface ParsedCommit {
  hash: string;
  type: string;
  scope: string | null;
  message: string;
  raw: string;
}

function exec(command: string): string {
  return execSync(command, { encoding: 'utf-8' }).trim();
}

export function isWorkingTreeClean(): boolean {
  const output = exec('git status --porcelain');
  return output.length === 0;
}

export function getCurrentBranch(): string {
  return exec('git rev-parse --abbrev-ref HEAD');
}

export function getTagsForPlugin(pluginName: string): string[] {
  try {
    const output = exec(`git tag -l "${pluginName}@*"`);
    if (!output) return [];
    return output.split('\n').filter(Boolean);
  } catch {
    return [];
  }
}

export function getLatestTagForPlugin(pluginName: string): string | null {
  const tags = getTagsForPlugin(pluginName);
  if (tags.length === 0) return null;

  // Sort by version using git's version sort
  try {
    const output = exec(`git tag -l "${pluginName}@*" --sort=-version:refname`);
    const sorted = output.split('\n').filter(Boolean);
    return sorted[0] ?? null;
  } catch {
    return tags[tags.length - 1] ?? null;
  }
}

function parseConventionalCommit(raw: string): {
  type: string;
  scope: string | null;
  message: string;
} {
  // Match: type(scope): message or type: message
  const match = raw.match(/^(\w+)(?:\(([^)]*)\))?:\s*(.+)$/);
  if (match) {
    return {
      type: match[1],
      scope: match[2] ?? null,
      message: match[3],
    };
  }
  return { type: 'other', scope: null, message: raw };
}

export function getCommitsSinceTag(tag: string | null): ParsedCommit[] {
  const range = tag ? `${tag}..HEAD` : 'HEAD';
  const format = '%H %s'; // hash + subject

  try {
    const output = exec(`git log ${range} --format="${format}"`);
    if (!output) return [];

    return output
      .split('\n')
      .filter(Boolean)
      .map((line) => {
        const spaceIndex = line.indexOf(' ');
        const hash = line.slice(0, spaceIndex);
        const subject = line.slice(spaceIndex + 1);
        const { type, scope, message } = parseConventionalCommit(subject);

        return { hash, type, scope, message, raw: subject };
      });
  } catch {
    return [];
  }
}

const NOISE_PATTERNS: RegExp[] = [
  /^Merge\s/i,
  /^address\s+(pr\s+)?review\s+feedback/i,
  /^mark\s+.+\s+as\s+completed/i,
  /^update\s+[A-Z]+-\d+\s+status/i,
];

export function filterNoiseCommits(commits: ParsedCommit[]): ParsedCommit[] {
  return commits.filter((commit) => !NOISE_PATTERNS.some((pattern) => pattern.test(commit.raw)));
}

export function tagExists(tagName: string): boolean {
  try {
    exec(`git rev-parse --verify "refs/tags/${tagName}"`);
    return true;
  } catch {
    return false;
  }
}
