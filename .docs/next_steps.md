---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Validate the new vision-first grounding path on live desktop tasks and, if needed, follow it with stateful pointer execution improvements.
2. Why now: screenshot crop/zoom, grid overlay, active image-to-screen mapping, and same-turn visual guardrails are now code-complete and automated-test complete, so the remaining risk is real desktop pointer reliability rather than missing infrastructure.
3. Code tasks:
  - Run live small-target tasks and collect any remaining misses or drift cases.
  - If misses remain, implement the next executor follow-up:
    - stepped mouse movement
    - hover dwell
    - click timing
    - post-move verification before retry
  - Tune grid contrast/spacing only if runtime validation shows the current overlay is hard to read.
4. Automated tests:
  - Keep `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests test` green.
  - Keep `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/DesktopScreenshotTransformServiceTests -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerVisionTests test` green.
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests test` after the final split.
  - Run `xcodebuild build -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` before closing the task.
5. Manual tests:
  - Run a small-target task that uses full screenshot -> crop -> fine grid -> click and confirm the click lands correctly.
  - Run a crop-inside-crop targeting flow and confirm the final click still lands on the intended real screen point.
  - Validate overlay readability on both light and dark backgrounds.
  - Validate the same flow on a non-primary display.
  - Confirm a click/type/open action resets the next model turn back to a fresh full-display screenshot.
6. Exit criteria:
  - Live desktop validation shows the vision-first grounding flow materially improves localization for small targets.
  - Any follow-up pointer-execution changes land with focused tests, full tests, and a clean build.
  - Multi-display and overlay-readability checks remain green in manual validation.
