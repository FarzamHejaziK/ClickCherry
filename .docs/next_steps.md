---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Stabilize execution behavior on prompt baseline `v2` and close the Dock-hover misidentification issue.
2. Why now: Replay diagnostics proved image transport is correct and prompt drift introduced regressions; the highest-value work is now runner guardrails plus targeted validation on the working baseline.
3. Code tasks:
  - Keep `execution_agent_openai/config.yaml` pinned to `version: v2`.
  - Add runner-side success validation guardrails for hover/target-identification tasks so `SUCCESS` requires direct screenshot evidence.
  - Keep screenshot and `-llm-exchanges` persistence as mandatory diagnostics for execution runs.
  - Investigate and stabilize `OpenAIComputerUseRunnerTests` whole-suite failures (shared state/interference).
4. Automated tests:
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/PromptCatalogServiceTests test`.
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests test`.
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/DesktopScreenshotTransformServiceTests -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerVisionTests test`.
  - Run `xcodebuild build -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build`.
5. Manual tests:
  - Re-run `Hover over Google Chrome in Dock` multiple times and verify final tooltip matches `Google Chrome` on success runs.
  - Open persisted run screenshots and confirm cursor marker alignment in initial and follow-up images.
  - Inspect `-llm-exchanges` for each run and confirm selected prompt/version/model logs match expected baseline.
  - Confirm screenshot thumbnails open in Preview for all images in a run log.
6. Exit criteria:
  - Dock-hover task succeeds consistently on `v2` without false-success claims.
  - Whole `OpenAIComputerUseRunnerTests` suite is stable when run together.
  - Replay workflow remains usable for prompt/runtime diagnosis.
