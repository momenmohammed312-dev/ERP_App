---
name: review-filter
description: Final maintainability gate before merge for any project. Use last to check reuse churn docs and rollback.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: filter-stage-5
---

## What I do
- Final review sandwich: AI review first, human decision last.
- Check maintainability: reuse up, duplication down, small diffs.
- Require docs update + PR summary + rollback plan.

## When to use me
Use me as FILTER 5 final gate. Only REVIEW OK can merge to main.

## Checklist
1. Reuse: does new code call existing helpers/components or copy them?
2. Churn risk: will this break existing flows or cause follow-up fixes?
3. Docs: README or docs updated? API contract documented?
4. Git: feature branch? Human reviewed diff? Rollback clear (revert or flag off)?
5. Verdict with reasons, not just LGTM.

## Output format
```text
REVIEW OK / REVIEW REJECTED
Maintainability: ...
Docs: ...
Risk: ...
Merge: yes/no + why
```
