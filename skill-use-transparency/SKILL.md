---
name: skill-use-transparency
description: Use when a task may trigger one or more skills, when project rules require visible skill selection, when a user asks whether a skill was used, or when skill loading fails or may be ambiguous.
---

# Skill Use Transparency

## Overview

Make skill invocation visible and auditable. Skill use is part of the agent's reasoning contract, so the user must be able to see which workflow was selected, why, and whether its instructions were actually available.

## Required Disclosure

Before applying any skill, state:

- Which skill or skills were selected.
- Why each skill applies to the current request.
- Whether the trigger came from an explicit user request or agent inference.

After attempting to load each `SKILL.md`, state:

- Whether the file was read successfully.
- If reading failed, the reason and the fallback workflow.
- If content was unreadable, truncated, garbled, or only partly available, do not claim full workflow execution.

## Direct Questions

If the user asks whether a skill was triggered, answer directly:

- `Selected`: yes or no.
- `Trigger`: explicit user request, project rule, or agent inference.
- `Loaded`: whether `SKILL.md` was read successfully.
- `Executed`: full workflow, partial workflow, or fallback approximation.

Do not answer with a vague statement such as "I considered it." Say exactly what happened.

## Failure Handling

When loading fails:

1. Say which file or skill could not be loaded.
2. Give the concrete failure reason if available.
3. Continue with the best fallback using only confirmed instructions.
4. Avoid claiming compliance with unseen instructions.

For local files that may contain non-ASCII text, prefer an explicit UTF-8 read before declaring failure.

## Common Mistakes

| Mistake | Correct behavior |
|---|---|
| Silently following a skill workflow | Announce selection before applying it. |
| Saying a workflow was executed after a read error | Say it was not fully available and use fallback. |
| Treating metadata as the full skill | Load `SKILL.md` before claiming workflow details. |
| Answering "did you use skill X?" indirectly | Give selected, trigger, loaded, and executed status. |

## Final Check

Before the final response, check whether any skill was selected during the turn. If yes, make sure the conversation already contains the selection reason and loading result.
