---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Step 4 execution agent (active, highest priority).
2. Why now: User explicitly prioritized execution-agent delivery as the most important milestone.
3. Code tasks:
   - Keep implemented baseline stable:
     - `Run Task` is wired to provider-routed `AutomationEngine` with explicit execution-provider selection (`OpenAI` or `Anthropic`).
     - runtime clarifications append into `## Questions`.
     - run summaries persist under `runs/`.
     - execution-agent prompt is loaded from `Prompts/execution_agent/prompt.md` + `config.yaml` (single template prompt).
   - Keep explicit execution-provider toggle behavior stable:
     - provider selection is persisted across relaunch.
     - selected provider is used directly at run time (no implicit fallback).
     - missing selected-provider key surfaces a clear switch/save error.
   - Keep iterative Anthropic computer-use loop (`computer_20251124`) stable for turn-based screenshot/tool execution.
     - Request-format guardrail: `claude-opus-4-6` is model id; `computer_20251124` is tool type; use beta header `computer-use-2025-11-24` on tool-loop calls.
     - keep execution path tool-loop only (no planner fallback path).
   - Include host OS version string in the execution-agent prompt (via `{{OS_VERSION}}` placeholder). (Implemented)
   - Add a custom `terminal_exec` tool to the execution tool loop for unrestricted terminal command execution (absolute-path or PATH-resolved executables). (Implemented)
   - Keep mouse cursor visible in LLM screenshots to improve hover/mouse-move task reliability. (Implemented)
   - Ensure LLM screenshots never include the “Agent is running” HUD by failing closed when exclusion-capable capture is unavailable. (Implemented)
   - Keep full text/tool history but send only the latest screenshot image block per LLM turn to control payload size growth. (Implemented)
   - Enforce terminal-vs-computer boundary at runtime (block UI/visual terminal commands and redirect to `computer`). (Implemented)
   - Before each run, hide other regular apps to provide a cleaner screen for the agent. (Implemented)
   - Ensure screenshots sent to Anthropic stay under the 5 MB base64 image limit (raw-byte budgeting + JPEG re-encode fallback for retina screenshots). (Implemented)
   - Expose model-visible screenshots in Diagnostics so users can review the exact images sent to Anthropic. (Implemented)
   - While agent takeover is active, significantly increase cursor visibility and restore/remove it when the run ends/cancels (including early monitor-start failure):
     - preferred path: temporary system cursor-size increase.
     - fallback path: large cursor-following halo overlay when macOS blocks cursor-size writes.
     (Implemented)
   - Keep execution-agent prompt aligned with takeover cursor visualization so the model treats larger cursor/halo as pointer presentation (not actionable UI). (Implemented)
   - Expand action coverage through tool-loop path (scroll/right-click/move/cursor_position implemented; drag and richer UI control still pending).
   - Fix tool schema parsing for `computer_20251124` tool inputs:
     - accept click coordinates in the model-returned schema (top-level `x`/`y` and `coordinate: [x,y]` / nested position fields). (Implemented)
     - add coordinate scaling/translation layer if screenshot coordinates don’t match CGEvent coordinate space. (Partially implemented: Retina logical-vs-capture pixel mismatch fixed via CGDisplayBounds mapping; multi-display/origin validation still pending)
   - Fix keyboard shortcut injection reliability:
     - handle special keys like `space`.
     - improve text typing reliability for system UI targets (Spotlight, etc.) by using clipboard-paste typing with clipboard restore (cmd+v).
     - reduce dependence on AppleScript `System Events` where possible. (Implemented for shortcuts and typing via CGEvent; AppleScript fallback remains for unknown keys)
   - Add loop guardrails to avoid “stuck tool_use spam”:
     - after N repeated invalid tool inputs, stop and append a blocking question into `## Questions` in `HEARTBEAT.md`.
   - Keep unresolved runtime-question generation on ambiguity/failure and persist to `HEARTBEAT.md`.
   - Implement current baseline policies:
     - allow run with unresolved questions and ask clarifications from run report.
     - no deterministic local action-plan synthesis; model tool calls are the only action authority.
     - desktop actions: zero retries before generating clarification questions (transport/network retries are allowed).
     - no per-step confirmation gates and no app allowlist/blocklist.
     - failure-only screenshot artifacts and no max step/runtime limits.
   - Keep provisional choices tracked in `.docs/revisits.md`.
   - Keep run status surfaced in task detail.
4. Automated tests:
   - Keep passing:
     - Anthropic tool-loop API-key gating/request-format tests.
     - automation-engine outcome tests (`success`/`needs clarification`/`failed`).
     - run-trigger persistence tests (heartbeat question writeback + run-summary writes).
     - iterative tool-loop parser/execution smoke checks.
     - provider-routing tests for explicit selected-provider behavior (`OpenAI`/`Anthropic`/missing-key failure). (Implemented)
     - state-store selection persistence test for execution-provider toggle. (Implemented)
   - Markdown runtime-question append/dedup tests.
   - Add richer tool-action integration tests (drag and multi-display coordinate/origin cases; scroll/right-click/move are covered).
   - Add tests for `terminal_exec` tool definition + dispatch (PATH resolution + stdout/stderr capture). (Implemented)
   - Keep coverage for `cursor_position` tool action mapping + payload return format. (Implemented)
   - Keep coverage for latest-image-only request compaction and visual terminal-command rejection. (Implemented)
   - Keep coverage for base64 image-size budget math (encoded 5 MB limit). (Implemented)
   - Keep coverage for LLM screenshot-log emission (initial + tool-result captures). (Implemented)
   - Keep state-store coverage for desktop preparation before run start. (Implemented)
   - Keep state-store coverage for takeover cursor-size activation/restoration paths. (Implemented)
   - Add tool-input parsing tests for:
     - click coordinate schema variants (array/nested/top-level)
     - key schema variants (`key` vs `text`) and special keys like space
   - Add tests for loop guardrails (stop after repeated invalid tool inputs).
