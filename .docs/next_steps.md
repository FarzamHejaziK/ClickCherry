---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Confirm local Xcode build no longer reports `Initializer for conditional binding must have Optional type, not 'Data'`.
2. Why now: This hotfix unblocks development/build flow before further capture validation.
3. Code tasks:
   - Keep `isPNGFile(url:)` using a single optional binding for `read(upToCount:)` result.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-local CODE_SIGNING_ALLOWED=NO build`
5. Manual tests:
   - Build from Xcode UI and confirm no compile error on `RecordingCaptureService.swift`.
6. Exit criteria: Build advances past `RecordingCaptureService.swift` without the optional-binding error.

1. Step: Validate forced-video capture fix in signed Xcode run.
2. Why now: One saved `.mov` was actually a PNG screenshot, which confirms the previous capture path was not reliably entering video mode.
3. Code tasks:
   - Keep capture fallback chain for explicit mic-device mode:
     - selected device (`-G <id>`)
     - fallback to system default mic (`-g`)
     - fallback to no-mic only if both mic attempts fail
   - Keep `screencapture -v` mode (reverted from `-V`) because `-V` caused stop-time no-file failures (`status 15`) when ending early.
   - Keep stop sequence as `interrupt` first (with terminate/kill escalation only if needed) for better recording finalization.
   - Keep stop-time guard that rejects PNG output masquerading as `.mov`.
   - Keep unique capture filenames with fractional seconds + UUID suffix to avoid same-second file collision on retries.
   - Keep start-time mic-device refresh to reduce stale device selection failures.
   - Keep explicit status/warning messaging for mic fallback outcomes.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-local -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - In app, select `System Default Microphone`, start/stop capture, confirm spoken voice in playback and that no floating screenshot toolbar appears.
   - Select an explicit mic device, start/stop capture, confirm spoken voice in playback.
   - If explicit device fails, confirm start status reports fallback to system default mic (not silent no-audio fallback).
   - Select `No Microphone`, start/stop capture, confirm no voice is captured as expected.
   - In Finder/Terminal, run `file <new-capture.mov>` and confirm it reports QuickTime/MOV, not PNG.
   - If stop fails, capture and share the full error string (now includes command args and stderr/stdout details).
6. Exit criteria: At least one new recording is a real MOV (not PNG) with audible voice using system default mic; explicit-device path succeeds or cleanly falls back with explicit message.

1. Step: Commit documentation governance + design decision updates.
2. Why now: Keep process expectations explicit and ensure design decisions are captured in the canonical design log.
3. Code tasks:
   - Commit `/Users/farzamh/code-git-local/task-agent-macos/AGENTS.md` `.docs/` update contract.
   - Commit `/Users/farzamh/code-git-local/task-agent-macos/.docs/design.md` recording UX decisions (red border + mic source selection).
   - Commit `/Users/farzamh/code-git-local/task-agent-macos/.docs/worklog.md` and `/Users/farzamh/code-git-local/task-agent-macos/.docs/next_steps.md` synchronization entries.
4. Automated tests:
   - `git diff -- AGENTS.md .docs/design.md .docs/worklog.md .docs/next_steps.md`
   - `git status --short`
5. Manual tests:
   - Review updated docs for consistency and verify all `.docs/` file ownership rules are clear and actionable.
6. Exit criteria: Docs governance and new design decisions are committed and become the new source of truth.

1. Step: Commit repository hygiene cleanup.
2. Why now: Keep the working tree free of machine-specific Xcode churn before continuing capture work.
3. Code tasks:
   - Commit `/Users/farzamh/code-git-local/task-agent-macos/.gitignore` update for `.deriveddata/` and `*.xcuserstate`.
   - Commit untracking of `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj/project.xcworkspace/xcuserdata/farzamh.xcuserdatad/UserInterfaceState.xcuserstate`.
4. Automated tests:
   - `git check-ignore -v .deriveddata/ TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj/project.xcworkspace/xcuserdata/farzamh.xcuserdatad/UserInterfaceState.xcuserstate`
   - `git status --short`
5. Manual tests:
   - Open Xcode, perform a quick UI interaction, close Xcode, and verify no new unstaged `xcuserdata`/`.xcuserstate` noise appears.
6. Exit criteria: Working tree stays clean from local Xcode artifact churn after normal local usage.

1. Step: Step 2.6 capture stabilization and validation.
2. Why now: Recent capture changes produced non-playable `.mov` output and intermittent start failures; capture reliability is the current blocker.
3. Code tasks:
   - Keep non-interactive display capture path with mic-first strategy (`screencapture -V <long-seconds> -g -D <display>` then fallback to `-V <long-seconds> -D <display>` if mic mode fails for app identity).
   - Keep in-app microphone source picker wired to `screencapture`:
     - `No Microphone` -> no audio arg
     - `System Default Microphone` -> `-g`
     - explicit input device -> `-G <audio-id>`
   - Request microphone access in-app before mic capture attempt (`AVCaptureDevice.requestAccess(.audio)`) so permission prompt originates from app runtime.
   - Keep red recording border overlay on the selected display while capture is active; hide immediately on stop/failure.
   - Keep app Info.plist microphone usage text configured (`NSMicrophoneUsageDescription`) to prevent privacy-access crash.
   - Keep graceful stop path (`interrupt`) so QuickTime-compatible `.mov` finalization is preserved.
   - Keep a short post-stop file finalize wait to avoid false "no recording file" errors.
   - Keep output validation guard to detect PNG-in-`.mov` miscaptures and fail with explicit messaging.
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
   - Verify mic picker shows `No Microphone`, `System Default Microphone`, and detected input devices with IDs.
   - Verify selecting an explicit mic device starts capture with microphone audio and status reflects chosen input.
   - Verify selecting `No Microphone` starts capture without audio and status reflects no-mic mode.
   - Verify red border appears on selected display during active recording and disappears after stop/failure.
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
