---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Validate and stabilize the split `MainShellStateStore` structure before any deeper cleanup.
2. Why now: `MainShellStateStore` has been reorganized into domain files under `TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShell/` with targeted tests and a broader app build passing, so the next highest-value work is to finish interactive smoke coverage and only then do small no-behavior-change cleanup passes.
3. Code tasks:
  - Run the MainShell manual smoke checklist across task creation/selection, settings/provider keys, heartbeat clarifications, run preflight/cancel, recording, and extraction.
  - Fix any regressions found in the split without broadening scope.
  - If the split stays stable, follow up with small internal deduplication passes in `MainShellStateStore+RunTask.swift`, `MainShellStateStore+Recording.swift`, and `MainShellStateStore+Extraction.swift` without changing public API or UX.
4. Automated tests:
  - Keep `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` green after each follow-up change.
  - Run `xcodebuild build -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` before merging release-facing cleanup.
5. Manual tests:
  - Open/new/select/delete/pin tasks.
  - Save and clear provider keys; verify missing-key routes still open Settings correctly.
  - Save heartbeat changes and apply a clarification answer on a task that has questions.
  - Trigger run preflight failures, start a run with valid setup, and cancel with `Esc`.
  - Start/stop capture, import a recording, and verify extraction to both a new task and an existing task.
6. Exit criteria:
  - No regressions are found in the MainShell interactive smoke pass.
  - `MainShellStateStoreTests` and a broader app build remain green.
  - Any post-split cleanup remains semantics-preserving.
