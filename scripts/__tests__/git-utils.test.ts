import { filterNoiseCommits, type ParsedCommit } from '../lib/git-utils.js';

function commit(raw: string, overrides?: Partial<ParsedCommit>): ParsedCommit {
  return {
    hash: 'abc1234',
    type: 'chore',
    scope: null,
    message: raw,
    raw,
    ...overrides,
  };
}

describe('filterNoiseCommits', () => {
  it('should filter out merge commits', () => {
    const commits = [
      commit('Merge pull request #42 from user/branch', {
        type: 'other',
        raw: 'Merge pull request #42 from user/branch',
      }),
      commit('feat(ui): add button', { type: 'feat', scope: 'ui' }),
    ];
    const result = filterNoiseCommits(commits);
    expect(result).toHaveLength(1);
    expect(result[0].message).toBe('feat(ui): add button');
  });

  it('should filter out "address review feedback" commits', () => {
    const commits = [
      commit('address review feedback', { raw: 'address review feedback' }),
      commit('address PR review feedback', { raw: 'address PR review feedback' }),
      commit('fix(core): real fix', { type: 'fix', scope: 'core' }),
    ];
    const result = filterNoiseCommits(commits);
    expect(result).toHaveLength(1);
    expect(result[0].message).toBe('fix(core): real fix');
  });

  it('should filter out "mark * as completed" commits', () => {
    const commits = [
      commit('mark CHORE-015 as completed', { raw: 'mark CHORE-015 as completed' }),
      commit('feat: new feature', { type: 'feat' }),
    ];
    const result = filterNoiseCommits(commits);
    expect(result).toHaveLength(1);
    expect(result[0].type).toBe('feat');
  });

  it('should filter out "update * status" commits', () => {
    const commits = [
      commit('update CHORE-012 status to completed', {
        raw: 'update CHORE-012 status to completed',
      }),
      commit('docs: update readme', { type: 'docs' }),
    ];
    const result = filterNoiseCommits(commits);
    expect(result).toHaveLength(1);
    expect(result[0].type).toBe('docs');
  });

  it('should keep all commits when none are noise', () => {
    const commits = [
      commit('feat(ui): add button', { type: 'feat', scope: 'ui' }),
      commit('fix(core): fix crash', { type: 'fix', scope: 'core' }),
      commit('docs: update readme', { type: 'docs' }),
    ];
    const result = filterNoiseCommits(commits);
    expect(result).toHaveLength(3);
  });

  it('should return empty array when all commits are noise', () => {
    const commits = [
      commit('Merge branch main into feature', { raw: 'Merge branch main into feature' }),
      commit('address review feedback', { raw: 'address review feedback' }),
      commit('mark FEAT-001 as completed', { raw: 'mark FEAT-001 as completed' }),
    ];
    const result = filterNoiseCommits(commits);
    expect(result).toHaveLength(0);
  });

  it('should return empty array for empty input', () => {
    expect(filterNoiseCommits([])).toHaveLength(0);
  });

  it('should be case-insensitive for noise patterns', () => {
    const commits = [
      commit('MERGE pull request #1', { raw: 'MERGE pull request #1' }),
      commit('Address Review Feedback', { raw: 'Address Review Feedback' }),
    ];
    const result = filterNoiseCommits(commits);
    expect(result).toHaveLength(0);
  });
});
