---
name: test-fixture-agent
description: Minimal agent definition kept for test-skill.test.ts fixture coverage.
model: haiku
tools: []
---

# Test Fixture Agent

This agent exists solely so `test-skill.test.ts` can exercise the agent-copy
path in `test-skill.ts` without depending on a production agent. It carries no
behavioral logic.
