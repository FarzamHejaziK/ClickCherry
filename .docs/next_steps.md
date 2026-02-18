---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Release notarization reliability hardening for transient GitHub runner network drops (completed in workflow, pending run confirmation).
2. Why now: Recent release run stayed `In Progress` for hours and failed with `NSURLErrorDomain -1009` while waiting on notary status.
3. Code tasks:
   - Replace `xcrun notarytool submit --wait` with:
     - submit + capture submission ID (Completed).
     - explicit status polling with retry on transient network failures (Completed).
     - bounded wait timeout and explicit invalid/rejected log handling (Completed).
     - timestamp + elapsed-time logging per poll for easier queue/runtime diagnosis (Completed).
   - Validate next release tag run completes notarization with the new flow. (In progress)
4. Automated tests:
   - `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "release.yml ok"'` (pass on 2026-02-18 local run).
5. Manual tests:
   - Manual workflow review:
     - confirm submission ID is persisted via `GITHUB_ENV`.
     - confirm polling retries `NSURLErrorDomain -1009`/offline errors.
     - confirm accepted/invalid/rejected/timeout paths are explicit. (Completed)
6. Exit criteria: A release workflow run completes with notarization accepted under the new submit+poll flow; transient network blips no longer cause immediate failure.

1. Step: CI-local parity verification with CI command shape (completed).
2. Why now: Recent CI failures needed reproducible local evidence using the same `xcodebuild` flags and target selection as `.github/workflows/ci.yml`.
3. Code tasks:
   - Keep local verification commands aligned to CI:
     - build: `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-build CODE_SIGNING_ALLOWED=NO build` (Completed locally)
     - tests: `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (Completed locally)
   - Added deterministic test fixes for:
     - `GeminiVideoLLMClientTests.analyzeVideoUploadsPollsAndGeneratesExtractionOutput`
     - `MainShellStateStoreTests.extractFromFinishedRecordingCreatesTaskOnlyAfterExtractionReturns` (Completed locally)
   - Rerun GitHub CI and compare runner `.xcresult` with local logs only if failures persist. (In progress)
   - Keep `extractFromFinishedRecordingCreatesTaskOnlyAfterExtractionReturns` on time-based wait helper (`Task.sleep` polling) to avoid yield-scheduler flake regressions. (Completed locally)
4. Automated tests:
   - Build command above (pass on 2026-02-17 local run).
   - Test command above (pass on 2026-02-17 local run).
5. Manual tests:
   - N/A (command parity + log verification task).
6. Exit criteria: CI and local use identical command shape, deterministic local failures are addressed, and the next GitHub CI run confirms green.

1. Step: Open-source baseline rollout and launch hardening (active).
2. Why now: The repository now has a concrete OSS strategy (MIT + DCO + owner review authority) and needs immediate launch-ready follow-through.
3. Code tasks:
   - Configure GitHub branch protection to require PRs, passing checks (`CI`, `DCO`), and owner/code-owner review. (Pending)
   - Configure release signing/notarization secrets and wire signed artifact steps in release workflow. (Pending)
   - Publish initial launch issues/labels (`good first issue`, `help wanted`, `documentation`). (Pending)
   - Keep `/docs/` contributor guides current as onboarding/release flows evolve. (In progress)
   - Keep `/.docs/open_source.md` as the strategy source of truth for OSS decisions and tradeoffs. (In progress)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-oss-baseline -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - Review `/README.md` and `/docs/*` as a new contributor and confirm setup/release/contribution flow is clear.
   - Review governance and policy docs (`/CONTRIBUTING.md`, `/GOVERNANCE.md`, `/SECURITY.md`) for consistency with the locked strategy.
6. Exit criteria: Repo can accept external PRs with clear governance, contribution process, and release documentation; pending secrets/branch rules are explicitly tracked.

1. Step: UI/UX: New Task recording controls (multi-display + mic + Escape-to-stop) (active).
2. Why now: User wants `New Task` to show available displays only when multiple displays exist, allow microphone selection, and keep the UI out of the way while still being easy to stop (Escape + HUD).
3. Code tasks:
   - Show display picker under `Start recording` only when multiple displays are available. (Implemented)
   - Start capture hides the main app windows after capture begins (desktop stays clear). (Implemented)
   - Stop capture restores the app windows and focuses the app again (Escape stop matches Stop button flow). (Implemented)
   - Show microphone selection under `New Task` only when multiple microphone devices are available. (Implemented)
   - Fix explicit microphone selection so recording stop succeeds (avoid `Capture audio device <id> not found`). (Implemented)
   - Ensure the red border overlay appears on the selected display (display ordering matches `screencapture -D`). (Implemented)
   - Add a transparent HUD during recording that says `Press Escape to stop recording`. (Implemented)
   - Ensure the recording HUD is not captured into the saved recording output. (Implemented)
   - Support Escape-to-stop for recording; only hide the app UI when Escape monitoring starts successfully. (Implemented)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-recording-esc-micfix CODE_SIGNING_ALLOWED=NO build`
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-recording-esc-micfix-tests -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - Runtime: with 2+ displays connected, open `New Task` and confirm the display picker appears and selecting `Display 1/2/...` changes the display that gets the red border overlay (including non-main displays positioned left/below the main display).
   - Runtime: with only 1 display connected, confirm the picker is not shown.
   - Runtime: with 2+ microphone devices available, confirm the microphone dropdown appears and selecting a non-default mic:
     - records with microphone audio.
     - stops cleanly and saves a `.mov` (no `Capture audio device ... not found` error).
   - Runtime: click record on `New Task` and confirm:
     - the app window hides immediately after capture starts (when Escape monitoring starts), even if the app window is on a secondary display.
     - a transparent HUD appears that says `Press Escape to stop recording`.
     - the HUD does not appear inside the saved `.mov` output.
     - pressing Escape stops recording, restores/focuses the app, and navigates to the new task detail view.
6. Exit criteria: `New Task` stays minimal while allowing multi-display + mic selection when needed; recording hides the app UI during capture; and pressing Escape stops recording and restores the app (same as Stop).

1. Step: UI/UX: Permissions Preflight panel (modern) (pending manual confirmation).
2. Why now: User wants the Permissions step to match the new modern onboarding style, with careful alignment and no icon focus.
3. Code tasks:
   - Redesign Permissions Preflight into a single glass panel with aligned rows and consistent button columns. (Implemented)
   - Remove the hero/app-icon illustration from Permissions (no icon focus on this step). (Implemented)
   - Remove `Check Status` buttons; keep status pills updated automatically (polling) and rely on `Open Settings` as the primary action. (Implemented)
   - Remove the Automation permission row (no longer required). (Implemented)
   - Add Microphone permission to support screen recordings with voice. (Implemented)
   - Add `Skip` to the Permissions footer (matches Provider Setup). (Implemented)
   - Remove the Testing shortcut panel (Skip covers bypass). (Implemented)
   - Update Input Monitoring copy to clarify it is only used to detect `Escape` for stopping a run. (Implemented)
   - Validate spacing/alignment in Canvas and tune if needed. (Pending user-side confirmation)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-permissions-mic-noskiptestpanel CODE_SIGNING_ALLOWED=NO build`
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-permissions-mic-noskiptestpanel-tests -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - In Xcode Canvas, open `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Previews/RootViewPreviews.swift`, select `Startup - Permissions`, and confirm:
      - rows have consistent alignment and button columns line up.
      - there are no `Check Status` buttons.
      - `Open Settings` stays aligned (does not shift) across `Granted` vs `Not Granted` status-pill widths.
       - no hero/app icon appears on this step.
       - there is no Automation row.
       - Microphone (Voice) appears.
       - `Skip` is available in the footer.
       - there is no Testing shortcut panel.
6. Exit criteria: Permissions Preflight matches the redesign direction and looks visually aligned (no per-row drift).

1. Step: UI/UX: Provider Setup panel (OpenAI + Gemini) (pending manual confirmation).
2. Why now: Provider Setup is part of the same onboarding redesign and still needs local Canvas confirmation for alignment.
3. Code tasks:
   - Limit onboarding Provider Setup to OpenAI + Gemini only. (Implemented)
   - Keep Provider Setup as a single glass panel with consistent row alignment. (Implemented)
   - Align provider logos with the left edge of the API key input fields. (Implemented)
   - Add Keychain storage note (keys are stored locally and only used to authenticate provider API requests). (Implemented)
   - Remove onboarding `Remove` buttons; Save/Update only. (Implemented)
   - Keep `Skip` in the footer for Provider Setup. (Implemented)
   - Remove the warning line below the Provider Setup panel (Skip covers bypass). (Implemented)
   - Validate spacing/alignment in Canvas and tune if needed. (Pending user-side confirmation)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-provider-keychain-copy2 CODE_SIGNING_ALLOWED=NO build`
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-provider-keychain-copy2-tests -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - In Xcode Canvas, open `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Previews/RootViewPreviews.swift`, select `Startup - Provider Setup`, and confirm:
      - Save/Update aligns with the status pill.
     - provider logos align with the left edge of the API key fields.
     - Keychain storage note appears under the subtitle.
     - only OpenAI and Gemini are present.
     - no warning line appears below the panel.
     - `Skip` appears in the footer.
6. Exit criteria: Provider Setup matches the redesign direction and looks visually aligned (no per-row drift).

1. Step: Code health: Split large view files into per-page subviews (completed).
2. Why now: `MainShellView.swift` and `OnboardingFlowView.swift` were getting too large; splitting by page reduces merge conflicts and makes UI iteration faster.
3. Code tasks:
   - Split main shell into sidebar + per-page views (`New Task`, `Task`, `Settings`) and move `VisualEffectView` to a shared file. (Implemented)
   - Split onboarding into shared components + per-step pages (`Welcome`, `Provider Setup`, `Permissions`, `Ready`). (Implemented)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-refactor-pages CODE_SIGNING_ALLOWED=NO build`
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-refactor-pages-tests -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - In Xcode Canvas, re-check `Startup - Welcome/Provider Setup/Permissions/Ready` and `MainShell - New Task/Settings` previews render. (Pending user-side confirmation)
6. Exit criteria: No behavior changes; compilation/tests remain green with smaller files.

1. Step: UI/UX documentation baseline (completed, docs-only).
2. Why now: UI/UX changes need a single source-of-truth log that explicitly follows plan and design decisions.
3. Code tasks:
   - Added `/Users/farzamh/code-git-local/task-agent-macos/.docs/ui_ux_changes.md`.
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/AGENTS.md` with required UI/UX change logging/alignment rules.
4. Automated tests:
   - N/A (docs-only).
5. Manual tests:
   - N/A (docs-only).
6. Exit criteria: UI/UX governance instructions and canonical log exist and are ready for future UI changes.

1. Step: Step 4 execution agent (active, highest priority).
2. Why now: User explicitly prioritized execution-agent delivery as the most important milestone.
3. Code tasks:
   - Keep implemented baseline stable:
     - `Run Task` is wired to OpenAI execution (`OpenAIAutomationEngine` / `OpenAIComputerUseRunner`) (no provider routing in v1 UI).
     - runtime clarifications append into `## Questions`.
     - run summaries persist under `runs/`.
     - execution-agent prompt is loaded from `Prompts/execution_agent_openai/prompt.md` + `config.yaml`.
     - app branding baseline is set to `ClickCherry` (bundle/display name) with macOS AppIcon slots populated from the approved logo asset. (Implemented)
     - keep top-bar branding clean:
       - render `ClickCherry` in the top bar aligned near traffic-light controls via a left `NSTitlebarAccessoryViewController`.
       - keep icon to the left of the name with small native-looking size.
       - avoid SwiftUI title-bar toolbar placements (`.principal`, `.navigation`, `.toolbarRole(.editor)`) that introduce capsule/border rendering.
   - Execution provider UI is OpenAI-only (no segmented control / selection persistence).
   - Include host OS version string in the execution-agent prompt (via `{{OS_VERSION}}` placeholder). (Implemented)
   - Add a custom `terminal_exec` tool to the execution tool loop for unrestricted terminal command execution (absolute-path or PATH-resolved executables). (Implemented)
   - Keep OpenAI tool surface stable:
     - runner exposes both `desktop_action` and `terminal_exec`.
   - Keep OpenAI execution prompt organized and action-explicit:
     - separate sections for `desktop_action` help and `terminal_exec` help.
     - include full `desktop_action` action reference and accepted input forms so tool calls are predictable. (Implemented)
   - Keep default `wait` action duration at `0.5s` (when model omits duration). (Implemented)
   - Keep mouse cursor visible in LLM screenshots to improve hover/mouse-move task reliability. (Implemented)
   - Ensure LLM screenshots never include the “Agent is running” HUD by failing closed when exclusion-capable capture is unavailable. (Implemented)
   - Keep full text/tool history but send only the latest screenshot image block per LLM turn to control payload size growth. (Implemented)
   - Enforce terminal-vs-desktop boundary at runtime (block UI/visual terminal commands and redirect to `desktop_action`). (Implemented)
   - Before each run, hide other regular apps to provide a cleaner screen for the agent. (Implemented)
   - Keep screenshot size under a conservative base64 payload budget (downscale/re-encode when required). (Implemented)
   - Expose model-visible screenshots in Diagnostics so users can review the exact images sent to the model. (Implemented)
   - Keep cursor presentation unchanged during agent takeover (normal cursor size, no cursor-following halo overlay), including cancellation/monitor-start-failure paths. (Implemented)
   - Expand action coverage through tool-loop path (scroll/right-click/move/cursor_position implemented; drag and richer UI control still pending).
   - Fix keyboard shortcut injection reliability:
     - handle special keys like `space`.
     - improve text typing reliability for system UI targets (Spotlight, etc.) by using clipboard-paste typing with clipboard restore (cmd+v).
     - remove AppleScript `System Events` usage entirely to avoid macOS Automation permission prompts. (Implemented; unknown keys now fail with an explicit unsupported-key error)
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
     - automation-engine outcome tests (`success`/`needs clarification`/`failed`).
     - run-trigger persistence tests (heartbeat question writeback + run-summary writes).
     - iterative tool-loop parser/execution smoke checks.
   - Markdown runtime-question append/dedup tests.
   - Add richer tool-action integration tests (drag and multi-display coordinate/origin cases; scroll/right-click/move are covered).
   - Add tests for `terminal_exec` tool definition + dispatch (PATH resolution + stdout/stderr capture). (Implemented)
   - Keep OpenAI parity tests passing for `terminal_exec` (execution output, visual-command rejection, PATH-resolved executable). (Implemented)
   - Keep coverage for `cursor_position` tool action mapping + payload return format. (Implemented)
   - Keep coverage for latest-image-only request compaction and visual terminal-command rejection. (Implemented)
   - Keep coverage for base64 image-size budget math (encoded 5 MB limit). (Implemented)
   - Keep coverage for LLM screenshot-log emission (initial + tool-result captures). (Implemented)
   - Keep state-store coverage for desktop preparation before run start. (Implemented)
   - Keep state-store coverage for takeover cursor-presentation activation/deactivation paths. (Implemented)
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
     - cursor presentation remains normal while takeover is active (no enlarged cursor and no halo overlay).
   - Confirm clicking `Run Task` minimizes the app window immediately (agent overlay remains visible).
   - Confirm cursor presentation remains unchanged after run completion/cancellation.
   - Confirm the model can use `terminal_exec` to open an app (example command: `open -a "Google Chrome"`).
   - Confirm Diagnostics -> `LLM Screenshots` matches what the model received during the run.
   - Confirm top-bar brand near traffic lights has no capsule/border and icon renders with correct aspect ratio (not stretched/compressed).
   - Temporarily revoke Screen Recording, Accessibility, or Input Monitoring permission and confirm clicking `Run Task`:
     - triggers a permission prompt (or opens System Settings)
     - does not start a run until permissions are granted
   - Validate ambiguity/failure writes blocking questions to `HEARTBEAT.md`.
   - Answer generated question and rerun to confirm progression.
6. Exit criteria: First execution-agent baseline can run a task, generate blocking questions when needed, and persist outcomes.

1. Step: Defer top-bar branding issue `OI-2026-02-11-007` (backlog).
2. Why now: User requested to pause this path; current attempts are inconsistent and should not block execution-agent priorities.
3. Code tasks:
   - Do not continue titlebar-branding implementation work in this cycle.
   - Keep issue tracked in `.docs/open_issues.md` and revisit in `.docs/revisits.md`.
4. Automated tests:
   - N/A (docs-only defer update).
5. Manual tests:
   - N/A (deferred).
6. Exit criteria: Defer decision is recorded and remains visible in active planning docs.

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
