---
description: Design decision checklist for the native macOS task agent, including open decisions that must be finalized before and during implementation
---

# Design Decisions

## Maintenance rule

- Every new design choice introduced during implementation must be documented in this file in the same task/PR.

## 1) Product scope and success criteria
- v1 app scope: menu bar app, dock app, or both
- Single-user local app vs future multi-user sync
- v1 success KPI: first successful scheduled run within what time
- Supported macOS minimum version

## 2) Task model
- Canonical task format: free-form `HEARTBEAT.md` only vs hybrid structured metadata + markdown body
- One task = one agent runtime boundary details
- How task versions are tracked (history, rollback)
- How follow-up recordings merge into existing task

## 3) Recording model
- v1 input: import `.mp4` only or include direct in-app recording now
- Capture scope: full display, single window, or both
- Multi-monitor behavior
- Recording max duration and size limits
- Recording privacy controls (pause/resume, redact zones later)

## 4) Video understanding and prompt design
- Primary model/provider for video understanding
- Fallback model/provider strategy
- Prompt contract and strict output schema
- Confidence scoring and low-confidence fallback flow
- Regeneration policy (when to overwrite vs append)

## 5) Clarification loop
- When a question is generated (confidence threshold, runtime ambiguity rules)
- Question lifecycle states (open, answered, stale, reopened)
- Block run on open questions vs allow run with warnings
- UX location for questions (task detail, run result, both)

## 6) Automation execution engine
- Automation approach: Accessibility API action graph vs vision+heuristics hybrid
- Locator strategy (AX identifiers, titles, relative positions)
- Deterministic checkpoints between steps
- Retry policy and timeout strategy
- Recovery behavior on drift (ask user, skip, stop)

## 7) Scheduling and runtime mode
- Schedule parsing: natural language parser + deterministic validator
- Scheduler reliability model while app is open
- Behavior when app is closed in v1
- Missed-run policy on restart
- Timezone policy and daylight-saving handling

## 8) Permissions and system integration
- Required permission set in v1 (Accessibility, Screen Recording, Automation)
- Permission preflight UX and remediation flow
- Managed-device limitations handling
- Least-privilege policy and permission revocation handling

## 9) Safety and control model
- Risky action classes requiring confirmation
- Human-in-the-loop checkpoints for irreversible actions
- Allowed/blocked app list support in v1
- Run sandboxing boundaries

## 10) Data, security, and secrets
- Workspace layout finalization (`HEARTBEAT.md`, `recordings/`, `runs/`)
- Secret storage mechanism (Keychain schema)
- Log redaction policy for sensitive UI/text
- Data retention policy for recordings and run artifacts

## 11) UI architecture decisions
- Navigation structure and screen ownership boundaries
- State management pattern (`Observation` and async flow)
- Error/status presentation model
- Background task UX (in-progress, paused, failed, needs input)

## 12) Observability and diagnostics
- What to log per run (step-level traces, screenshots, errors)
- User-facing diagnostics vs developer diagnostics separation
- Export format for troubleshooting bundles
- Crash and failure telemetry (local only in v1)

## 13) Testing strategy
- Unit/integration/UI test boundaries
- Golden test fixtures for recording-to-task extraction
- Deterministic automation tests (mocked AX tree vs live env)
- Manual QA checklist per milestone

## 14) Packaging and release
- Distribution mode: local dev first, signed app later
- Code signing/notarization timing
- Update mechanism choice (manual, Sparkle, custom)
- Migration strategy for task/workspace format changes

## Decision log template
Use this template per finalized decision:

- Decision ID:
- Date:
- Context:
- Options considered:
- Decision:
- Consequences:
- Follow-up actions:

## Current v1 defaults (locked)

- Recording input: import `.mp4` first (fastest path), because final artifact needed is the recording file.
- Task format: `HEARTBEAT.md` only (free-form markdown) for v1.
- Automation scope: desktop-wide computer-use execution in v1 (not web-only).
- Scheduler mode: easiest v1 path = run jobs while app is open only (no background helper yet).

