---
name: spec-filter
description: Specify phase with EARS syntax for any software. Use first for any feature to force unambiguous When While If Where shall requirements.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: filter-stage-1-specify
---

## What I do
- Turn vague ideas into EARS requirements. The spec is the source, code is just build output.
- Reject ambiguity, vagueness, incompleteness. Ask, don't guess.
- Output SPEC OK only when every requirement is EARS-formatted and testable.

## When to use me
Use me as FILTER 1 / SDD Phase 1 Specify. STOP workflow if SPEC REJECTED.

## EARS - 5 types only
- Ubiquitous: The [system] shall [response]
- Event-driven: When [event], the [system] shall [response]
- State-driven: While [state], the [system] shall [response]
- Unwanted: If [bad event], then the [system] shall [response]
- Optional: Where [feature present], the [system] shall [response]

## Checklist
1. Rewrite every wish into EARS. No vague words like good/fast/nice allowed.
2. Generic examples (replace with your domain):
   - When user submits the form, the system shall show a loading spinner.
   - While upload is in progress, the system shall disable the submit button.
   - If the API times out, then the system shall show a retry option.
   - Where dark mode is enabled, the system shall use dark colors.
   - The system shall validate email format on every submit.
3. Non-goals explicit (what this feature will NOT do).
4. If any requirement can't be phrased in EARS -> ask user, SPEC REJECTED.

## Output format
```text
SPEC OK / SPEC REJECTED
EARS:
- When ..., the system shall ...
- If ..., then the system shall ...
Non-goals: ...
Accept: [ ] ... [ ] ...
```
