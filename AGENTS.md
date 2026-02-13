# Agent Instructions

- At the beginning of any task, read all the docs in `.docs/` first, except `.docs/legacy_worklog.md` unless historical context is required.
- Testing strategy: at each incremental implementation step, verify with both automated code-based tests and manual tests before marking the step complete.
- Follow the `.docs/` update contract below for file ownership and maintenance rules.
- Never push changes (run `git push`) unless the user explicitly requests it in the current thread.

## Prompt Rules

- All LLM prompts must live under `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Prompts/`.
- Each prompt must be in its own folder and include:
  - `prompt.md`
  - `config.yaml` with at least `version` and `llm`.
- Do not keep production prompt text inline in service code; load prompts via `PromptCatalogService`.

## UI/UX Change Rules

- Track all UI/UX plan and decision updates in `/Users/farzamh/code-git-local/task-agent-macos/.docs/ui_ux_changes.md`.
- For each UI/UX change, record:
  - plan alignment (how it follows `/Users/farzamh/code-git-local/task-agent-macos/.docs/plan.md`)
  - design-decision alignment (how it follows `/Users/farzamh/code-git-local/task-agent-macos/.docs/design.md`)
  - implementation notes and validation status.
- Keep `/Users/farzamh/code-git-local/task-agent-macos/.docs/ui_ux_changes.md` current in the same task/PR where UI/UX work is introduced.

## `.docs/` Update Contract

- `.docs/PRD.md`:
  - Update when product requirements, scope, constraints, or locked addenda change.
  - Keep requirement statements explicit and testable.
- `.docs/design.md`:
  - Update when design decisions are introduced, revised, or locked.
  - Any new design choice must be recorded in this file in the same task/PR where it is introduced.
- `.docs/plan.md`:
  - Update when implementation phases, sequencing, or validation strategy changes.
  - Keep step definitions aligned with current execution reality.
- `.docs/next_steps.md`:
  - Keep this as the current execution queue.
  - Always include immediate priorities, code tasks, automated tests, manual tests, and exit criteria.
- `.docs/worklog.md`:
  - Append an entry for each incremental implementation step and major docs/process change.
  - Include: what changed, automated tests run, manual tests run, result, blockers, notes.
  - Keep only the 10 most recent `## Entry` sections in this file.
  - Move older entries to `.docs/legacy_worklog.md` using `scripts/rotate_worklog.sh`.
- `.docs/legacy_worklog.md`:
  - Archive for older `worklog.md` entries.
  - Do not review by default; consult only when historical context is needed.
- `.docs/testing.md`:
  - Update when test commands, environment limitations, or source-of-truth testing guidance changes.
- `.docs/xcode_signing_setup.md`:
  - Update when app identity, signing, entitlement, or permission-grant workflow changes.
- `.docs/open_issues.md`:
  - Update when a known unresolved issue is discovered, re-scoped, mitigated, or closed.
  - Keep entries actionable and current; do not leave stale "in progress" items without next steps.
- `.docs/ui_ux_changes.md`:
  - Update when UI/UX plans, decisions, or implementation direction changes.
  - Explicitly state how each entry aligns with `.docs/plan.md` and `.docs/design.md`.
- `.docs/*.bak`:
  - Treat as snapshots.
  - Do not edit routinely; refresh only when intentionally creating a backup snapshot.

## Docs-Only Changes

- If a task is docs-only, still update `.docs/worklog.md` and keep `.docs/next_steps.md` aligned with current priorities.
- In docs-only worklog entries, explicitly mark automated/manual tests as `N/A (docs-only)` unless a verification command is actually run.

## `open_issues.md` Entry Rules

- File location: `/Users/farzamh/code-git-local/task-agent-macos/.docs/open_issues.md`.
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
