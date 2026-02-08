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
- Automation scope: web-first (Chrome/web flows) in v1, expand later.
- Scheduler mode: easiest v1 path = run jobs while app is open only (no background helper yet).

## Clarification on question 2 (run policy with open questions)

This means: if the agent still has unresolved questions, should execution stop or continue?

- Option A: block run until user answers all open questions.
- Option B: allow run with warnings, and ask follow-up questions after run.

Current status: pending your explicit choice between A and B.

## Clarification policy (decided)

- After recording analysis, the app sends exactly one round of clarification questions.
- Execution waits until the user answers that round.
- After answers are applied to `HEARTBEAT.md`, execution continues.

## UI clarification decision (locked)

- v1 includes a lightweight in-app chat/Q&A panel for clarification.
- This is not a full messaging product; scope is task clarification only.
- Interaction contract:
  1. System posts one round of clarification questions after recording analysis.
  2. User answers in panel input.
  3. User confirms with `Apply & Continue`.
  4. App writes answers into `HEARTBEAT.md` and unblocks execution.

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

## Recording UX decisions (locked: 2026-02-07)

- During active recording, the app shows a visible red border around the selected display.
- The border is removed immediately when capture stops or fails.
- Capture controls include an in-app microphone source selector with:
  - `System Default Microphone`
  - Explicit input device entries (resolved from system audio devices)
  - `No Microphone`
- Default selection is `System Default Microphone` to keep voice capture enabled by default.
- When microphone capture cannot be started, the app may fall back to no-microphone capture and must show an explicit warning/status message.

## Prompt management decisions (locked: 2026-02-08)

- Prompt source of truth is file-based under:
  - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Prompts/`
- Prompts are immutable by version:
  - each prompt family has version folders (`v1.0.0`, `v1.1.0`, etc.).
  - old versions are never edited in-place.
- Prompt resolution is alias-based:
  - aliases like `stable` and `canary` map to concrete versions.
  - alias mapping is defined in a single registry file and can be updated without code edits.
- Prompt composition is provider-agnostic:
  - canonical prompt parts are `system`, `user`, and optional `output schema`.
  - provider adapters transform canonical prompt parts to provider-specific request payloads.
- Structured output contract is version-bound:
  - each prompt version owns its output schema and parser expectations.
  - parse/validation failures must fail fast and must not write partial `HEARTBEAT.md` updates.
- Observability requirement:
  - each LLM run must capture prompt metadata (`prompt_id`, `prompt_version`, `provider`, `model`) in run diagnostics.
