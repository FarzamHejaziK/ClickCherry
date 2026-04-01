---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Validate the new OpenAI Responses WebSocket transport in live provider-backed runs and decide whether the current internal-only rollout settings are sufficient.
2. Why now: The transport abstraction, fallback behavior, focused automated coverage, app build, and local launch smoke are complete. The remaining uncertainty is live socket behavior, recovery quality, and real latency impact against the OpenAI API.
3. Code tasks:
  - Run one safe multi-turn task in `http` mode and one in `webSocketPreferred` mode using the same task and desktop target.
  - Verify exchange logs and execution traces remain readable and that socket lifecycle events are persisted clearly.
  - Confirm fallback to HTTP preserves run continuity when the socket path fails before the runner can complete a turn.
  - Keep the transport mode internal and `UserDefaults`-backed unless live validation shows a strong need for a debug-facing toggle.
  - After live transport validation is complete, return to the higher-level Dock-hover/success-evidence follow-up work.
4. Automated tests:
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerVisionTests CODE_SIGNING_ALLOWED=NO`.
  - Run `xcodebuild build -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO`.
  - If any transport follow-up changes are made after live validation, rerun the focused suite before expanding to broader tests.
5. Manual tests:
  - Run a known-safe multi-turn OpenAI task in `http` mode and capture baseline timing plus diagnostics.
  - Run the same task in `webSocketPreferred` mode and compare timing, tool behavior, screenshots, and final result.
  - Confirm the app still launches cleanly from the debug build after any transport follow-up changes.
  - If feasible, induce a socket-path failure and confirm the run falls back to HTTP without partial-turn tool execution.
6. Exit criteria:
  - Live WebSocket runs match HTTP behavior for tool selection, screenshot flow, and final status handling.
  - Persisted diagnostics make socket open/reuse/reconnect/fallback events easy to inspect.
  - WebSocket is at least neutral and preferably faster on a representative multi-turn task.
  - Remaining execution-quality follow-up work is again dominated by model behavior rather than transport behavior.