5. Manual tests:
   - Run at least one real task and verify desktop actions occur.
   - While the run is executing:
     - confirm `Diagnostics (LLM + Screenshot) -> Execution Trace` shows `tool_use` entries and local action entries (click/type/open/wait).
     - if no `tool_use` entries appear, the model is returning text-only completion; adjust the execution-agent prompt accordingly.
   - In `Diagnostics`, click `Copy Trace` and paste into Notes/Terminal to confirm clipboard formatting is readable.
   - Click `Stop` during an active run and confirm:
     - status becomes `Run cancelled.`
     - no new questions are appended into `HEARTBEAT.md` for the cancelled run.
   - While the run is executing, confirm:
     - a centered "Agent is running" overlay is visible.
     - pressing `Escape` cancels the run and the overlay disappears.
     - cursor visibility is visibly larger while takeover is active (larger cursor or halo overlay).
     - model behavior is not distracted by cursor-visibility halo (continues acting on real UI targets).
   - Confirm clicking `Run Task` minimizes the app window immediately (agent overlay remains visible).
   - Confirm cursor visibility enhancement is removed after run completion/cancellation.
   - Confirm the model can use `terminal_exec` to open an app (example command: `open -a "Google Chrome"`).
   - Confirm Diagnostics -> `LLM Screenshots` matches what the model received during the run.
   - In `Provider API Keys`, switch execution provider between `OpenAI` and `Anthropic` and confirm:
     - selected value persists after relaunch.
     - run path follows selected provider.
     - if selected provider key is missing, run fails with explicit save/switch guidance.
   - Temporarily revoke Screen Recording, Accessibility, or Input Monitoring permission and confirm clicking `Run Task`:
     - triggers a permission prompt (or opens System Settings)
     - does not start a run until permissions are granted
   - Validate ambiguity/failure writes blocking questions to `HEARTBEAT.md`.
   - Answer generated question and rerun to confirm progression.
6. Exit criteria: First execution-agent baseline can run a task, generate blocking questions when needed, and persist outcomes.

1. Step: Keep `OI-2026-02-08-003` open (deferred clarification-panel local verification).
2. Why now: Clarification UI verification is deferred while execution-agent milestone is in progress.
3. Code tasks:
   - Keep clarification parser/apply behavior unchanged during Step 4 execution-agent work.
   - Preserve regression tests for question parsing and markdown apply.
4. Automated tests:
   - Keep `HeartbeatQuestionService` tests passing.
   - Keep `MainShellStateStore` clarification persistence tests passing.
5. Manual tests:
   - Deferred by decision; do not run now.
6. Exit criteria: Issue remains tracked until deferred local verification is executed and confirmed.

1. Step: Defer `OI-2026-02-07-001` microphone selection bug (backlog).
2. Why now: Mitigation remains available via `System Default Microphone`; execution-agent baseline has higher delivery priority.
3. Code tasks:
   - Keep current mitigation and fallback messaging unchanged.
   - Resume mic diagnostics after Step 4 execution-agent baseline lands.
4. Automated tests: N/A (deferred backlog item).
5. Manual tests: N/A (deferred backlog item).
6. Exit criteria: Issue remains tracked in `.docs/open_issues.md` with mitigation and clear next action.

1. Step: Track `OI-2026-02-09-004` prompt resource-collision issue (deferred).
2. Why now: Anthropic execution runner is unblocked via embedded prompt; prompt file-packaging fix is a secondary concern after core computer-use loop.
3. Code tasks:
   - Keep execution-agent prompt embedded while current Xcode resource collision persists.
   - Design and implement prompt resource namespacing for multiple prompt folders.
4. Automated tests:
   - Build/test validation after namespacing fix to confirm no duplicate resource outputs.
5. Manual tests:
   - Add a second prompt folder with `prompt.md` and `config.yaml`, then verify project builds without collisions.
6. Exit criteria: Multiple prompt folders can coexist with required filenames and build cleanly.

1. Step: Step 5 scheduling while app is open (next, after Step 4 baseline).
2. Why now: Scheduling depends on a reliable execution-agent run path.
3. Code tasks:
   - Add natural-language schedule input and deterministic validation.
   - Persist schedule config per task and show `next run` and `last run` in task detail.
   - Wire scheduler trigger path while app is open and write run history updates.
4. Automated tests:
   - Schedule parser validation tests.
   - Scheduler trigger/deduplication tests.
   - State-store tests for schedule persistence and status projection (`next run`/`last run`).
5. Manual tests:
   - Configure short interval and verify scheduled run triggers while app is open.
   - Restart app and verify schedule reload behavior.
   - Confirm task detail status updates after at least one scheduled fire.
6. Exit criteria: At least one task runs successfully on schedule with correct status updates.
