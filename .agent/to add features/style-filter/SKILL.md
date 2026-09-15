---
name: style-filter
description: Enforce project style and anti-duplication for any language. Use after code is written to reject copy-paste and convention violations.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: filter-stage-3
---

## What I do
- Enforce the project's actual conventions (naming, structure, error handling, state management).
- Block duplication: copy-paste and reinvented helpers are the main AI failure mode.
- Enforce SOLID, DRY, small functions, clear names.

## When to use me
Use me as FILTER 3 on every diff. FAIL means send back to implementation, not forward.

## Checklist
1. Conventions: does new code follow existing naming, folder structure, patterns? If project has linter/formatter, would it pass?
2. Reuse: if new function/component duplicates an existing one -> REJECT with pointer to existing file.
3. Safety: errors handled? No silent swallowing? No hardcoded secrets? Inputs validated?
4. Size: no giant files or functions doing 5 things. Split if needed.
5. No dead code, no stray console.logs, no TODO without issue.

## Output format
```text
STYLE OK / STYLE REJECTED
Conventions: pass/fail
Duplication: pass/fail + lines
Safety: pass/fail
Fix: ...
```
