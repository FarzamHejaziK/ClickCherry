---
description: Map of the internal documentation layout and the canonical files to use first.
---

# Internal Docs Map

## Read This First

- Do not bulk-read `/.docs`.
- Start here when you need to discover where information lives.
- Then open only the specific files relevant to the current task.

## Folder Map

- `/.docs/core/`
  - Source-of-truth product, design, planning, execution-queue, and testing docs.
- `/.docs/tracking/`
  - Active logs and trackers such as worklog, open issues, revisits, and UI/UX tracking.
- `/.docs/governance/`
  - Internal governance and open-source strategy docs.
- `/.docs/research/`
  - Research, investigations, implementation-shaping findings, and platform runbooks.
- `/.docs/archive/`
  - Historical material and snapshots. Do not read or edit by default.

## Canonical Files

- Product requirements: `/.docs/core/PRD.md`
- Locked design decisions: `/.docs/core/design.md`
- Implementation sequencing: `/.docs/core/plan.md`
- Current execution queue: `/.docs/core/next_steps.md`
- Testing source of truth: `/.docs/core/testing.md`
- Current worklog: `/.docs/tracking/worklog.md`
- Open issues: `/.docs/tracking/open_issues.md`
- Deferred decisions: `/.docs/tracking/revisits.md`
- UI/UX tracking: `/.docs/tracking/ui_ux_changes.md`
- Open-source strategy: `/.docs/governance/open_source.md`
- Automation strategy: `/.docs/research/automation/automation_strategy.md`
- Automation research: `/.docs/research/automation/automation_research.md`

## Maintenance Rules

- Prefer updating an existing canonical doc over creating a new overlapping doc.
- Use repo-relative paths inside docs whenever possible.
- New internal docs should be placed under one of the existing folders above.
- Avoid creating new top-level `/.docs/*.md` files unless there is a strong reason.
- Keep public contributor-facing guidance in `/docs/`; keep internal planning and execution material in `/.docs/`.
