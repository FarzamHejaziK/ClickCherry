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
- Add Anthropic computer-use runner call path using `claude-opus-4-6`. (Implemented, legacy; no longer used by v1 UI as of 2026-02-13)
- Execute baseline app-agnostic actions from model output (open app/url, click, type, shortcuts). (Implemented)
- On ambiguity/runtime failure, append unresolved blocking questions into `HEARTBEAT.md` `## Questions`. (Implemented)
- Persist per-run summary artifacts under `runs/` including LLM-authored summary text. (Implemented)
- Integrate full iterative Anthropic computer-use tool loop (`computer_20251124`) for turn-based screenshot/tool execution. (Implemented, legacy; no longer used by v1 UI as of 2026-02-13)
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
- Enforce screenshot-size safety against a conservative base64 payload budget before request send (downscale/re-encode when required). (Implemented)
- Enforce tool-policy boundary at runtime: reject visual/UI-oriented terminal commands and direct model to `desktop_action`. (Implemented)
- Prepare a cleaner visual workspace before run by hiding other regular apps. (Implemented)
- Add diagnostics screenshot log showing the exact images sent to the LLM tool loop. (Implemented)
- Keep takeover cursor presentation unchanged (normal cursor size, no cursor-following halo overlay). (Implemented)
- Execution provider is OpenAI only; remove execution-provider selection UI and always route runs through OpenAI. (Implemented)
- OpenAI Responses runner exposes both `desktop_action` and `terminal_exec`. (Implemented)
- Replace the centered takeover HUD with a transparent, top-anchored live run overlay on the selected display. (Implemented)
- Populate the overlay from active run events plus screenshot logs with newest-first ordering and recent thumbnails. (Implemented)
- Keep `Escape` cancellation visible as a stopping state until final run cleanup rather than hiding the overlay immediately. (Implemented)
- Project run events into user-facing overlay copy and suppress backend transport/setup detail. (Implemented)
- Surface screenshot capture/review as overlay activity rows and use placeholder rows so the early-run feed never looks unfinished. (Implemented)
- Keep overlay animation state and layout stable across updates; avoid whole-view rebuilds and panel-height wobble. (Implemented)
- Attempted slower "natural" mouse motion was rolled back; default pointer motion remains direct to avoid slowing execution. (Implemented rollback)
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
- Unit tests for OpenAI tool-surface parity with Anthropic baseline (`desktop_action` + `terminal_exec`, including visual-command rejection and PATH-resolution behavior). (Implemented)
- Unit tests for cursor-position tool action mapping and tool-result payload format.
- Unit tests for request-history image compaction (latest-image only).
- Unit tests for terminal policy enforcement (visual command rejection -> `computer` guidance).
- Unit tests for base64 image-size budgeting helpers (5 MB encoded limit mapping).
- Unit tests for LLM screenshot-log entries (initial + tool-result screenshot captures).
- State-store test for run preflight desktop preparation invocation.
- State-store tests for takeover cursor-presentation activation/deactivation hooks (Escape cancellation and monitor-start failure paths).
- Integration tests for richer tool-action coverage (scroll/drag/right-click/move) are pending.

### Manual test
- Run at least one extracted task using `Run Task` and confirm real desktop actions execute.
- While the run is executing, confirm:
  - a transparent, top-anchored live activity overlay appears on the selected display.
  - the newest action/status stays at the top and previous actions remain visible below it.
  - screenshot thumbnails match the persisted model-visible screenshots for the run.
  - screenshot-taking/reviewing appears as user-facing activity in the feed.
  - pressing `Escape` changes the overlay into a visible stopping state that remains on-screen until the run settles.
  - cursor presentation stays normal (no enlarged cursor and no cursor-following halo overlay).
