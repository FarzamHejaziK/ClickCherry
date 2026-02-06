---
description: Step-by-step implementation plan with code scope, automated tests, and manual tests for each milestone
---

# Implementation Plan

## Step 0: Project foundation and test harness

### Code
- Create native macOS app skeleton (SwiftUI, app lifecycle, navigation shell).
- Add local storage layer for task workspaces (`HEARTBEAT.md`, `recordings/`, `runs/`).
- Add basic dependency boundaries for LLM client, automation engine, scheduler.

### Automated tests
- Unit tests for workspace path creation and file read/write.
- Unit tests for app config loading and validation.

### Manual test
- Launch app and create/open a local workspace.
- Verify expected folders and files are created on disk.

## Step 1: Task functionality (create/list/open)

### Code
- Implement `New Task` flow.
- Implement task list and task detail navigation.
- Implement `HEARTBEAT.md` creation with sections:
  - `# Task`
  - `## Questions`

### Automated tests
- Unit tests for task creation service.
- Unit tests for task list loading/parsing.
- UI tests for create -> list -> open flow.

### Manual test
- Create multiple tasks from UI.
- Reopen app and verify tasks persist and load correctly.

## Step 2: Screen recording functionality

### Code
- Add recording import first (`.mp4` select and attach to task).
- Add direct recording capture (full desktop) as second part.
- Save recordings under `recordings/` with metadata.

### Automated tests
- Unit tests for recording file validation and copy/move logic.
- Unit tests for recording metadata persistence.

### Manual test
- Import a valid `.mp4` and confirm it appears in task detail.
- Run direct capture and confirm output is saved in `recordings/`.
- Test permission denial path (Screen Recording not granted).

## Step 3: Task extraction from recording

### Code
- Implement video-understanding pipeline (LLM call).
- Convert model output into `HEARTBEAT.md` updates.
- Add output validation to prevent empty/invalid task generation.

### Automated tests
- Unit tests for prompt builder and response parser.
- Unit tests for markdown writer (`Task` + `Questions` sections).
- Integration test with mocked LLM responses (success and malformed output).

### Manual test
- Use a sample recording and generate `HEARTBEAT.md`.
- Verify task detail is specific, not over-summarized.
- Verify failures show clear errors and recovery options.

## Step 4: Task completion + clarification loop

### Code
- Implement execution runner for task steps.
- Implement question generation when execution hits ambiguity/failure.
- Persist unresolved/resolved questions in `HEARTBEAT.md`.

### Automated tests
- Unit tests for question state transitions (open/resolved/reopened).
- Unit tests for run result persistence under `runs/`.
- Integration tests for run -> question creation -> answer -> rerun.

### Manual test
- Execute task once; verify run summary is stored.
- Trigger ambiguous scenario; verify question is asked and persisted.
- Answer question and rerun; confirm progress.

## Step 5: Scheduling (cron-style while app is open)

### Code
- Add natural-language schedule input.
- Parse to internal schedule representation.
- Execute scheduled runs while app is active.

### Automated tests
- Unit tests for schedule parsing and validation.
- Unit tests for scheduler trigger timing and deduplication.
- Integration tests for scheduled run creation and history writes.

### Manual test
- Set a short schedule (e.g., every 5 minutes) and verify trigger.
- Verify `last run` and `next run` update in UI.
- Restart app and confirm schedule reload behavior.

## Step 6: Reliability and safety hardening

### Code
- Add preflight checks (permissions, missing resources, app state).
- Add retry and fallback logic for fragile UI actions.
- Add safety gates for destructive actions.

### Automated tests
- Unit tests for preflight diagnostics.
- Unit tests for retry/backoff behavior.
- Integration tests for partial-failure recovery paths.

### Manual test
- Revoke permissions and verify clear remediation guidance.
- Simulate UI drift/failure and verify fallback behavior.
- Validate safety confirmation UX for risky actions.

## Step 7: Release candidate validation

### Code
- Polish onboarding, task status, and run history UX.
- Freeze v1 scope and cleanup tech debt that blocks stability.

### Automated tests
- Full test suite run (unit + integration + UI).
- Regression suite on core flows: create, record, extract, run, schedule.

### Manual test
- End-to-end test from fresh install to first successful scheduled run.
- Multi-task test (at least 3 tasks) for stability and persistence.
- Final checklist for permissions, error handling, and data integrity.

## Step 0.5: First-run onboarding (API keys + preflight)

### Code
- Add first-run onboarding flow before task creation.
- Screens:
  1. Welcome
  2. Provider setup (OpenAI or Anthropic required, Gemini required)
  3. Permissions preflight (Screen Recording, Accessibility, Automation)
  4. Ready state
- Persist API keys in Keychain.
- Add validation for missing/invalid keys before continuing.

### Automated tests
- Unit tests for Keychain read/write wrappers.
- Unit tests for provider setup validation rules.
- UI tests for onboarding completion gating (cannot continue until required fields are valid).

### Manual test
- Fresh install run: verify onboarding appears before main app.
- Enter valid keys and complete onboarding; relaunch app and confirm onboarding is skipped.
- Remove/revoke key and verify app returns to provider setup state with clear guidance.

## Testing Strategy (process rule)

- Every incremental implementation step must include both:
  1. Automated code-based tests
  2. Manual verification
- A step is considered complete only after both test types pass for that step.
