---
name: test-filter
description: Adversarial testing for any app. Use after style-filter to try to break logic with edge cases and regression.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: filter-stage-4
---

## What I do
- Generate edge cases for the feature: empty state, loading, error, offline, permission denied, large data, concurrent actions.
- Ask AI to break the code, not just confirm it.
- Require regression: old tests must stay green.

## When to use me
Use me as FILTER 4. Input must be STYLE OK. No merge without TEST OK.

## Checklist
1. Happy path covered with unit or integration test?
2. Edge cases: empty, null, timeout, network failure, invalid input, unauthorized?
3. Platform cases: mobile vs desktop, light vs dark, RTL if applicable?
4. Regression: existing test suite still passes?
5. Provide manual test steps: 1... 2... 3... with expected results.

## Output format
```text
TEST OK / TEST REJECTED
Cases: x/y pass
Break attempts: ...
Manual steps: 1... 2... 3...
```