- Confirm clicking `Run Task` minimizes the app window immediately (agent overlay remains visible).
- Confirm cursor presentation remains unchanged after run completion/cancellation (including early takeover setup failure).
- Confirm the agent overlay is not present in the screenshots sent to the LLM (no overlay visible in agent behavior / screenshots used for navigation).
- Confirm overlay copy describes user-visible agent work and does not expose backend transport details such as HTTP/WebSocket wording.
- Validate `terminal_exec` can run unrestricted commands and open apps reliably (ex: `open -a "Google Chrome"`), and that stdout/stderr/exit code are reported back to the tool loop.
- Validate UI-oriented terminal commands are rejected and model switches to `desktop_action` actions.
- Validate request payload size does not grow linearly with screenshot count during long tool loops.
- Validate Diagnostics shows “LLM Screenshots” that match the model-visible images per turn.
- Validate a multi-app flow where the runner opens an app and performs click/type steps.
- Trigger an ambiguity/failure case and confirm `HEARTBEAT.md` receives unresolved blocking question(s).
- Answer the generated question in-app, rerun, and confirm progression.
- Reopen task/relaunch app and confirm clarification + run state persists.
- Confirm any future cursor-motion polish does not materially slow visible desktop actions before adopting it.

### Maintainability follow-up: OpenAI execution-runner split

#### Code
- Status: implemented and validated on 2026-03-26; focused OpenAI runner tests, the full unit-test target, a clean app build, local launch smoke, and the live provider-backed smoke pass are complete.
- Refactor `OpenAIAutomationEngine.swift` into concern-based files under `TaskAgentMacOSApp/TaskAgentMacOSApp/Services/OpenAIAutomation/` without changing behavior.
- Keep `OpenAIComputerUseRunner` as the single orchestration type and keep `OpenAIAutomationEngine` as the thin `AutomationEngine` adapter.
- Preserve all existing request payloads, response parsing, constants, tool schemas, error text, policy boundaries, coordinate math, screenshot behavior, and logging semantics exactly.
- Move code by concern only:
  - orchestration
  - transport/retry/request building
  - tool execution / terminal execution
  - capture / coordinate mapping
  - response parsing / summarization
  - request/response DTOs

#### Automated tests
- Keep `TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests.swift` green after each extraction slice.
- Run the full `TaskAgentMacOSAppTests` target after the final split.
- Add characterization coverage only where needed to lock existing OpenAI runner behavior before moving code.

#### Manual test
- Launch the app and run a known-safe OpenAI task against a controlled desktop target.
- Verify normal success path, cancellation path, and a run that exercises both `desktop_action` and `terminal_exec`.
- Validation note:
  - Completed on 2026-03-26 with user-reported success after following the OpenAI runner smoke checklist.
- Confirm there is no visible regression in run startup, HUD behavior, screenshot-driven interaction, or error presentation.

### Maintainability follow-up: feature-first folder organization (implemented: 2026-04-09)

#### Code
- Status: implemented on 2026-04-09 as a no-intended-behavior-change source/layout refactor.
- Reorganize the app target into a feature-first structure:
  - `TaskAgentMacOSApp/TaskAgentMacOSApp/App`
  - `TaskAgentMacOSApp/TaskAgentMacOSApp/Features`
  - `TaskAgentMacOSApp/TaskAgentMacOSApp/Core`
  - `TaskAgentMacOSApp/TaskAgentMacOSApp/UI`
  - `TaskAgentMacOSApp/TaskAgentMacOSApp/Resources`
- Co-locate feature code under `Features/MainShell`, `Features/Onboarding`, `Features/Recording`, `Features/TaskExecution`, `Features/Permissions`, and `Features/PromptCatalog`.
- Move shared non-UI types and services under `Core/Models`, `Core/Desktop`, `Core/Persistence`, `Core/Workspace`, and `Core/LLM`.
- Move reusable UI-only code under `UI/Components`, `UI/Styles`, and `UI/Titlebar`.
- Move app assets and prompt folders under `Resources/Assets.xcassets` and `Resources/Prompts`.
- Update `PromptCatalogService` source lookup and the Xcode prompt-copy build phase so debug/source lookup and bundled prompt loading still resolve the same prompt names and versions after the resource move.
- Reorganize tests to mirror the new source ownership under `TaskAgentMacOSAppTests/Core`, `TaskAgentMacOSAppTests/Features`, `TaskAgentMacOSAppTests/TestSupport`, and `TaskAgentMacOSAppUITests/App`.

