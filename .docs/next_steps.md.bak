---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Step 2.5 Xcode app target migration (critical blocker).
2. Why now: Real screen recording tests are blocked because the current SwiftPM run path does not provide a stable TCC app identity.
3. Code tasks:
   - Create a real macOS App target in Xcode. (Done: `TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj`)
   - Reuse source files from `app/Sources/TaskAgentMacOS/`. (Done: copied into `TaskAgentMacOSApp/TaskAgentMacOSApp/`)
   - Keep one stable bundle ID (current: `com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp`).
   - Enable signing (`Apple Development`, automatic signing) with personal team in Xcode UI.
   - Use this app target as the only target for permission/capture manual tests.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build` (pass)
   - `swift test` in `app/` (pass, 28 tests)
5. Manual tests:
   - Run app from Xcode twice using the same scheme/target.
   - In onboarding permissions, click `Check Status` once for Screen Recording and Accessibility to trigger macOS prompt/registration.
   - Confirm active scheme is macOS App target (not package executable scheme).
   - Confirm signing certificate is `Apple Development` (not `Sign to Run Locally`).
   - Verify built app signature/ID:
     - `codesign -dv --verbose=4 "<path-to-app>.app"`
     - `defaults read "<path-to-app>.app/Contents/Info.plist" CFBundleIdentifier`
   - Grant Screen Recording in System Settings once.
   - If app is not listed automatically, add built `.app` via `+` in Screen Recording settings.
   - Confirm second run does not require re-grant for the same app identity.
   - Confirm `Start Capture`/`Stop Capture` succeeds and output appears under task `recordings/`.
6. Exit criteria: Permission grant persists across Xcode runs and capture works end-to-end from Xcode Run.

1. Step: Step 3 task extraction from recording (next).
2. Why now: Capture flow is implemented; once real capture testing is unblocked, extraction is the next product milestone.
3. Code tasks: Build recording-to-task extraction pipeline stub with provider adapter boundary and markdown update path.
4. Automated tests: Unit tests for extraction request/response parsing and heartbeat update validation.
5. Manual tests: Run extraction on sample recording and verify `HEARTBEAT.md` updates `# Task` and `## Questions`.
6. Exit criteria: Recording extraction path updates task markdown with validated content.