## Run policy with open questions (locked: 2026-02-08)

This means: if the agent still has unresolved questions, should execution stop or continue?

- Option A: block run until user answers all open questions.
- Option B: allow run with warnings, and ask follow-up questions after run.

- Decision: Option B.
- Runtime behavior:
  - `Run Task` is allowed even when unresolved questions exist.
  - unresolved/open questions are surfaced in run status/report UI.
  - after run completion (or blocked completion), clarification questions are shown to user for follow-up.

## Clarification policy (decided)

- After recording analysis, the app sends exactly one round of clarification questions.
- Execution is allowed with warnings even if that round remains unresolved.
- Unresolved or newly generated questions are surfaced after run/report for user follow-up.
- After answers are applied to `HEARTBEAT.md`, subsequent runs use the updated context.

## UI clarification decision (locked)

- v1 includes a lightweight in-app chat/Q&A panel for clarification.
- This is not a full messaging product; scope is task clarification only.
- Interaction contract:
  1. System posts one round of clarification questions after recording analysis.
  2. User answers in panel input.
  3. User confirms with `Apply & Continue`.
  4. App writes answers into `HEARTBEAT.md` and unblocks execution.

## Clarification markdown state format (locked: 2026-02-08)

- Question parsing source of truth is the `## Questions` section in `HEARTBEAT.md`.
- Parsed open questions come from markdown bullets under that section, excluding `- None.`.
- Applying an answer rewrites the selected question into a resolved checklist item:
  - question line: `- [x] <question>`
  - answer line: `Answer: <answer>` (indented under that question item)
- The app keeps unresolved/resolved state derived from markdown, not separate storage.

## Platform decision (locked)

- v1 minimum macOS target: macOS 14 (Sonoma).
- Rationale: easiest modern baseline for SwiftUI/Observation and fewer compatibility branches.

## Recording limits (locked)

- Max recording size: 2 GB.
- Max recording duration: 5 minutes.
- If exceeded, app blocks ingestion and asks user to trim/re-record.

## LLM provider onboarding (locked)

- App asks for API keys during first-run setup.
- Required providers in v1 onboarding:
  - OpenAI or Anthropic (Claude) for core agent tasks.
  - Gemini for video understanding path.
- Keys are stored locally in Keychain (never plaintext in logs).

## Execution agent model/provider decision (locked: 2026-02-10)

- Task execution agent provider for Step 4 is Anthropic computer-use with:
  - model: `claude-opus-4-6`
  - tool type: `computer_20251124`
- Anthropic computer-use identifiers must be treated as:
  - `claude-opus-4-6`: the model.
  - `computer_20251124`: the computer-use tool schema/version identifier (not a model).
  - `anthropic-beta: computer-use-2025-11-24`: required beta header paired with `computer_20251124`.
- Usage boundary:
  - These values are required on Anthropic `messages` requests that include the computer-use tool loop (`tools` entry with type `computer_20251124`).
  - Execution now uses tool-loop only; there is no planner-only execution path.
- Execution loop is tool-driven:
  1. app captures current desktop screenshot/state
  2. model returns tool actions
  3. app executes actions locally
  4. app returns tool results and continues until stop condition
- Runner scope in this decision is app-agnostic desktop control, including:
  - opening apps/windows
  - clicking, typing, keyboard shortcuts
  - scrolling/dragging/waiting
- If execution is blocked by ambiguity or runtime failure, the app must append unresolved blocking questions to `## Questions` in `HEARTBEAT.md` instead of silently guessing.

## Execution action-authority policy (locked: 2026-02-09)

- During task execution, every desktop action must come from an LLM computer-use tool call.
- `HEARTBEAT.md` is execution context and persistent task memory; it is not a deterministic local action script.
- The app may parse/validate `HEARTBEAT.md` sections to build context and derive clarification state.
- The app must not synthesize local click/type/shortcut/scroll action plans outside model-issued tool calls.
- If tool output is invalid, missing, or ambiguous, the run must stop and append clarification question(s) to `HEARTBEAT.md` instead of guessing.

