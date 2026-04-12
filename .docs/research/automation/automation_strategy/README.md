---
description: Canonical entry point for ClickCherry's automation strategy doc set.
---

# Automation Strategy

## Purpose

This folder is the canonical strategy doc set for ClickCherry automation direction.

It replaces the old single-file `automation_strategy.md` layout with smaller, focused files so strategy, architecture, implementation sequencing, and browser-extension planning are easier to maintain.

## Read Order

1. `overview.md`
2. `architecture.md`
3. `implementation_plan.md`
4. `browser_extension_v1.md`

## File Map

- `overview.md`
  - purpose, scope, goal, and locked decisions
- `architecture.md`
  - system layers, routing policy, and tooling direction
- `implementation_plan.md`
  - phased rollout, testing strategy, immediate next steps, and open questions
- `browser_extension_v1.md`
  - real-session browser path, V1 scope, risk posture, UX plan, and follow-up path

## Maintenance Rule

- Treat this folder as the canonical automation-strategy source of truth.
- Keep `../automation_strategy.md` as a lightweight redirect file for compatibility only.
