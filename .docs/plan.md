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
- Add file-based prompt folders where each prompt defines `prompt.md` and `config.yaml` (`version`, `llm`).
- Use an outcome-first, path-flexible extraction prompt contract with explicit task-detection flags (`TaskDetected`, `Status`, `NoTaskReason`).
- Implement Gemini video adapter using upload -> poll-until-`ACTIVE` -> `generateContent`.
- Normalize configured model alias `gemini-3-pro` to provider-compatible runtime model ID when needed.
- Convert model output into `HEARTBEAT.md` updates while stripping control metadata fields (`TaskDetected`, `Status`, `NoTaskReason`).
- Add output validation to prevent empty/invalid task generation.
- Keep a strict persistence gate:
  - invalid extraction output must never overwrite existing `HEARTBEAT.md`.
  - `TaskDetected: false` output must not overwrite existing `HEARTBEAT.md`.

### Automated tests
- Unit tests for prompt builder and response parser.
- Unit tests for markdown writer (`Task` + `Questions` sections).
- Unit tests for metadata stripping before persistence.
- Integration test with mocked LLM responses (success and malformed output).

### Manual test
- Use a sample recording and generate `HEARTBEAT.md`.
- Verify task detail is specific, not over-summarized.
- Use a non-task/low-signal sample and verify structured no-task output is produced.
- Confirm no-task result does not modify existing `HEARTBEAT.md`.
- Verify failures show clear errors and recovery options.

## Step 4: Execution agent + clarification loop

### Code
- Build first concrete execution runner implementing `AutomationEngine`.
- Add execution-plan parser from `HEARTBEAT.md` goal/plan fields into actionable intents.
- Integrate Anthropic computer-use execution loop for desktop actions (`claude-opus-4-6` + computer-use tool).
- Execute app-agnostic desktop actions (open apps, click/type/shortcuts, scroll/drag/wait) through local action executor.
- On ambiguity/runtime failure, append unresolved blocking questions into `HEARTBEAT.md` `## Questions`.
- Baseline policy for this implementation increment:
  - allow run with unresolved open questions and request clarifications in run report.
  - no per-step confirmations.
  - no app allowlist/blocklist.
  - zero retries before raising clarification questions.
  - screenshot artifacts on failures only.
  - no max step/runtime limits.
- Persist per-run artifacts/logs under `runs/`.
- Keep clarification UI/state parser wired so newly appended runtime questions are immediately actionable.

### Automated tests
- Unit tests for execution-plan parsing from `HEARTBEAT.md`.
- Unit tests for automation-engine outcome mapping (`success`, `needs clarification`, `failed`).
- Unit tests for runtime question append/dedup in markdown.
- State-store tests for run-trigger flow and persistence of updated heartbeat + run summary state.
- Integration tests for run -> runtime question creation -> answer -> rerun.

### Manual test
- Run at least one extracted task using `Run Task` and confirm real desktop actions execute.
- Validate a multi-app flow where the runner opens an app and performs click/type steps.
- Trigger an ambiguity/failure case and confirm `HEARTBEAT.md` receives unresolved blocking question(s).
- Answer the generated question in-app, rerun, and confirm progression.
- Reopen task/relaunch app and confirm clarification + run state persists.

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
- Add a post-onboarding settings surface in main shell to update/remove saved API keys.

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
