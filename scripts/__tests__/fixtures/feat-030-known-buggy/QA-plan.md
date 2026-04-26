---
id: FEAT-030-FIXTURE
version: 2
persona: qa
---

# QA Plan: FEAT-030-FIXTURE

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios

### Inputs

- [P0] mode: test-framework — FR-1 classifyNumber returns the correct sign for positive and negative integers; expected: classifyNumber(5) === 'positive' and classifyNumber(-3) === 'negative'.

### State transitions

- [P2] mode: exploratory — N/A: classifyNumber is a pure function with no state.

### Environment

- [P2] mode: exploratory — N/A: pure function, no environment dependence.

### Dependency failure

- [P2] mode: exploratory — N/A: no external dependencies.

### Cross-cutting

- [P2] mode: exploratory — N/A: pure function, no cross-cutting concerns.
