---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Step 2.6 capture stabilization and validation.
2. Why now: Recent capture changes produced non-playable `.mov` output and intermittent start failures; capture reliability is the current blocker.
3. Code tasks:
   - Keep non-interactive display capture path with mic-first strategy (`screencapture -v -g -D <display>` then fallback to `-v -D <display>` if mic mode fails for app identity).
   - Request microphone access in-app before mic capture attempt (`AVCaptureDevice.requestAccess(.audio)`) so permission prompt originates from app runtime.
   - Keep app Info.plist microphone usage text configured (`NSMicrophoneUsageDescription`) to prevent privacy-access crash.
   - Keep graceful stop path (`interrupt`) so QuickTime-compatible `.mov` finalization is preserved.
   - Keep a short post-stop file finalize wait to avoid false "no recording file" errors.
   - Keep app target unsandboxed for local capture testing (`ENABLE_APP_SANDBOX = NO`), since sandboxed child-process capture fails with immediate status `1`.
   - Surface explicit start/stop failure reasons to avoid silent recording failures.
   - Ensure UI state resets if backend capture is already stopped or fails.
4. Automated tests:
   - Reference command set in `/Users/farzamh/code-git-local/task-agent-macos/.docs/testing.md`.
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build`
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test`
   - If DerivedData permission collisions occur, run with isolated path:
     `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-local CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - Run signed app from Xcode (`TaskAgentMacOSApp` scheme).
   - Verify Screen Recording + Accessibility grant flow.
   - Verify first mic-enabled capture attempt triggers macOS microphone prompt from the app when permission is `Not Determined`.
   - Verify Microphone permission is granted for `TaskAgentMacOSApp` in `Privacy & Security > Microphone`.
   - Verify permissions persist across app relaunch.
   - Verify selecting `Display 1/2/...` in-app and clicking `Start Capture` immediately starts full-display recording (no floating region picker).
   - Verify start-status message indicates whether microphone audio is enabled or app fell back to no-mic mode.
   - Verify while recording: red indicator + elapsed timer is visible and clear.
   - Verify `Stop Capture` writes recording under task `recordings/` and status names saved file.
   - Open the saved file in QuickTime via `Play`; confirm it is playable (not corrupted/incompatible).
   - Confirm spoken voice is present in playback.
   - If recording is not written, verify app shows explicit start/stop failure reason (no silent success).
   - Verify each recording row actions:
     - `Reveal` opens file location in Finder
     - `Play` opens the recording in default video player
6. Exit criteria: At least one new `.mov` capture is playable in QuickTime from in-app `Play`, with clear start/stop UX.

1. Step: Step 3 task extraction from recording.
2. Why now: Recording flow is in place; next milestone is turning recordings into task markdown.
3. Code tasks: Build extraction pipeline stub + provider adapter boundary + markdown update path.
4. Automated tests: Parser/validation tests for `# Task` and `## Questions` updates.
5. Manual tests: Run extraction and verify `HEARTBEAT.md` content updates correctly.
6. Exit criteria: Extraction path updates task markdown with validated output.
