---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Step 3.1 prompt management foundation (active).
2. Why now: We explicitly decided to defer microphone issue `OI-2026-02-07-001` and start Step 3 extraction with a reusable prompt system that works across providers.
3. Code tasks:
   - Add file-based prompt registry under `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Prompts/`.
   - Add versioned prompt layout for task extraction (`system.md`, `user.md`, `output_schema.json`).
   - Add alias resolution (`stable`, `canary`) via a single registry file.
   - Add Swift prompt-loading/rendering service with deterministic errors for missing/invalid prompt assets.
   - Add provider-agnostic request model so OpenAI/Anthropic/Gemini adapters can consume one canonical prompt shape.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-local -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
   - If sandbox macro limitations block authoritative suite signal, at minimum run focused typecheck for new prompt services and unit tests in local Xcode.
5. Manual tests:
   - In app, trigger extraction flow stub for a task recording and verify prompt metadata (ID/version/alias) is visible in status/diagnostics output.
   - Flip alias mapping from `stable` to another version and verify extractor uses the new version without code changes.
6. Exit criteria: Prompt files are versioned and resolved by alias, and extraction path can request a prompt set deterministically.

1. Step: Step 3.2 task extraction pipeline integration (next).
2. Why now: After prompt foundation, we need end-to-end recording -> model output -> `HEARTBEAT.md` update.
3. Code tasks:
   - Implement extraction service using the prompt system + provider adapter boundary.
   - Parse/validate model output into `# Task` and `## Questions`.
   - Update `HEARTBEAT.md` only when parsed output passes validation.
4. Automated tests:
   - Parser success/failure tests.
   - Markdown writer tests for `# Task` and `## Questions` updates.
   - Integration test with mocked LLM client (success + malformed output).
5. Manual tests:
   - Run extraction against one recording and confirm task details are specific and actionable.
   - Confirm malformed output surfaces an explicit error and does not corrupt existing `HEARTBEAT.md`.
6. Exit criteria: `HEARTBEAT.md` updates reliably from recording analysis with validated content.

1. Step: Defer `OI-2026-02-07-001` until Step 3 baseline ships.
2. Why now: Issue is mitigated by `System Default Microphone`; current priority is unblocking extraction milestones.
3. Code tasks:
   - Keep current mitigation and fallback messaging unchanged.
   - Re-open diagnostics work after Step 3.2 if still needed.
4. Automated tests: N/A (deferred backlog item).
5. Manual tests: N/A (deferred backlog item).
6. Exit criteria: Item remains tracked in `.docs/open_issues.md` with mitigation; no new scope spent before Step 3 baseline.
