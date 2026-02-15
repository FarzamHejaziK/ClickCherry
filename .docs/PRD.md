---
description: Product requirements for a fully native macOS desktop app that learns tasks across desktop apps from recordings, asks clarifications, and runs scheduled local automations
---

# PRD: Fully Native macOS Task Agent

## Product Summary

Build a fully native macOS desktop app (Swift/SwiftUI) that lets users teach tasks by recording workflows across any desktop app, automatically generates a detailed task spec, asks clarifying questions, and executes scheduled task runs locally.

## Problem

Users want to automate repetitive desktop work without coding and without managing fragile infrastructure. Current setup friction (gateway/runtime coupling, app reliability, permissions complexity) slows experimentation. We need a native, focused macOS experience with a local-first execution model.

## Vision

Users demonstrate a task once, confirm missing details through a question loop, and trust the app to run the task repeatedly on schedule from their Mac.

## Goals

1. Native macOS-first UX for task creation, review, and execution.
2. Desktop app automation scope in v1 (browser included, not browser-only).
3. Local-only data and execution by default.
4. Per-task agent ownership (one task agent per task).
5. Reliable scheduled runs while app is open (always-on mode later).

## Non-Goals (v1)

1. Cross-platform support (Windows/Linux).
2. Cross-platform desktop automation beyond macOS.
3. Cloud execution or managed backend service.
4. "No-human-ever" operation for protected flows (captcha/MFA/passkeys).

## Target Users

1. Individual power users automating repeated desktop tasks.
2. Users who prefer local execution and private data storage.

## Core Use Cases

1. Create task from desktop workflow recording.
2. Continue/refine an existing task.
3. Run now and run on schedule.
4. Review run history and resolve pending questions.

## Primary User Flows

## Flow A: New Task

1. User clicks `New Task`.
2. User records workflow (upload/import `.mp4` in early versions; direct in-app capture later).
3. App creates a dedicated task agent + workspace.
4. LLM extracts detailed task instructions into `HEARTBEAT.md`.
5. App surfaces unresolved questions under `## Questions`.
6. User answers questions and sets schedule in natural language.
7. Task becomes active; first run can be manual or scheduled.

## Flow B: Existing Task

1. User opens task list and selects a task.
2. App shows status: pending questions, last run, next run, latest outcome.
3. User can edit task markdown, answer questions, or attach follow-up recording.
4. Task agent runs with warnings if questions remain unresolved.

## Functional Requirements

## Task/Agent Model

1. One task = one task agent.
2. Task agent owns task spec, recordings, questions, run history.
3. No global "main task owner" for task lifecycle.

## Recording + Understanding

1. Accept desktop workflow recording as `.mp4`.
2. Run video understanding to generate:
   - `# Task`
   - `## Questions`
3. Preserve details; avoid over-summarization.

## Clarification Loop

1. Detect ambiguity/missing variables.
2. Persist unresolved and resolved questions in task file.
3. Allow follow-up recording to refine existing task.

## Execution

1. Replay desktop app action sequence by intent (not pixel replay).
2. Track execution steps and failures.
3. Save run artifacts and result summary under task workspace.

## Scheduling

1. User enters schedule in natural language.
2. App converts to scheduler format (cron-like).
3. Run jobs locally while app is open in v1.
4. Optional future background daemon mode for closed-app execution.

## Status + Observability

1. Task list with health indicators.
2. Task detail view with:
   - pending questions count
   - last run
   - next run
   - warning/error state
3. Per-run logs and summary.

## Non-Functional Requirements

1. Privacy: task data local by default.
2. Reliability: retries + deterministic step state checks.
3. Safety: v1 execution baseline allows autonomous actions without per-step confirmation; approval gates for risky/destructive actions are deferred and tracked for revisit.
4. Performance: responsive UI during long-running jobs.
5. Robustness on managed macOS devices with constrained permissions.

## Data Model and Storage

Task workspace layout:

1. `HEARTBEAT.md` (canonical task spec + questions).
2. `recordings/` (source recordings).
3. `runs/` (run logs + summaries + artifacts).

Security:

1. API keys in Keychain or secure local config.
2. No plaintext secret leakage in run logs.

## UX Requirements

## Screens (v1)

1. Task List
2. New Task (record/upload)
3. Task Review (generated task + questions)
4. Schedule Setup
5. Task Detail + Run History

## UX Principles

1. Keep setup linear and explicit.
2. Show what the agent inferred before enabling schedule.
3. Keep unresolved questions visible and actionable.

## Technical Architecture (Native-First)

1. Frontend: SwiftUI app.
2. Runtime: native execution engine in app process for v1.
3. LLM layer: direct provider HTTP calls from Swift (provider adapters).
   - Execution (agentic runs): OpenAI.
   - Recording understanding (task extraction): Gemini (`gemini-3-flash-preview`).
4. Scheduler: in-app scheduler for "while-open" jobs.
5. Automation layer:
   - v1: app-agnostic desktop action execution for common workflows.
   - v2: deeper coverage for protected/specialized app surfaces.

## Dependencies and Integrations

1. LLM provider(s) for video understanding and clarifications.
2. Desktop automation hooks/runtime.
3. macOS permissions: Screen Recording, Accessibility, Input Monitoring (Escape-stop takeover), Microphone (voice capture during screen recording).

## Risks and Mitigations

1. UI drift across apps breaks replay.
   - Mitigation: resilient locators + fallback matching + question prompts.
2. Managed-device restrictions block permissions.
   - Mitigation: explicit preflight checks + graceful degraded mode.
3. LLM output quality inconsistency.
   - Mitigation: strict output schema + post-processing validators.
4. Scheduler reliability when app closed.
   - Mitigation: declare v1 behavior clearly; add daemon mode later.

## Success Metrics

1. Time to first automated run.
2. Task run success rate.
3. Number of unresolved questions per task over time.
4. Reduction in manual task effort.

## Rollout Plan

## Phase 1: Native MVP (Desktop Recording Import)

1. Create task from `.mp4`.
2. Generate `HEARTBEAT.md` with Task + Questions.
3. Manual run + basic scheduled run while app open.

## Phase 2: Clarification and Reliability

1. Follow-up recordings for task refinement.
2. Better run diagnostics and recovery.
3. Improved question management UI.

## Phase 3: Always-On and Expanded Automation

1. Optional background daemon for closed-app scheduling.
2. Expanded desktop automation scope beyond browser flows.

## Open Questions

1. What minimum desktop automation fidelity is required for v1 success?
2. Should task editing remain free-form markdown or move to structured editor?
3. When to introduce background daemon mode relative to user demand?

## Clarification UX Addendum (v1 locked)

1. After recording analysis, the app opens an in-app Q&A panel (chat-style interaction).
2. The app sends one round of clarification questions.
3. Execution is allowed with warnings even when clarification questions remain unresolved.
4. Clarification follow-ups can be requested after run completion/report.
5. Answers are applied to `HEARTBEAT.md` for subsequent runs.
6. v1 requires this panel in task setup flow and task detail view.

## Platform and Limits Addendum (v1 locked)

1. Minimum supported macOS: 14 (Sonoma).
2. Recording ingestion limits:
   - maximum file size: 2 GB
   - maximum duration: 5 minutes
3. If limits are exceeded, app shows actionable guidance to trim or re-record.

## Provider Onboarding Addendum (v1 locked)

1. First-run setup asks users to provide model API keys.
2. Required onboarding providers:
   - OpenAI for core task execution/reasoning (v1 execution provider is OpenAI only).
   - Gemini for video-understanding flow.
3. Keys are stored in macOS Keychain and never written to plaintext logs.
