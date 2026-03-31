---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Improve model-side target judgment and success validation for Dock hover tasks now that visual grounding and cursor delivery are explicit.
2. Why now: Screenshot coordinates, grid overlays, cursor overlays, and `CURRENT_CURSOR` delivery are now consistent. The remaining failures are higher-level model behavior failures such as picking the wrong icon or claiming success without enough visual evidence.
3. Code tasks:
  - Keep the selected-display/global coordinate contract and explicit cursor-state contract unchanged.
  - Add runner-side completion guardrails for hover/target-identification tasks so `SUCCESS` requires direct screenshot evidence when the task asks for a visible hover target.
  - Add targeted replay fixtures or assertions that compare claimed target identity against the visible tooltip or equivalent screenshot evidence.
  - Keep persisted screenshots and persisted `-llm-exchanges` as mandatory diagnostics for execution runs.
4. Automated tests:
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerVisionTests test`.
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests/runToolLoopExecutesToolUseAndReturnsSuccess test`.
  - Run `xcodebuild build -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build`.
  - Revisit the broader `OpenAIComputerUseRunnerTests` whole-suite harness separately if it continues to fail for reasons unrelated to the current behavior change.
5. Manual tests:
  - Re-run `Hover over Google Chrome in Dock` multiple times and inspect persisted screenshots plus `-llm-exchanges`.
  - Confirm `CURRENT_CURSOR` text and structured cursor metadata agree with the screenshot for each hover-critical turn.
  - Confirm success is only accepted when the final screenshot clearly identifies the requested Dock icon.
6. Exit criteria:
  - Dock-hover runs stop falsely selecting the wrong icon after a correct crop.
  - Dock-hover runs stop falsely reporting success without matching visible evidence.
  - Replay diagnostics remain sufficient to explain any remaining misses turn by turn.
