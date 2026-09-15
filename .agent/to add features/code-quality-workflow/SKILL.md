---
name: code-quality-workflow
description: SDD orchestrator Specify Plan Tasks Implement for any software. Use when user says new feature workflow or filter stages.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: orchestrator-sdd
---

## What I do
- Run SDD 4 phases with human checkpoint after each. Stop on first REJECTED. No skipping.
- Chain: spec-filter (Specify) -> plan-filter (Plan) -> Tasks breakdown -> Implement (style-filter -> test-filter -> review-filter).
- I am the only entry point. Works for web, mobile, backend, desktop, any stack.

## When to use me
Use me for any new feature, fix, or change in any repo. Always start here.

## Workflow - SDD 4 phases
1. SPECIFY: Load `spec-filter`. Rewrite all to EARS. If SPEC REJECTED -> ask, STOP. Checkpoint: user approves SPEC.
2. RESEARCH+PLAN: Load `plan-filter`. Websearch current year + compare 2 options. Output PLAN OK. Checkpoint: user approves PLAN explicitly. Zero code before this.
3. TASKS: Break approved plan into small tasks. Each task = change + linked test + diff (no full rewrite for big files) + regression check. Checkpoint: user approves task list.
4. IMPLEMENT one task at a time on new git branch or feature flag:
   a. Load `style-filter`. If REJECTED -> refactor, re-run.
   b. Load `test-filter`. If REJECTED -> fix, re-run.
   c. Old tests must stay green.
5. FINAL: Load `review-filter`. If REVIEW OK -> merge summary + manual test steps + rollback + docs update.
6. Never merge without SPEC OK + PLAN OK + TASKS OK + STYLE OK + TEST OK + REVIEW OK.

## Rules
- Spec is source, code is build output. Intent drift / context decay / unverifiable output -> reject.
- One filter at a time, verdict explicit.
- Permanent project constraints live in AGENTS.md, do not repeat them per prompt.
