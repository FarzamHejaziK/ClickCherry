# Agent Instructions

- At the beginning of any task, read all the docs in `.docs/` first.
- Testing strategy: at each incremental implementation step, verify with both automated code-based tests and manual tests before marking the step complete.
- Follow the `.docs/` update contract below for file ownership and maintenance rules.

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
- `.docs/testing.md`:
  - Update when test commands, environment limitations, or source-of-truth testing guidance changes.
- `.docs/xcode_signing_setup.md`:
  - Update when app identity, signing, entitlement, or permission-grant workflow changes.
- `.docs/open_issues.md`:
  - Update when a known unresolved issue is discovered, re-scoped, mitigated, or closed.
  - Keep entries actionable and current; do not leave stale "in progress" items without next steps.
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
