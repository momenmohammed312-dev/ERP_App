---
name: plan-filter
description: Plan and Research phase for any stack. Use after SPEC OK to compare current best practices and lock files reuse risks pseudocode.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: filter-stage-2-plan
---

## What I do
- SDD Phase 2 Plan. No code until PLAN OK + explicit user approval.
- Force websearch: latest best practice for the task in current year, compare 2+ options with sources.
- Lock reuse to prevent duplication failure mode.

## When to use me
Use me as FILTER 2. Input must be SPEC OK. Output PLAN OK, then WAIT for user.

## Checklist
1. RESEARCH: websearch current year + official docs for your stack (web, mobile, backend, etc). Table: Option | Pros | Cons | Source.
2. Files: list new vs modified files. Flag breaking changes and migrations.
3. Reuse list mandatory: which existing functions, components, services, utils will be reused instead of duplicated?
4. Risks: data loss, auth, performance, backward compatibility, platform differences (iOS/Android, browsers).
5. Pseudocode or API contract 5-10 lines + rollback plan (feature branch, feature flag, revert steps).
6. End with: STOP - awaiting approval. Do not implement.

## Output format
```text
PLAN OK / PLAN REJECTED
Research: opt A vs opt B + sources
Files: ...
Reuse: ...
Risks: ...
Pseudocode: ...
AWAITING APPROVAL
```
