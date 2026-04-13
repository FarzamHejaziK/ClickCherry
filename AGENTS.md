# Agent Instructions

- Reading docs: do not bulk-read `.docs/` by default. When doc discovery is needed, read `.docs/README.md` first, then open only the specific files needed for the current request. Avoid `.docs/archive/**` unless historical context is required.
- Testing strategy: at each incremental implementation step, verify with both automated code-based tests and manual tests before marking the step complete.
- Large file awareness: if a change is likely to generate or expand a large code file, pause and think through how to break it into smaller, maintainable, semantically organized units. Propose that breakdown before defaulting to a monolithic implementation.
- Code file size rule:
  - Prefer small, single-responsibility production code files over large, multi-purpose files.
  - Soft limit: when a production code file approaches `800` lines, pause and evaluate whether the work should be split into smaller units.
  - Hard limit: do not create a new production code file over `1000` lines, and do not expand an existing production code file beyond `1000` lines, unless the user explicitly approves an exception.
  - If a change would cross the soft or hard limit, break the implementation into semantically organized modules such as views, components, services, helpers, models, or feature-specific extensions.
  - Split by responsibility, cohesion, readability, and testability, not by arbitrary line counts alone.
  - Before proceeding with a large implementation, briefly propose the intended file breakdown and explain why that structure will be easier to maintain, review, and test.
  - Exclusions may include generated files, vendor files, or files the user explicitly wants kept as a single artifact.
- Follow the `.docs/` update contract below for file ownership and maintenance rules.
- Use `$clickcherry-doc-sync` for work that may affect internal docs, testing guidance, prompts, UI/UX tracking, open issues, automation strategy, or open-source governance. Let the skill prepare the proposed `.docs` approval list before editing any internal docs.
- Never push changes (run `git push`) unless the user explicitly requests it in the current thread.
- Prefer repo-relative paths inside docs and `AGENTS.md`; avoid machine-specific absolute paths unless a tool requires them.
- New internal docs should live under the existing `.docs/` folders. Do not create new top-level `.docs/*.md` files unless the user asks or there is a strong reason.

## Docs Update Approval Gate

- Before editing any `.docs/**/*` file, explicitly ask the user for approval.
- Provide a short proposed doc update list first (files + one-line reason per file).
- Apply `.docs` changes only after the user approves.
- Prioritize this approval gate for `.docs/core/next_steps.md` and `.docs/tracking/worklog.md`.
- If the user declines, skip `.docs` edits and continue code changes unless instructed otherwise.

## Open Source Strategy Rules

- Track all open-source strategy decisions, tradeoffs, and process updates in `.docs/governance/open_source.md`.
- Whenever a change affects open-source governance, contribution process, licensing, releases, or public documentation strategy:
  - update `.docs/governance/open_source.md` in the same task/PR.
  - keep `/docs/` aligned for contributor-facing guidance.
  - keep `.docs/core/next_steps.md` and `.docs/tracking/worklog.md` aligned with the open-source work status.

## Prompt Rules

- All LLM prompts must live under `TaskAgentMacOSApp/TaskAgentMacOSApp/Resources/Prompts/`.
- Each prompt must be in its own folder and include:
  - `prompt.md`
  - `config.yaml` with at least `version` and `llm`.
- Do not keep production prompt text inline in service code; load prompts via `PromptCatalogService`.

## UI/UX Change Rules

- Track all UI/UX plan and decision updates in `.docs/tracking/ui_ux_changes.md`.
- For each UI/UX change, record:
  - plan alignment (how it follows `.docs/core/plan.md`)
  - design-decision alignment (how it follows `.docs/core/design.md`)
  - implementation notes and validation status.
- Keep `.docs/tracking/ui_ux_changes.md` current in the same task/PR where UI/UX work is introduced.

## `.docs/` Layout

- `.docs/README.md`:
  - Update when the internal doc structure, ownership, or discovery guidance changes.
- `.docs/core/*`:
  - Source-of-truth docs for requirements, design, implementation sequencing, active next steps, and testing guidance.
- `.docs/tracking/*`:
  - Active trackers and logs. These are operational records, not product-spec replacements.
