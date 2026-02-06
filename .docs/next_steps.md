---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Step 2.5 migration closeout (Xcode-only workflow).
2. Why now: Old `app/` SwiftPM folder is removed; project now develops/tests from `TaskAgentMacOSApp.xcodeproj`.
3. Code tasks:
   - Keep all app code under `TaskAgentMacOSApp/TaskAgentMacOSApp/`.
   - Keep all tests under `TaskAgentMacOSApp/TaskAgentMacOSAppTests/`.
   - Keep stable bundle ID/signing identity for TCC permission persistence.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build`
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - Run signed app from Xcode (`TaskAgentMacOSApp` scheme).
   - Verify Screen Recording + Accessibility grant flow.
   - Verify permissions persist across app relaunch.
   - Verify `Start Capture` -> `Stop Capture` writes recording under task `recordings/`.
6. Exit criteria: Xcode-only dev/test flow is stable and permission/capture flow is validated.

1. Step: Step 3 task extraction from recording.
2. Why now: Recording flow is in place; next milestone is turning recordings into task markdown.
3. Code tasks: Build extraction pipeline stub + provider adapter boundary + markdown update path.
4. Automated tests: Parser/validation tests for `# Task` and `## Questions` updates.
5. Manual tests: Run extraction and verify `HEARTBEAT.md` content updates correctly.
6. Exit criteria: Extraction path updates task markdown with validated output.
