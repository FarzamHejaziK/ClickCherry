---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Tighten how cursor state is delivered to the execution model now that screenshot/grid coordinates are stable.
2. Why now: The selected-display coordinate contract, grid overlays, persisted screenshots, and live-run validation are now behaving correctly. The next highest-value simplification is reducing cursor-location ambiguity in the model context without reopening the overlay bugs we just fixed.
3. Code tasks:
  - Keep the selected-display/global coordinate contract as the single source of truth for screenshot labels, crop inputs, and pointer actions.
  - Decide and implement the cursor-state delivery shape for execution turns:
    - keep the rule in the system prompt once
    - keep the live `CURRENT_CURSOR` value with each screenshot payload
    - avoid introducing a separate cursor tool as the primary path unless diagnostics prove it is necessary
  - Preserve persisted screenshot artifacts and persisted `-llm-exchanges` as mandatory diagnostics for execution runs.
  - Keep the overlay visual-check scripts as the deterministic validation path for future cursor/grid changes.
4. Automated tests:
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/DesktopScreenshotTransformServiceTests test`.
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerVisionTests test`.
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests test`.
  - Run `xcodebuild build -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build`.
5. Manual tests:
  - Run `/Users/ferzamh/code-git-local/ClickCherry/scripts/run_overlay_visual_checks.sh` and visually confirm the full-screen and crop overlay outputs still align after any cursor-state change.
  - Re-run `Hover over Google Chrome in Dock` and inspect persisted screenshots plus `-llm-exchanges` to confirm the model sees the expected cursor state and still lands on the correct icon.
  - Inspect at least one run that uses a grid overlay and confirm the visible grid labels match the crop bounds reported in the matching request JSON.
6. Exit criteria:
  - Cursor state is presented to the model in a single clear contract that does not require mental remapping after crops.
  - Overlay visual-check artifacts remain correct.
  - Real execution runs continue to show correct cursor placement and successful Dock hover targeting.