## Execution prompt runtime context (locked: 2026-02-10)

- The execution-agent prompt includes the host OS version string inline via a placeholder (`{{OS_VERSION}}`) that is rendered at run start.
- Rationale: Some system UI and shortcut behaviors vary by macOS version; including it helps the model choose robust actions.
- Implementation:
  - prompt contains: `OS: {{OS_VERSION}}`
  - render value source: `ProcessInfo.processInfo.operatingSystemVersionString`
  - prompt explicitly tells the model cursor visibility may be enhanced (larger cursor and/or cursor-following halo) and that this is pointer visualization, not target UI content.

## Execution terminal tool (locked: 2026-02-11)

- The execution tool loop defines a second tool in addition to the built-in computer-use tool:
  - `computer`: built-in Anthropic tool (desktop actions + screenshots)
  - `terminal_exec`: custom tool that runs a non-shell `Process` command and returns stdout/stderr/exit code as JSON
- Tool selection priority (prompt guideline):
  - use `computer` for visual/spatial on-screen actions
  - use `terminal_exec` for deterministic non-visual command-line tasks
- Within `computer` (prompt guideline):
  - prefer shortcut/keyword-driven actions (keyboard shortcuts + typing) over mouse movement/clicks when possible
- Baseline safety policy for `terminal_exec`:
  - unrestricted executable set (no allowlist).
  - executable resolution:
    - absolute path when provided
    - otherwise resolve by searching `PATH`.
  - shell executables are allowed if requested by the model.
- Runtime enforcement:
  - terminal commands that appear to perform UI/visual automation are rejected with an error and redirected to `computer`.
  - examples blocked by policy include AppleScript/UI-element style commands intended to locate/click/hover screen elements.
- Primary use-case: command-line-first task execution and reliable app control (including `open -a ...`).
- Revisit candidate: reintroduce safety boundaries only if product policy changes (tracked in `.docs/revisits.md`).

## OpenAI custom desktop tool loop (locked: 2026-02-11)

- Added a second execution-provider path using OpenAI Responses API:
  - model baseline: `gpt-5.2-codex`
  - runtime tool: custom function tool `desktop_action` (JSON schema action envelope)
  - loop format: screenshot + prompt input -> `function_call` -> local action execution -> `function_call_output` + fresh screenshot -> continue
- Action surface implemented in `desktop_action`:
  - screenshot
  - cursor position read
  - mouse move
  - left click
  - right click
  - double click
  - type text
  - keyboard shortcut
  - open app
  - open URL
  - scroll
  - wait
- Screenshot strategy for OpenAI path:
  - reuse existing execution screenshot capture path (including HUD exclusion and cursor-visible images).
  - send screenshot as data URL image input each turn.
- Completion contract remains shared with Anthropic path:
  - final plain JSON text:
    - `status`: `SUCCESS | NEEDS_CLARIFICATION | FAILED`
    - `summary`
    - `error`
    - `questions`
- Provider routing policy:
  - execution defaults to OpenAI path when an OpenAI API key is configured.
  - fallback to Anthropic path when OpenAI key is missing and Anthropic key exists.

## Execution takeover UX (locked: 2026-02-10)

- While a run is executing, the app must show a centered on-screen HUD overlay indicating the agent is running and in control.
- The run is cancelled when the user presses `Escape` (explicit takeover), and the HUD overlay is hidden.
- When a run starts from the UI, the main app window is immediately minimized (the HUD overlay remains visible).
- Implementation details:
  - A global `CGEventTap` monitors `keyDown` and triggers only on `Escape`.
  - The desktop action executor tags injected CGEvents with a sentinel `eventSourceUserData` value so the interruption monitor ignores synthetic events (avoid self-cancel).
  - Desktop screenshots are captured while excluding the HUD overlay window so it does not appear in images sent to the LLM tool loop.
  - While takeover is active, the app attempts to increase system cursor size (target `4.0`) and restore the previous value when takeover ends.
  - If macOS blocks writing cursor-size preferences, the app falls back to a large cursor-following halo overlay during takeover and removes it at takeover end.
