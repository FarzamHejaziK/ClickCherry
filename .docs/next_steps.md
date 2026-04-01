---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Redesign the execution takeover overlay into a transparent live run feed on the selected display.
2. Why now: The current centered HUD confirms takeover but does not surface enough run context, does not keep the Escape stop state visible long enough, and is visually weaker than the rest of the execution UX. The underlying run event stream and screenshot log already exist, so the next highest-leverage step is to expose that data in the overlay without changing the model-facing capture contract.
3. Code tasks:
  - Replace the centered `Agent is running` HUD with a top-anchored transparent activity overlay.
  - Extend `AgentControlOverlayService` so it can render live state updates from the active run.
  - Reuse `runHistory` events and `runScreenshotLogByRunID` screenshots to populate the overlay feed with newest-first ordering.
  - Keep the overlay click-through and excluded from model screenshots through the existing window-number exclusion path.
  - Change the Escape cancellation flow so the overlay stays visible with a stopping message until the run settles.
4. Automated tests:
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests CODE_SIGNING_ALLOWED=NO`.
  - Run `xcodebuild build -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO`.
  - If the overlay implementation introduces reusable view logic outside the state store, add focused tests or previews for that surface before broadening coverage.
5. Manual tests:
  - Run a known-safe multi-turn task and confirm the overlay appears on the selected display with a transparent top activity feed.
  - Confirm the newest action is always shown at the top and older actions remain visible below it.
  - Confirm recent screenshot thumbnails shown in the overlay match the run screenshots persisted for diagnostics.
  - Press `Escape` mid-run and confirm a visible stopping state remains on screen until the run cancels.
  - Confirm the app still launches cleanly from the debug build after the overlay redesign.
  - Confirm the model-visible screenshots never include the overlay itself.
6. Exit criteria:
  - The overlay clearly shows current and recent run activity without blocking interaction on the desktop.
  - Escape cancellation remains visible on-screen until the run settles.
  - The overlay stays excluded from model screenshots and does not regress selected-display capture behavior.
  - Automated tests and a debug build pass after the redesign.
