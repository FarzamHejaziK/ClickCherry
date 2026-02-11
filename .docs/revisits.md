---
description: Provisional decisions and open product/design questions that are intentionally deferred for future revision.
---

# Revisits

## Usage

- Add a new entry whenever we intentionally choose a temporary baseline.
- When an item is revised, update `Status`, `Resolution Date`, and linked docs.
- Keep newest active revisit items first.

## Revisit RV-2026-02-11-015
- Revisit ID: RV-2026-02-11-015
- Source: Step 4 execution runner (`AnthropicComputerUseRunner` / `terminal_exec`)
- Status: Open
- Current Baseline: `terminal_exec` is unrestricted (no executable allowlist; absolute-path and PATH-resolved execution both allowed).
- Why Revisit: Full terminal power increases risk of destructive commands; policy-level safety boundaries are intentionally deferred by current product direction.
- Trigger To Revisit: When product/safety policy requires guardrails, or if misuse/incident data indicates restrictions are needed.
- Owner: Engineering + product
- Last Updated: 2026-02-11

## Revisit RV-2026-02-10-014
- Revisit ID: RV-2026-02-10-014
- Source: Step 4 execution runner (`AnthropicComputerUseRunner` / `terminal_exec`)
- Status: Closed
- Current Baseline: `terminal_exec` no longer uses a hard-coded allowlist.
- Why Revisit: Initial implementation intentionally constrained executable set.
- Trigger To Revisit: N/A (resolved).
- Owner: Engineering
- Last Updated: 2026-02-11
- Resolution Date: 2026-02-11
- Resolution Summary: Switched `terminal_exec` to unrestricted execution with absolute-path + PATH-based executable resolution.

## Revisit RV-2026-02-09-013
- Revisit ID: RV-2026-02-09-013
- Source: Step 4 iterative computer-use implementation (`AnthropicAutomationEngine`)
- Status: Closed
- Current Baseline: Execution-loop screenshots are captured via ScreenCaptureKit (nominal resolution) with optional HUD-window exclusion; `/usr/sbin/screencapture` is retained as a fallback only.
- Why Revisit: Process-based capture added a runtime dependency and prevented excluding in-app HUD overlays from LLM screenshots.
- Trigger To Revisit: N/A (resolved).
- Owner: Engineering
- Last Updated: 2026-02-10
- Resolution Date: 2026-02-10
- Resolution Summary: Implemented ScreenCaptureKit-based screenshot capture in `DesktopScreenshotService` and wired HUD window exclusion for the tool-loop screenshot provider.

## Revisit RV-2026-02-09-012
- Revisit ID: RV-2026-02-09-012
- Source: Step 4 implementation note in `.docs/worklog.md`
- Status: Open
- Current Baseline: Execution and extraction prompts are file-based (`prompt.md` + `config.yaml`) and loaded via `PromptCatalogService`; Xcode build excludes prompt files from auto resource copy to avoid flattened-name collisions.
- Why Revisit: Current mitigation depends on source-path prompt discovery in debug/local builds; production-grade bundle packaging for prompts is not finalized.
- Trigger To Revisit: When implementing production prompt asset packaging that preserves per-folder prompt structure in app bundle.
- Owner: Engineering
- Last Updated: 2026-02-09

## Revisit RV-2026-02-08-011
- Revisit ID: RV-2026-02-08-011
- Source: `.docs/open_issues.md` (`OI-2026-02-07-001`)
- Status: Open
- Current Baseline: Explicit mic selection fallback remains; use `System Default Microphone`.
- Why Revisit: Explicit device routing fails in some local runs.
- Trigger To Revisit: After Step 4 execution-agent baseline is stable.
- Owner: Codex + user validation
- Last Updated: 2026-02-08

## Revisit RV-2026-02-08-010
- Revisit ID: RV-2026-02-08-010
- Source: `.docs/open_issues.md` (`OI-2026-02-08-003`)
- Status: Open
- Current Baseline: Step 4 clarification local UI verification is deferred.
- Why Revisit: Runtime persistence behavior still needs local confirmation pass.
- Trigger To Revisit: After Step 4 execution-agent baseline implementation.
- Owner: Codex + user validation
- Last Updated: 2026-02-08