- Permission requirements for this UX:
  - Screen Recording: screenshots for the tool loop.
  - Accessibility: inject clicks/keys.
  - Input Monitoring: detect user takeover to cancel.

## Step 4 implementation status (update: 2026-02-11)

- Implemented in this increment:
  - `Run Task` UI action and state-store run pipeline.
  - Anthropic computer-use runner using `claude-opus-4-6` request path.
  - Iterative Anthropic computer-use tool loop (`computer_20251124`) with turn-by-turn `tool_use` -> local execution -> `tool_result`.
  - Legacy planner fallback path removed; execution path is tool-loop only.
  - Tool-loop request guards:
    - request header `anthropic-beta: computer-use-2025-11-24`
    - request tool type `computer_20251124`
  - Screenshot exchange for tool loop:
    - initial desktop screenshot attached in first run turn.
    - post-action screenshots attached in tool results when capture succeeds.
    - implementation uses ScreenCaptureKit for screenshot capture in execution runtime (with a `/usr/sbin/screencapture` fallback).
    - when available, screenshots exclude the “Agent is running” HUD window so it does not appear in images sent to the LLM tool loop.
    - when HUD exclusion is requested, fallback capture that cannot exclude windows is blocked (fail-closed) so the model never receives HUD-visible screenshots.
    - screenshots include the mouse cursor to improve hover/mouse-move grounding for the model.
    - request payload compaction keeps full text/tool history but retains only the latest screenshot image block when sending each turn.
    - screenshot encoding enforces Anthropic's 5 MB limit on the base64 payload (not just raw image bytes), using a base64-safe raw-byte budget before request send.
    - diagnostics now include an in-app LLM screenshot log that previews the exact encoded images sent to the model (initial image + tool-result images).
  - Pre-run desktop preparation:
    - before each execution run, the app hides other regular apps to provide a cleaner visual workspace for the model.
  - Takeover cursor visibility:
    - while the takeover HUD is active, cursor visibility is significantly increased.
    - preferred path is temporary system cursor-size increase with restore on completion/cancellation.
    - fallback path is a large cursor-following halo overlay when system cursor-size writes are blocked.
  - Execution prompt context:
    - execution-agent prompt renders OS version via `{{OS_VERSION}}` placeholder.
  - Tool-loop action execution for baseline action types:
    - open app
    - open URL
    - click
    - right click
    - mouse move
    - cursor position read
    - scroll
    - type text
    - keyboard shortcut
    - wait
    - screenshot action response
    - double click
  - Tool-loop custom tools:
    - `terminal_exec` tool (unrestricted `Process` execution with PATH resolution).
  - Runtime clarification persistence:
    - generated blocking questions are appended into `## Questions` in `HEARTBEAT.md`.
  - Run artifact persistence:
    - each run writes a markdown summary under `runs/` including LLM summary text.
  - OpenAI Responses custom desktop-use loop:
    - added `OpenAIComputerUseRunner` + `OpenAIAutomationEngine` using custom tool schema (`desktop_action`).
    - added prompt folder `Prompts/execution_agent_openai/` (`prompt.md` + `config.yaml`).
    - execution provider routing now prefers OpenAI when OpenAI key exists, with Anthropic fallback.
- Still pending for full locked computer-use design:
  - broader action surface (drag) through tool protocol path.
  - local Xcode runtime validation across multi-app tasks and ambiguous failure paths.

## Execution-agent baseline behavior (locked, revisit-candidate: 2026-02-08)

- Risk confirmation policy:
  - allow all actions without per-step confirmation in current baseline.
- App boundary policy:
  - no allowlist/blocklist in current baseline; run across apps the user asks for.
