---
description: Testing guidance for TaskAgentMacOSApp, including local commands, release-artifact validation, and permission-specific caveats.
---

# Testing Guide

## Source of truth

- Treat local Xcode or local terminal runs as the authoritative build/test result for source changes.
- Treat the GitHub DMG as the authoritative runtime artifact for release-permission validation.
- For permission regressions, do not stop at local Xcode validation. Compare:
  - Apple Development local build
  - GitHub release DMG / Developer ID hardened-runtime artifact

## Why local and public builds can differ

- Local Xcode runs are signed as `Apple Development`.
- Public DMGs are re-signed as `Developer ID Application` with hardened runtime.
- A local build can pass while the public DMG fails if signing or entitlements differ.
- This is exactly how the March 2026 microphone regression reproduced: local builds showed the native prompt, while the public DMG failed until the hardened-runtime signature included `com.apple.security.device.audio-input`.

## Recommended local test commands

Release build:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/clickcherry-release-local \
  build
```

Unit tests:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/clickcherry-tests-local \
  -only-testing:TaskAgentMacOSAppTests \
  test
```

Optional: force a specific Xcode when multiple versions are installed.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...
```

## Operational notes

- Use a dedicated `-derivedDataPath` to avoid permission or lock conflicts.
- Avoid running multiple `xcodebuild` commands concurrently against the same DerivedData path.
- If you hit stale lock issues, remove the chosen DerivedData directory and rerun.
- Unit tests run inside an XCTest host app process. To avoid macOS Keychain popups during test runs, `KeychainAPIKeyStore` automatically uses in-memory storage when `XCTestConfigurationFilePath` is present.
- Runtime behavior is unchanged outside XCTest: provider keys are still read/written in macOS Keychain.

## MainShell refactor smoke test

Use this focused pass after structural refactors to `MainShellStateStore` or its extension files.

1. Run the targeted store suite:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests \
  test
```

2. Run a broader build:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  build
```

3. Perform this interactive smoke checklist in the app:
   - Create a task, open another task, and switch back to confirm selection and heartbeat reloads.
   - Open Settings, save a provider key, then clear it and confirm missing-key flows still route correctly.
   - Pin a task, verify it moves to the pinned area, then delete the selected pinned task and confirm the app returns to the new-task route.
   - Edit and save heartbeat content, then reopen the task to confirm persistence.
   - If clarification questions are present, answer one and verify it remains resolved after reload.
   - Trigger run preflight failures, then run a valid task and cancel it with `Esc`.
   - Start and stop capture, then verify the finished-recording review flow appears.
   - Import a supported recording and verify extraction to both a new task and an existing task.

## Public DMG permission verification

Use this when the bug might depend on release signing, notarization, or hardened runtime.

1. Download the GitHub DMG for the tag under test.
2. Remove all other `ClickCherry` copies and eject all mounted ClickCherry DMGs.
3. Drag `ClickCherry.app` into `/Applications`.
4. Reset permission state before each clean pass:

```bash
tccutil reset ScreenCapture
tccutil reset Microphone com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp
tccutil reset Accessibility com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp
tccutil reset ListenEvent com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp
killall tccd || true
```

5. Launch only `/Applications/ClickCherry.app`.
6. Validate permission flows in this order:
   - Microphone: expect native macOS dialog on first request.
   - Screen Recording: expect System Settings list entry for the installed app.
   - Accessibility / Input Monitoring: expect Settings-first flow.

## Permission-specific caveats

- Microphone:
  - The native macOS dialog is the critical first-registration path.
  - There is no manual `+` add flow in System Settings.
- Screen Recording:
  - The Settings list can preserve stale renamed local test app entries.
  - If Screen Recording shows a backup/test app name instead of `ClickCherry`, treat that as test-environment contamination and redo the clean reset before evaluating product behavior.
- Accessibility / Input Monitoring:
  - These remain Settings-first validations and are more sensitive to duplicate app copies than to signing-entitlement drift.