- `.docs/governance/*`:
  - Internal governance and open-source process docs.
- `.docs/research/**/*`:
  - Research, investigations, strategy notes, and runbooks. Prefer updating canonical merged docs over creating overlapping topic docs.
- `.docs/archive/**/*`:
  - Historical records and snapshots. Do not edit routinely; consult only when historical context is needed.

## `.docs/` Update Contract

- `.docs/core/PRD.md`:
  - Update when product requirements, scope, constraints, or locked addenda change.
  - Keep requirement statements explicit and testable.
- `.docs/core/design.md`:
  - Update when design decisions are introduced, revised, or locked.
  - Any new design choice must be recorded in this file in the same task/PR where it is introduced.
- `.docs/core/plan.md`:
  - Update when implementation phases, sequencing, or validation strategy changes.
  - Keep step definitions aligned with current execution reality.
- `.docs/core/next_steps.md`:
  - Keep this as the current execution queue.
  - After user approval, include immediate priorities, code tasks, automated tests, manual tests, and exit criteria.
- `.docs/tracking/worklog.md`:
  - After user approval, append an entry for each incremental implementation step and major docs/process change.
  - Include: what changed, automated tests run, manual tests run, result, blockers, notes.
  - Keep only the 10 most recent `## Entry` sections in this file.
  - Move older entries to `.docs/archive/legacy_worklog.md` using `scripts/rotate_worklog.sh`.
- `.docs/archive/legacy_worklog.md`:
  - Archive for older `worklog.md` entries.
  - Do not review by default; consult only when historical context is needed.
- `.docs/core/testing.md`:
  - Update when test commands, environment limitations, or source-of-truth testing guidance changes.
- `.docs/research/platform/xcode_signing_setup.md`:
  - Update when app identity, signing, entitlement, or permission-grant workflow changes.
- `.docs/tracking/open_issues.md`:
  - Update when a known unresolved issue is discovered, re-scoped, mitigated, or closed.
  - Keep entries actionable and current; do not leave stale "in progress" items without next steps.
- `.docs/tracking/ui_ux_changes.md`:
  - Update when UI/UX plans, decisions, or implementation direction changes.
  - Explicitly state how each entry aligns with `.docs/core/plan.md` and `.docs/core/design.md`.
- `.docs/research/automation/automation_strategy/README.md`:
  - Treat this as the canonical entry point for the automation strategy doc set.
  - Update the relevant file within `automation_strategy/` when semantic automation direction, browser automation architecture, MCP policy, phased implementation strategy, or the browser-extension V1 plan changes.
- `.docs/research/automation/automation_research.md`:
  - Update when automation findings, real-profile browser research, or implementation-shaping external research changes.
- `.docs/research/runtime/*`:
  - Update the relevant runtime investigation or transport-hardening doc when those findings or decisions change.
- `.docs/research/platform/permissions_incident_report.md`:
  - Update when permission-related incident understanding, mitigations, or operational guidance changes.
- `.docs/archive/backups/*.bak`:
  - Treat as snapshots.
  - Do not edit routinely; refresh only when intentionally creating a backup snapshot.

## Docs-Only Changes

- If a task is docs-only, first ask for user approval; after approval, update `.docs/tracking/worklog.md` and keep `.docs/core/next_steps.md` aligned with current priorities.
- In docs-only worklog entries, explicitly mark automated/manual tests as `N/A (docs-only)` unless a verification command is actually run.

## `open_issues.md` Entry Rules

- File location: `.docs/tracking/open_issues.md`.
- One issue per section; newest open issue first.
- Required fields per issue:
  - `Issue ID`
  - `Title`
  - `Status` (`Open`, `Mitigated`, `Blocked`, `Closed`)
  - `Severity` (`High`, `Medium`, `Low`)
  - `First Seen` (YYYY-MM-DD)
  - `Scope`
  - `Repro Steps`
  - `Observed`
  - `Expected`
  - `Current Mitigation`
  - `Next Action`
  - `Owner`
- Closing rule:
  - Keep closed issues in the file for history, but move them to a `Closed Issues` section with `Resolution Date` and short fix summary.
