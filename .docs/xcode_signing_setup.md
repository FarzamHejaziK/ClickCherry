---
description: Required Xcode app identity and signing setup for reliable macOS permission (TCC) testing
---

# Xcode App Target + Signing Setup (Required for Permission Testing)

Use this setup whenever testing Screen Recording, Accessibility, Input Monitoring, or Microphone grants.

## Why this is required

- macOS TCC ties permission behavior to app identity, signing, and install path.
- Local Xcode runs and public GitHub DMGs are different artifacts:
  - Xcode run: `Apple Development`
  - GitHub DMG: `Developer ID Application` + hardened runtime
- A permission flow can work locally and still fail in the public DMG if the release-signing path drops a required entitlement.

## App identities used in this repo

1. Open `/Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj`.
2. Use scheme `TaskAgentMacOSApp`.
3. Keep the checked-in bundle IDs stable:
   - Debug: `com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp.dev` (`ClickCherry Dev`)
   - Release: `com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp` (`ClickCherry`)

## Xcode signing requirements

1. In target `Signing & Capabilities`:
   - Team: your Apple development team
   - Signing Certificate: `Apple Development`
   - Automatically manage signing: enabled
2. Keep the app target wired to:
   - `/Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp/ClickCherry.entitlements`
3. The entitlements file must continue to include:
   - `com.apple.security.device.audio-input`
   - `com.apple.security.files.user-selected.read-only`

## Release signing requirements discovered in 2026-03

The March 2026 DMG investigation proved the microphone regression was caused by hardened-runtime signing without `com.apple.security.device.audio-input`.

Required release-signing contract:

1. `/Users/ferzamh/code-git-local/ClickCherry/.github/workflows/release.yml` must sign the built app with:
   - `--options runtime`
   - `--entitlements TaskAgentMacOSApp/TaskAgentMacOSApp/ClickCherry.entitlements`
2. The release workflow should fail if the final signed app is missing `com.apple.security.device.audio-input`.
3. If a permission bug reproduces only in a public DMG, compare the signed entitlements in the final `.app` before changing permission UI code.

## Local Xcode validation checklist

1. Launch using Xcode `Run` with the same scheme/target each time.
2. Do not switch bundle ID between runs.
3. After build, verify the built app identity from Terminal:
   - `codesign -dv --verbose=4 "<path-to-your-app>.app"`
   - `defaults read "<path-to-your-app>.app/Contents/Info.plist" CFBundleIdentifier`
4. Confirm `Authority=` is present and matches your development signing identity.

## Release DMG runtime checklist

Use this checklist when validating a GitHub DMG install:

1. Download the DMG for the tag under test.
2. Drag `ClickCherry.app` into `/Applications`.
3. Eject the mounted DMG before launching app for permission checks.
4. Launch only `/Applications/ClickCherry.app`.
5. Use app actions to open each privacy pane.
6. Confirm expected behavior:
   - Microphone: first-time request should show the native macOS dialog.
   - Screen Recording / Accessibility / Input Monitoring: app should route to System Settings lists.

## Clean-slate permission reset checklist

Use this before end-to-end DMG validation when prior local experiments may have polluted TCC state:

1. Delete all local `ClickCherry` variants from `/Applications`, `Downloads`, mounted DMGs, and temporary backup locations.
2. Keep exactly one app copy for the test: `/Applications/ClickCherry.app`.
3. Reset:
   - `tccutil reset ScreenCapture`
   - `tccutil reset Microphone com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp`
   - `tccutil reset Accessibility com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp`
   - `tccutil reset ListenEvent com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp`
4. Optionally restart the daemon between passes:
   - `killall tccd || true`
5. Relaunch `ClickCherry` from `/Applications`.

Important behavior discovered during investigation:

- Screen Recording can retain stale renamed backup/test app entries because the Settings list is path-sensitive enough to preserve earlier experimental app paths.
- Microphone does not provide a manual `+` add flow in System Settings; the native permission dialog is the critical first-registration path.
- If Screen Recording shows a stale backup/test app name, run a global `tccutil reset ScreenCapture` and reinstall only the GitHub DMG app before re-testing.

## Exit criteria

- Permission state is reproducible across two Xcode runs for the development app identity.
- Public GitHub DMG testing from `/Applications` shows the native microphone dialog on first request.
- No duplicate local app copies remain during DMG permission validation.
