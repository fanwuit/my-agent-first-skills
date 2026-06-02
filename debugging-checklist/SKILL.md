---
name: debugging-checklist
description: Provide a concise debugging checklist for a junior developer or human handoff. Do not use as the primary agent debugging workflow when superpowers:systematic-debugging or another project-specific debugging workflow is available.
---

# Debugging Checklist

## Purpose
Provide a systematic debugging checklist for a human reader, junior developer, or handoff note. This is not the primary agent debugging workflow when a stronger workflow skill such as `superpowers:systematic-debugging` is available.

## Inputs to request
- Repro steps and frequency.
- Environment details and recent changes.
- Logs, stack traces, or screenshots.

## Workflow
1. Reproduce the issue and isolate the scope.
2. Check inputs, environment, and recent changes.
3. Add targeted logs or breakpoints.
4. Hand off clear next checks instead of executing a full agent debugging loop.

## Output
- Checklist ordered by likelihood.

## Quality bar
- Start with reversible, low-risk checks.
- Prefer minimal probes over broad logging.
