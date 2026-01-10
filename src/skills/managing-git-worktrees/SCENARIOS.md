# Common Worktree Scenarios

## Table of Contents
- [Scenario 1: Parallel Feature Development](#scenario-1-parallel-feature-development)
- [Scenario 2: Pull Request Review](#scenario-2-pull-request-review)
- [Scenario 3: Multiple Claude Code Sessions](#scenario-3-multiple-claude-code-sessions)
- [Scenario 4: Experimental Comparison](#scenario-4-experimental-comparison)
- [Scenario 5: Emergency Hotfix](#scenario-5-emergency-hotfix)
- [Scenario 6: Long-Running Feature with Bug Fixes](#scenario-6-long-running-feature-with-bug-fixes)

## Scenario 1: Parallel Feature Development

### User Request
"I need to work on feature X while also fixing bug Y"

### Context
User wants to work on two unrelated tasks simultaneously without context switching.

### Workflow

**Step 1: Assess**
```bash
git worktree list
git status
```

**Step 2: Propose**
```
Current: ~/Projects/pullapod/pullapod-cli (branch: main)

Proposed worktrees:
1. ../pullapod-feature-x
   Branch: feature/apple-search
   Purpose: Implement Apple Podcast search

2. ../pullapod-bugfix-y
   Branch: fix/metadata-parsing
   Purpose: Fix metadata parsing bug

Commands:
git worktree add -b feature/apple-search ../pullapod-feature-x
git worktree add -b fix/metadata-parsing ../pullapod-bugfix-y

Proceed? (y/N)
```

**Step 3: Execute**
```bash
# Create worktrees
git worktree add -b feature/apple-search ../pullapod-feature-x
git worktree add -b fix/metadata-parsing ../pullapod-bugfix-y

# Setup each worktree
cd ../pullapod-feature-x && npm install && npm test
cd ../pullapod-bugfix-y && npm install && npm test
```

**Step 4: Work Guidance**
```
Worktree 1 (Feature X):
  Path: ../pullapod-feature-x
  Branch: feature/apple-search
  Focus: src/clients/apple.ts, src/commands/search.ts

Worktree 2 (Bug Fix Y):
  Path: ../pullapod-bugfix-y
  Branch: fix/metadata-parsing
  Focus: src/utils/metadata.ts, tests/unit/metadata.test.ts
```

**Step 5: Merge Order Recommendation**
```
Suggested merge order:
1. Bug fix (simpler, less risk)
2. Feature (may benefit from bug fix)

Merge process:
# After bug fix is complete
cd ~/Projects/pullapod/pullapod-cli
git checkout main
git merge fix/metadata-parsing
git push
git worktree remove ../pullapod-bugfix-y
git branch -d fix/metadata-parsing

# After feature is complete
git merge feature/apple-search
git push
git worktree remove ../pullapod-feature-x
git branch -d feature/apple-search
```

## Scenario 2: Pull Request Review

### User Request
"Review PR #123 without disrupting my current work"

### Context
User is actively working on a feature but needs to review a colleague's PR.

### Workflow

**Step 1: Assess Current Work**
```bash
git status  # Check for uncommitted changes
git worktree list  # Check existing worktrees
```

**Step 2: Fetch PR**
```bash
# Fetch PR to local branch
git fetch origin pull/123/head:pr-123
```

**Step 3: Create Review Worktree**
```bash
git worktree add ../pullapod-pr-123 pr-123
```

**Step 4: Setup Review Environment**
```bash
cd ../pullapod-pr-123
npm install
npm test
npm run build
```

**Step 5: Review Guidance**
```
PR Review Checklist:
- [ ] Code runs without errors
- [ ] Tests pass
- [ ] No linting errors
- [ ] Matches PR description
- [ ] No security issues
- [ ] Documentation updated

Commands for review:
npm run lint              # Check code style
npm test                  # Run tests
git log main..pr-123      # View commits
git diff main...pr-123    # View changes

After review:
cd ~/Projects/pullapod/pullapod-cli
git worktree remove ../pullapod-pr-123
git branch -d pr-123
```

**Step 6: Post-Review**
```
Your main work remains untouched at:
~/Projects/pullapod/pullapod-cli

Continue where you left off with no context switching required.
```

## Scenario 3: Multiple Claude Code Sessions

### User Request
"Set up for parallel AI development on two features"

### Context
User wants to run multiple Claude Code sessions to work on different features simultaneously.

### Workflow

**Step 1: Define Task Boundaries**

Ask user to clarify:
- What are the two distinct tasks?
- Which files will each task modify?
- Any shared dependencies?

**Step 2: Propose Separated Worktrees**
```
Current: ~/Projects/pullapod/pullapod-cli (branch: main)

Proposed parallel development:

Session 1: Apple Podcast Search
  Worktree: ../pullapod-task-search
  Branch: feature/apple-search
  Scope:
    - src/clients/apple.ts (new)
    - src/commands/search.ts (modify)
    - tests/integration/apple.test.ts (new)
  DO NOT modify:
    - src/index.ts
    - src/downloader.ts
    - src/commands/download.ts

Session 2: Download Progress UI
  Worktree: ../pullapod-task-progress
  Branch: feature/progress-ui
  Scope:
    - src/downloader.ts (modify)
    - src/ui/progress.ts (new)
    - tests/unit/progress.test.ts (new)
  DO NOT modify:
    - src/clients/*
    - src/commands/search.ts

Proceed? (y/N)
```

**Step 3: Create Worktrees**
```bash
git worktree add -b feature/apple-search ../pullapod-task-search
git worktree add -b feature/progress-ui ../pullapod-task-progress

cd ../pullapod-task-search && npm install
cd ../pullapod-task-progress && npm install
```

**Step 4: Provide Session Prompts**
```
Claude Code Session 1 Prompt:
---
Working directory: ~/Projects/pullapod/pullapod-task-search
Task: Implement Apple Podcast search client
Files in scope: src/clients/apple.ts, src/commands/search.ts
DO NOT modify: src/index.ts, src/downloader.ts, src/commands/download.ts
Branch: feature/apple-search
---

Claude Code Session 2 Prompt:
---
Working directory: ~/Projects/pullapod/pullapod-task-progress
Task: Refactor download progress display with new UI
Files in scope: src/downloader.ts, src/ui/progress.ts
DO NOT modify: src/clients/*, src/commands/search.ts
Branch: feature/progress-ui
---
```

**Step 5: Merge Strategy**
```
After both sessions complete:

1. Merge simpler task first (likely progress UI)
2. Test in main worktree
3. Merge second task
4. Run full integration tests
5. Clean up worktrees

This minimizes merge conflicts by establishing changes sequentially.
```

## Scenario 4: Experimental Comparison

### User Request
"Compare two different approaches to implementing feature X"

### Context
User wants to try multiple implementation strategies and compare results.

### Workflow

**Step 1: Propose Experiment Structure**
```
Current: ~/Projects/pullapod/pullapod-cli (branch: main)

Experimental comparison for: Search optimization

Approach A: In-memory caching
  Worktree: ../pullapod-experiment-cache
  Branch: experiment/search-cache
  Strategy: Implement LRU cache for search results

Approach B: Database indexing
  Worktree: ../pullapod-experiment-db
  Branch: experiment/search-db
  Strategy: Use SQLite for indexed search

Both will modify: src/commands/search.ts, src/clients/

Proceed? (y/N)
```

**Step 2: Create Experiment Worktrees**
```bash
git worktree add -b experiment/search-cache ../pullapod-experiment-cache
git worktree add -b experiment/search-db ../pullapod-experiment-db

cd ../pullapod-experiment-cache && npm install
cd ../pullapod-experiment-db && npm install
```

**Step 3: Implement in Parallel**
```
Work on each approach independently in separate worktrees.
```

**Step 4: Comparison Framework**
```bash
# Create benchmark script
cat > benchmark-search.sh << 'EOF'
#!/bin/bash
echo "Benchmarking search performance..."

# Test approach A
cd ../pullapod-experiment-cache
echo "Testing cache approach:"
time npm run search-benchmark

# Test approach B
cd ../pullapod-experiment-db
echo "Testing database approach:"
time npm run search-benchmark
EOF

chmod +x benchmark-search.sh
./benchmark-search.sh
```

**Step 5: Decision and Cleanup**
```
After benchmarking:

Winning approach: experiment/search-cache (2x faster)

Merge process:
cd ~/Projects/pullapod/pullapod-cli
git checkout main
git merge experiment/search-cache
git push

Cleanup:
git worktree remove ../pullapod-experiment-cache
git worktree remove ../pullapod-experiment-db
git branch -d experiment/search-cache
git branch -d experiment/search-db
```

## Scenario 5: Emergency Hotfix

### User Request
"Critical bug in production - need to fix immediately while preserving feature work"

### Context
User is in the middle of feature development but needs to create an urgent hotfix.

### Workflow

**Step 1: Assess Current State**
```bash
git status  # Check uncommitted feature work
git worktree list
```

**Step 2: Propose Hotfix Worktree**
```
Current work: feature/large-feature (in progress, uncommitted changes)
Emergency: Production bug in metadata parser

Proposed hotfix workflow:
1. Keep current work untouched in main worktree
2. Create hotfix worktree from main branch
3. Fix bug, test, and merge
4. Return to feature work

Commands:
git worktree add -b hotfix/metadata-crash ../pullapod-hotfix main

Proceed? (y/N)
```

**Step 3: Create and Execute Hotfix**
```bash
# Create hotfix worktree from main (not current branch)
git worktree add -b hotfix/metadata-crash ../pullapod-hotfix main

# Setup
cd ../pullapod-hotfix
npm install

# Fix the bug
# ... make changes ...

# Test thoroughly
npm test
npm run lint
npm run build

# Commit
git add .
git commit -m "fix: resolve metadata parser crash on malformed input"

# Push for review or merge
git push -u origin hotfix/metadata-crash
```

**Step 4: Merge Hotfix**
```bash
# Switch to main worktree
cd ~/Projects/pullapod/pullapod-cli
git checkout main
git merge hotfix/metadata-crash
git push

# Clean up hotfix worktree
git worktree remove ../pullapod-hotfix
git branch -d hotfix/metadata-crash
```

**Step 5: Resume Feature Work**
```
Your feature work is exactly as you left it:
~/Projects/pullapod/pullapod-cli

All uncommitted changes preserved.
Continue development without any context switching overhead.
```

## Scenario 6: Long-Running Feature with Bug Fixes

### User Request
"Working on a large feature that will take weeks, but need to fix bugs in main branch"

### Context
User has a long-lived feature branch and needs to occasionally fix bugs in main without constantly rebasing.

### Workflow

**Step 1: Setup Dual Worktree Strategy**
```
Strategy: Maintain two persistent worktrees

Main worktree: ~/Projects/pullapod/pullapod-cli
  Branch: main
  Purpose: Bug fixes, reviews, hotfixes

Feature worktree: ../pullapod-feature-large
  Branch: feature/podcast-index-integration
  Purpose: Long-running feature development

Commands:
git worktree add -b feature/podcast-index-integration ../pullapod-feature-large

Setup:
cd ../pullapod-feature-large && npm install
```

**Step 2: Daily Workflow**
```
Feature development:
  Work in: ../pullapod-feature-large
  Commit regularly to feature branch

Bug fixes:
  Work in: ~/Projects/pullapod/pullapod-cli (main)
  Create fix branches as needed
  Merge to main when complete

Synchronization:
  Periodically merge main into feature branch to stay current
```

**Step 3: Bug Fix Process**
```bash
# Bug report comes in
cd ~/Projects/pullapod/pullapod-cli

# Create fix branch
git checkout -b fix/download-timeout main

# Fix, test, commit
# ... make changes ...
git add .
git commit -m "fix: increase download timeout for large files"

# Merge to main
git checkout main
git merge fix/download-timeout
git push

# Bring fix into feature branch
cd ../pullapod-feature-large
git merge main
```

**Step 4: Feature Completion**
```bash
# When feature is ready
cd ../pullapod-feature-large

# Final sync with main
git merge main

# Run full test suite
npm test
npm run lint
npm run build

# Merge feature to main
cd ~/Projects/pullapod/pullapod-cli
git checkout main
git merge feature/podcast-index-integration
git push

# Clean up feature worktree
git worktree remove ../pullapod-feature-large
git branch -d feature/podcast-index-integration
```

**Step 5: Benefits**
```
This dual-worktree strategy provides:
✓ No branch switching overhead
✓ Feature work always available
✓ Quick bug fixes without stashing
✓ Independent testing environments
✓ Clear separation of concerns
```

## General Patterns Across Scenarios

### Before Starting
1. Run `git worktree list` to see existing worktrees
2. Check `git status` for uncommitted changes
3. Verify disk space for new worktrees

### During Work
1. Keep clear scope boundaries between worktrees
2. Commit regularly in each worktree
3. Test in isolation before merging

### After Completion
1. Merge simpler changes first
2. Run full test suite after each merge
3. Remove worktrees immediately after merging
4. Delete merged branches
5. Run `git worktree prune` for cleanup

### Communication
When working in teams:
- Document active worktrees in shared notes
- Communicate which features are in which worktrees
- Avoid merging conflicting changes simultaneously
- Use PR workflow for all merges