## Revisit RV-2026-02-08-009
- Revisit ID: RV-2026-02-08-009
- Source: `.docs/PRD.md` (`Open Questions`)
- Status: Open
- Current Baseline: No background daemon in v1; app-open scheduler only.
- Why Revisit: Product needs may require closed-app scheduling.
- Trigger To Revisit: After stable v1 scheduled-run metrics are available.
- Owner: Product + engineering
- Last Updated: 2026-02-08

## Revisit RV-2026-02-08-008
- Revisit ID: RV-2026-02-08-008
- Source: `.docs/PRD.md` (`Open Questions`)
- Status: Open
- Current Baseline: `HEARTBEAT.md` remains free-form markdown editor.
- Why Revisit: Structured editor may improve reliability and validation.
- Trigger To Revisit: After execution-agent and scheduling flows stabilize.
- Owner: Product + engineering
- Last Updated: 2026-02-08

## Revisit RV-2026-02-08-007
- Revisit ID: RV-2026-02-08-007
- Source: `.docs/PRD.md` (`Open Questions`)
- Status: Open
- Current Baseline: No explicit minimum automation-fidelity threshold is locked.
- Why Revisit: Need a measurable v1 success threshold for run reliability.
- Trigger To Revisit: When enough run-history data exists to set KPI threshold.
- Owner: Product + engineering
- Last Updated: 2026-02-08

## Revisit RV-2026-02-08-006
- Revisit ID: RV-2026-02-08-006
- Source: `.docs/design.md` (`Execution-agent baseline behavior`)
- Status: Open
- Current Baseline: No max step limit and no max run-duration limit.
- Why Revisit: Unlimited runs can increase runaway-risk and resource usage.
- Trigger To Revisit: First observed runaway/looping run or safety hardening phase.
- Owner: Engineering
- Last Updated: 2026-02-08

## Revisit RV-2026-02-08-005
- Revisit ID: RV-2026-02-08-005
- Source: `.docs/design.md` (`Execution-agent baseline behavior`)
- Status: Open
- Current Baseline: Screenshot artifacts are captured on failures only.
- Why Revisit: May be insufficient for debugging successful-but-wrong runs.
- Trigger To Revisit: If run diagnostics are insufficient in user bug reports.
- Owner: Engineering
- Last Updated: 2026-02-08

## Revisit RV-2026-02-08-004
- Revisit ID: RV-2026-02-08-004
- Source: `.docs/design.md` (`Execution-agent baseline behavior`)
- Status: Open
- Current Baseline: Retry policy is `0` retries before asking clarification questions.
- Why Revisit: Zero retries may increase unnecessary clarification churn.
- Trigger To Revisit: If repeated transient failures generate excessive questions.
- Owner: Engineering
- Last Updated: 2026-02-08

## Revisit RV-2026-02-08-003
- Revisit ID: RV-2026-02-08-003
- Source: `.docs/design.md` (`Execution-agent baseline behavior`)
- Status: Open
- Current Baseline: No app allowlist/blocklist; execute across apps user requests.
- Why Revisit: Safety policy may require app boundaries for destructive contexts.
- Trigger To Revisit: Security review or first high-risk misuse report.
- Owner: Product + engineering
- Last Updated: 2026-02-08

## Revisit RV-2026-02-08-002
- Revisit ID: RV-2026-02-08-002
- Source: `.docs/design.md` (`Execution-agent baseline behavior`)
- Status: Open
- Current Baseline: No per-step confirmations; all actions are allowed by default.
- Why Revisit: Safety controls may be required for irreversible actions.
- Trigger To Revisit: Safety hardening phase or first risky-action incident.
- Owner: Product + engineering
- Last Updated: 2026-02-08

## Revisit RV-2026-02-08-001
- Revisit ID: RV-2026-02-08-001
- Source: `.docs/design.md` (`Run policy with open questions`)
- Status: Open
- Current Baseline: Allow run with unresolved questions; ask clarifications when run report is ready.
- Why Revisit: May trade reliability for speed depending on task class.
- Trigger To Revisit: If unresolved-question runs materially reduce success rate.
- Owner: Product + engineering
- Last Updated: 2026-02-08
