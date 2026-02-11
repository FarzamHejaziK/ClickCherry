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
- Build first concrete execution runner implementing `AutomationEngine`. (Implemented)
- Add `Run Task` trigger in task detail and wire state-store run orchestration. (Implemented)
- Add Anthropic computer-use runner call path using `claude-opus-4-6`. (Implemented)
- Execute baseline app-agnostic actions from model output (open app/url, click, type, shortcuts). (Implemented)
- On ambiguity/runtime failure, append unresolved blocking questions into `HEARTBEAT.md` `## Questions`. (Implemented)
- Persist per-run summary artifacts under `runs/` including LLM-authored summary text. (Implemented)
- Integrate full iterative Anthropic computer-use tool loop (`computer_20251124`) for turn-based screenshot/tool execution. (Implemented)
  - In the tool-loop request format, use:
    - `tools[].type = computer_20251124`
    - `anthropic-beta: computer-use-2025-11-24`
  - Keep model identity separate from tool identity (`claude-opus-4-6` is model; `computer_20251124` is tool version).
- Remove legacy planner/fallback execution path; keep tool-loop as the only action authority path. (Implemented)
- Load execution-agent prompt from file-based prompt folder (`Prompts/execution_agent/prompt.md` + `config.yaml`) via `PromptCatalogService`. (Implemented)
- Include host OS version string in the execution-agent prompt via placeholder (`{{OS_VERSION}}`). (Implemented)
- Advertise and handle a custom tool-loop tool `terminal_exec` for unrestricted terminal command execution (absolute-path or PATH-resolved executables). (Implemented)
- Add cursor-position action support (`cursor_position`) in tool-loop path. (Implemented)
- Include mouse cursor in tool-loop screenshots for visual grounding during hover/mouse tasks. (Implemented)
- Enforce fail-closed screenshot capture when HUD exclusion is requested (never fall back to non-excluding capture for LLM screenshots). (Implemented)
- Reduce tool-loop payload growth by keeping full text/tool history but only the latest screenshot image block in each request. (Implemented)
- Enforce screenshot-size safety against Anthropic's base64 5 MB image limit (not raw bytes) before request send. (Implemented)
- Enforce tool-policy boundary at runtime: reject visual/UI-oriented terminal commands and direct model to `computer`. (Implemented)
- Prepare a cleaner visual workspace before run by hiding other regular apps. (Implemented)
- Add diagnostics screenshot log showing the exact images sent to the LLM tool loop. (Implemented)
- During takeover, significantly increase cursor visibility and restore at run end/cancel:
  - preferred path: temporary system cursor-size increase + restore.
  - fallback path: large cursor-following halo overlay when system cursor-size writes are blocked.
  (Implemented)
- Update execution-agent prompt guidance so the model knows cursor visibility may be enhanced (larger cursor and/or halo) and should treat it as pointer visualization, not target UI. (Implemented)
- Expand tool/action coverage to drag in tool-loop path. (Pending)
- Baseline policy for this implementation increment:
  - allow run with unresolved open questions and request clarifications in run report.
  - no deterministic local action-plan synthesis; model tool calls are the only action authority.
  - no per-step confirmations.
  - no app allowlist/blocklist.
  - zero retries before raising clarification questions.
  - screenshot artifacts on failures only.
  - no max step/runtime limits.
- Persist per-run artifacts/logs under `runs/`.
- Keep clarification UI/state parser wired so newly appended runtime questions are immediately actionable.

### Automated tests
- Unit tests for automation-engine outcome mapping (`success`, `needs clarification`, `failed`) in tool-loop-only path.
- Unit tests for runtime question append/dedup in markdown.
- State-store tests for run-trigger flow and persistence of updated heartbeat + run summary state.
- Unit tests for Anthropic tool-loop API-key gating and request formatting.
- Unit tests for iterative tool-loop request formatting and response-to-result mapping.
- Unit tests for `terminal_exec` tool definition + dispatch (PATH resolution + output capture).
- Unit tests for cursor-position tool action mapping and tool-result payload format.
- Unit tests for request-history image compaction (latest-image only).
- Unit tests for terminal policy enforcement (visual command rejection -> `computer` guidance).
- Unit tests for base64 image-size budgeting helpers (5 MB encoded limit mapping).
- Unit tests for LLM screenshot-log entries (initial + tool-result screenshot captures).
- State-store test for run preflight desktop preparation invocation.
- State-store tests for takeover cursor-size activation/restoration (Escape cancellation and monitor-start failure paths).
- Integration tests for richer tool-action coverage (scroll/drag/right-click/move) are pending.

### Manual test
- Run at least one extracted task using `Run Task` and confirm real desktop actions execute.
- While the run is executing, confirm:
  - a centered "agent running" overlay appears.
  - pressing `Escape` cancels the run and hides the overlay.
  - cursor visibility is significantly larger while the agent is in control (either larger system cursor or halo overlay).
  - agent behavior remains stable when cursor halo is visible (the model does not treat halo as a UI target).
- Confirm clicking `Run Task` minimizes the app window immediately (agent overlay remains visible).
- Confirm cursor visibility enhancement is removed after run completion/cancellation (including early takeover setup failure).
- Confirm the agent overlay is not present in the screenshots sent to the LLM (no overlay visible in agent behavior / screenshots used for navigation).
- Validate `terminal_exec` can run unrestricted commands and open apps reliably (ex: `open -a "Google Chrome"`), and that stdout/stderr/exit code are reported back to the tool loop.
- Validate UI-oriented terminal commands are rejected and model switches to `computer` actions.
- Validate request payload size does not grow linearly with screenshot count during long tool loops.
- Validate Diagnostics shows “LLM Screenshots” that match the model-visible images per turn.
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
