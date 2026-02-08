---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Step 3 task extraction from recording (active).
2. Why now: Prompt contract and Gemini-backed extraction wiring are in place; remaining work is end-to-end runtime validation from the app UI and hardening.
3. Code tasks:
   - Validate extraction end-to-end from the app using a real Gemini key from onboarding/main-shell key settings.
   - Keep main-shell `Provider API Keys` settings as the key-rotation path without re-running onboarding.
   - Keep one LLM call per selected recording with prompt text from `prompt.md` and model from `config.yaml`.
   - Preserve current validation contract (`# Task`, `## Questions`, `TaskDetected`, `Status`, `NoTaskReason`) while stripping control metadata from persisted `HEARTBEAT.md`.
   - Keep no-overwrite behavior for both invalid output and `TaskDetected: false` output.
   - Add explicit UI status/error mapping for provider/network failures.
   - Keep unit tests Keychain-free (`XCTestConfigurationFilePath` -> in-memory key storage path).
   - Keep startup key-presence checks prompt-minimized (single service lookup + cache) to avoid repeated Keychain dialogs.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-local -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
   - Maintain parser/validation tests for success + malformed output.
   - Maintain tests verifying invalid/no-task extraction output does not overwrite existing `HEARTBEAT.md`.
   - Maintain tests verifying persisted `HEARTBEAT.md` excludes `TaskDetected`, `Status`, and `NoTaskReason`.
5. Manual tests:
   - Select a task recording and run extraction from the app UI.
   - Confirm exactly one provider call is issued and `HEARTBEAT.md` updates on valid output without control metadata lines.
   - Run extraction on a non-task/low-signal recording and confirm structured no-task output is returned.
   - Confirm no-task/malformed/empty/provider-failure output preserves existing markdown.
   - Relaunch app and confirm keychain access dialog does not repeat multiple times for startup key checks.
6. Exit criteria: At least one real recording updates `HEARTBEAT.md` through provider-backed extraction with validated output.

1. Step: Step 4 clarification loop UI integration (next).
2. Why now: After extraction creates `## Questions`, users need an in-app answer/apply loop.
3. Code tasks:
   - Add Q&A panel for unresolved questions.
   - Persist answers back into `HEARTBEAT.md`.
4. Automated tests:
   - Question parsing/state tests.
   - Markdown update tests for resolved questions.
5. Manual tests:
   - Answer at least one extracted question in-app.
   - Confirm answer is persisted and reflected in task markdown.
6. Exit criteria: Clarification answers can be applied and persisted reliably.

1. Step: Defer `OI-2026-02-07-001` until extraction baseline ships.
2. Why now: Mitigation remains available via `System Default Microphone`; extraction milestone is higher priority.
3. Code tasks:
   - Keep current mitigation and fallback messaging unchanged.
   - Re-open mic diagnostics work after Step 3 is stable.
4. Automated tests: N/A (deferred backlog item).
5. Manual tests: N/A (deferred backlog item).
6. Exit criteria: Issue remains tracked in `.docs/open_issues.md` with mitigation and clear next action.