#### Automated tests
- Run the full app build after the file moves:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  build
```

- Run the full test suite after the file moves:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  test
```

- Keep prompt-catalog regression coverage green after the `Resources/Prompts` move, including default source-path resolution for `execution_agent_openai`.

#### Manual test
- Inspect the built app bundle and confirm `Contents/Resources/Prompts` contains the expected prompt files and versioned OpenAI prompt folders.
- Launch the debug app and run the highest-risk structural smoke flows:
  - onboarding through permissions/provider setup
  - MainShell navigation and task open/create
  - recording import/capture
  - extraction prompt loading
  - one execution run
- Validation note:
  - automated build/test, prompt-bundle inspection, and a brief debug-app launch smoke completed successfully on 2026-04-09.
  - full interactive runtime walkthrough is still the remaining manual follow-up after the structural refactor.

### Execution vision-grounding increment (implemented: 2026-03-27)

#### Code
- Add `DesktopScreenshotTransformService.swift` for screenshot cropping, scaling, PNG re-encoding, and grid-overlay rendering.
- Add `OpenAIComputerUseRunner+VisionState.swift` to keep active screenshot/view metadata and coordinate remapping separate from selected-display anchoring state.
- Add `OpenAIComputerUseRunner+ScreenshotActions.swift` to implement real screenshot tool behavior for `full`, `crop`, and `current` modes.
- Extend `desktop_action` screenshot parameters with crop/zoom/overlay fields and return screenshot metadata in tool outputs.
- Make crop/current screenshots update the active vision state so subsequent click/move coordinates resolve against the latest returned image.
- Preserve OpenAI control-loop screenshots as PNG and send image inputs with `detail: "original"`.
- Update the OpenAI execution prompt to teach `full -> crop -> fine overlay -> act` and “one dependent visual action per turn”.
- Add runner-side guardrails that defer later same-turn visual `desktop_action` calls with a `wait_for_visual_feedback` tool response.
- After non-screenshot desktop actions, reset the next-turn visual context back to a fresh full-display screenshot.

#### Automated tests
- Added `TaskAgentMacOSAppTests/DesktopScreenshotTransformServiceTests.swift`.
- Added `TaskAgentMacOSAppTests/OpenAIComputerUseRunnerVisionTests.swift`.
- Verified:
  - screenshot request parsing
  - `full`, `crop`, and `current` screenshot modes
  - crop and nested-crop coordinate remapping
  - `detail: "original"` image payloads
  - full-display reset after non-screenshot actions
  - same-turn dependent visual action deferral
- Validation commands completed successfully on 2026-03-27:
  - focused OpenAI runner suite
  - focused vision suites
  - full `TaskAgentMacOSAppTests` target
  - full app build

#### Manual test
- Interactive validation checklist for this increment:
  - full screenshot -> crop -> fine grid -> click a small target
  - crop-inside-crop targeting on a tiny UI element
  - confirm click coordinates from a crop land on the correct real screen point
  - validate grid readability on both light and dark backgrounds
  - confirm multi-display runs still target the selected display
  - confirm the runner returns to a fresh full-display context after click/type/open actions
- Validation note:
  - automated coverage is complete as of 2026-03-27.
  - interactive desktop validation is still pending in local runtime and remains the immediate next step.

### Responses WebSocket transport increment (implemented: 2026-04-01)

#### Code
- Add an internal transport mode enum for the OpenAI execution runner:
  - `http`
  - `webSocketPreferred`
  - `webSocketOnly`
- Store the selected mode in `MainShellStateStore` `UserDefaults` handling and default the active app path to `webSocketPreferred`.
- Extract the previous HTTP `/v1/responses` logic into an HTTP transport session without changing request semantics.
- Add a WebSocket transport session that:
  - opens `wss://api.openai.com/v1/responses`
  - sends `response.create` events using the same per-turn request body fields as the HTTP path
  - accumulates stream events into a normalized `OpenAIResponsesResponse`
  - preserves the existing tool loop contract above the transport boundary
- Keep `OpenAIComputerUseRunner` as the orchestration owner and make transport selection/fallback internal to the transport layer.
- Preserve diagnostics parity by recording request/response exchanges and trace entries for both HTTP and WebSocket paths.