- Failure retry policy:
  - Desktop-action retries: zero retries (`0`) before generating runtime clarification questions.
  - LLM transport retries: allow a small retry budget with backoff for transient network/TLS failures (so we don't spam `## Questions` on a flaky connection).
- Artifact policy:
  - capture screenshots for failure cases only.
- Execution limits policy:
  - no max step limit and no max run-duration limit in current baseline.
- These are explicitly provisional and tracked for future revision in `.docs/revisits.md`.

## Provider key management UX (locked: 2026-02-08)

- Users can update or remove provider API keys after onboarding from main shell UI (`Provider API Keys` section).
- This settings surface manages keys for:
  - OpenAI
  - Anthropic
  - Gemini
- Saved keys remain non-readable in UI; UI only shows saved/not-saved status.
- All key writes/removals use the same Keychain-backed store as onboarding.

## Recording UX decisions (locked: 2026-02-07)

- During active recording, the app shows a visible red border around the selected display.
- The border is removed immediately when capture stops or fails.
- Capture controls include an in-app microphone source selector with:
  - `System Default Microphone`
  - Explicit input device entries (resolved from system audio devices)
  - `No Microphone`
- Default selection is `System Default Microphone` to keep voice capture enabled by default.
- When microphone capture cannot be started, the app may fall back to no-microphone capture and must show an explicit warning/status message.

## Prompt folder decision (locked: 2026-02-08)

- For each prompt, use one folder under:
  - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Prompts/`
- Each prompt folder must contain:
  - `prompt.md`
  - `config.yaml`
- `config.yaml` must contain at minimum:
  - `version` (prompt version source of truth)
  - `llm` (model/provider target for that prompt)
- Initial prompt implemented with this layout:
  - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Prompts/task_extraction/`
  - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Prompts/execution_agent/`
  - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Prompts/execution_agent_openai/`
- Execution-agent prompt shape decision:
  - use a single prompt template (`prompt.md`) with `{{TASK_MARKDOWN}}` placeholder.
  - do not split execution-agent behavior between hardcoded system/user prompt literals in code.

## Task extraction prompt behavior (locked: 2026-02-08)

- Extraction should be outcome-first and path-flexible:
  - prefer goal + completion checks over rigid click-level replay.
  - treat demonstrated flow as preferred, not mandatory, when equivalent paths are valid.
- Output contract must always include `# Task` and `## Questions`.
- Output must include explicit task-detection flags:
  - `TaskDetected`
  - `Status`
  - `NoTaskReason`
- If no actionable task is present, output a structured no-task result instead of empty or fabricated steps.
- Validation gate before persistence:
  - extraction output must include `# Task`, `## Questions`, `TaskDetected`, `Status`, and `NoTaskReason`.
  - if validation fails, do not overwrite existing `HEARTBEAT.md`.
- Persistence behavior:
  - do not persist control metadata fields (`TaskDetected`, `Status`, `NoTaskReason`) into `HEARTBEAT.md`.
  - if `TaskDetected: false`, do not update existing `HEARTBEAT.md`.

## Gemini extraction adapter behavior (locked: 2026-02-08)

- Provider call flow for task extraction uses Gemini Files API sequence:
  1. Upload init
  2. File upload/finalize
  3. Poll file state until `ACTIVE`
  4. `generateContent` with prompt + uploaded file reference
- Prompt config `llm` remains the source of truth per prompt; runtime currently normalizes `gemini-3-pro` to `gemini-3-pro-preview` for provider compatibility.
- Provider/network failures must surface explicit user-facing error messages in the extraction UI.

## Keychain prompt minimization policy (locked: 2026-02-08)

- Provider key presence checks should avoid repeated per-provider Keychain round-trips at startup.
- `KeychainAPIKeyStore.hasKey` must use a single service-level lookup with in-process caching to reduce repeated OS keychain prompts.
- Secure key read/write behavior is unchanged: values remain in macOS Keychain outside XCTest.
