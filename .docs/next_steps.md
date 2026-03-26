---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Split `PermissionService.swift` into clearer per-permission concerns with no behavior change.
2. Why now: the OpenAI execution-runner split is now code-complete, tested, and manually smoke-validated, so the next highest maintainability hotspot in the active path is `PermissionService.swift`.
3. Code tasks:
  - Extract screen recording permission checks and routing into a dedicated concern.
  - Extract microphone permission status, request flow, and settings handoff into a dedicated concern.
  - Extract accessibility and input-monitoring remediation helpers into clearer local seams.
  - Preserve all user-facing labels, status bucketing, deep links, and caching behavior exactly.
4. Automated tests:
  - Keep `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/PermissionServiceTests test` green after each extraction slice.
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests test` after the final split.
  - Run `xcodebuild build -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` before closing the task.
5. Manual tests:
  - Exercise each permission row from onboarding/settings and confirm the primary action and status text remain unchanged.
  - Validate the microphone not-determined flow still requests native access before falling back to Settings.
  - Validate screen recording, accessibility, and input-monitoring flows still route to the same System Settings destinations.
6. Exit criteria:
  - `PermissionService.swift` is broken into smaller concern-based units or same-type extensions with no intended behavior change.
  - Permission-focused tests, broader tests, and app build remain green.
  - Manual permission remediation flows behave exactly as before.