#### Automated tests
- Keep the focused OpenAI runner suites green with the transport abstraction in place.
- Add focused tests covering:
  - initial WebSocket request envelope contents
  - follow-up turns with `previous_response_id` and `function_call_output`
  - fallback from initial WebSocket connect failure to HTTP
  - fallback from `previous_response_not_found` to HTTP
  - reconnect-once behavior for `websocket_connection_limit_reached`
- Validation commands completed successfully on 2026-04-01:
  - `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerVisionTests CODE_SIGNING_ALLOWED=NO`
  - `xcodebuild build -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO`

#### Manual test
- Local launch smoke completed on 2026-04-01:
  - launched the built debug app successfully
  - confirmed the process started cleanly
  - terminated the launched app after startup verification
- Interactive provider-backed validation still pending:
  - compare one safe multi-turn task in `http` mode and `webSocketPreferred` mode
  - confirm tool behavior, screenshot flow, final status handling, trace readability, and latency impact

### Execution takeover overlay redesign increment (planned: 2026-04-01)

#### Code
- Replace the centered `Agent is running` HUD with a transparent, top-anchored activity overlay on the selected display.
- Extend `AgentControlOverlayService` so the overlay can receive live run state updates instead of only static show/hide commands.
- Feed the overlay from the active run's existing event and screenshot streams:
  - newest action or status at the top
  - previous actions stacked below
  - recent model-visible screenshots rendered as compact thumbnails
- Keep the overlay click-through, non-activating, and excluded from model screenshots through the existing window-exclusion path.
- Update Escape cancellation behavior so the overlay remains visible in a stopping state until the run actually settles, instead of disappearing immediately on key press.
- Preserve the current selected-display border overlay and the existing takeover cursor behavior.

#### Automated tests
- Expand `TaskAgentMacOSAppTests/MainShellStateStoreTests.swift` to cover:
  - live overlay activation on run start
  - overlay updates from appended trace events and screenshot log entries
  - Escape-triggered stopping state remaining visible until run completion
  - final overlay dismissal after cancellation or normal completion
- Keep the app build green after the overlay service and state-store changes.

#### Manual test
- Run a safe multi-turn task and confirm the overlay appears on the selected display as a transparent top activity rail.
- Confirm the newest action appears first and earlier actions remain visible below it while the run continues.
- Confirm recent screenshot thumbnails shown in the overlay match the model-visible run screenshots.
- Press `Escape` during a run and confirm the overlay switches to a visible stopping state before dismissing after the run settles.
- Confirm the overlay never appears inside screenshots sent to the model, even when the overlay itself shows screenshot thumbnails.

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

## Step 8: Open-source readiness and repository operations

### Code
- Add repository-level open-source governance files:
  - `LICENSE` (MIT)
  - `CONTRIBUTING.md`
  - `CODE_OF_CONDUCT.md`
  - `SECURITY.md`
  - `GOVERNANCE.md`
  - `MAINTAINERS.md`
  - `CHANGELOG.md`
- Add GitHub collaboration scaffolding:
  - `CODEOWNERS`
  - PR template
  - bug/feature issue templates
  - CI workflow (`xcodebuild` build + unit tests)
  - release workflow baseline
- Create public contributor docs in `/docs/` and align `README.md`.
- Track locked open-source decisions and follow-ups in `/.docs/open_source.md`.

### Automated tests
- Run unit tests to confirm docs/workflow changes do not regress build/test paths.
- Validate workflow file syntax and required file presence.

### Manual test
- Review public docs flow from `README.md` -> `/docs/*` for onboarding clarity.
- Review governance docs for consistency (license, contribution policy, owner approval model).
- Confirm release docs explicitly call out signed artifact prerequisites and pending secrets.

## Step 0.5: First-run onboarding (API keys + preflight)

### Code
- Add first-run onboarding flow before task creation.
- Screens:
  1. Welcome
  2. Provider setup (OpenAI required, Gemini required)
  3. Permissions preflight (Screen Recording, Microphone, Accessibility, Input Monitoring; allow Skip to grant later)
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
