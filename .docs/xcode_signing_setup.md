---
description: Required Xcode app identity and signing setup for reliable macOS permission (TCC) testing
---

# Xcode App Target + Signing Setup (Required for Permission Testing)

Use this setup whenever testing Screen Recording, Accessibility, Input Monitoring, or Microphone grants.

## Why this is required

- `swift run` can produce transient binary identities.
- macOS TCC ties permission grants to app identity (bundle ID + signing + path).
- Permission tests are only valid when run from a stable Xcode app target identity.

## One-time setup in Xcode

This repo currently uses Swift Package Manager for development logic/tests. For stable permission testing, create a real macOS app target once and keep using it.

1. Open the project/workspace in Xcode.
2. Create a new macOS app target (SwiftUI App lifecycle).
3. Add existing sources from `app/Sources/TaskAgentMacOS/` to that app target.
4. Remove the generated default `App` file in the new target so `app/Sources/TaskAgentMacOS/AppMain.swift` remains the only `@main` entry point.
5. In target `Signing & Capabilities`:
   - Team: your development team
   - Signing Certificate: `Apple Development`
   - Automatically manage signing: enabled
6. In target `General`:
   - Bundle Identifier: use a stable value (example: `com.farzamh.TaskAgentMacOS`)
7. Keep this target/scheme as the default one for local permission testing.

## Run configuration requirements

1. Launch using Xcode `Run` (same scheme/target each time).
2. Do not switch bundle ID between runs.
3. Do not keep recreating the target/app identity.
4. Do not test permission persistence using `swift run`.

## Release DMG runtime checklist (permission registration)

Use this checklist when validating a release DMG install (not Xcode-run builds):

1. Install by dragging `ClickCherry.app` to `/Applications`.
2. Eject the mounted DMG before launching app for permission checks.
3. Launch `ClickCherry` from `/Applications`.
4. Use app `Open Settings` actions to open each privacy pane.
5. Confirm the app opens System Settings lists directly (no native modal permission popup from the app click path).
6. If a pane does not show `ClickCherry`, relaunch from `/Applications` and retry `Open Settings`.

## Identity diagnostics (must pass)

1. In Xcode, the active scheme must be your macOS App target (not a package executable scheme).
2. In target `Signing & Capabilities`, ensure:
   - Team is selected.
   - `Automatically manage signing` is enabled.
   - Signing Certificate is `Apple Development` (not `Sign to Run Locally`).
3. After build, verify the built app identity from Terminal:
   - `codesign -dv --verbose=4 "<path-to-your-app>.app"`
   - Check that `Identifier=` matches your bundle ID and `Authority=` is present (not ad-hoc).
4. Verify the app has a stable bundle ID:
   - `defaults read "<path-to-your-app>.app/Contents/Info.plist" CFBundleIdentifier`

## Permission walkthrough checklist

1. Launch app from Xcode Run.
2. In the onboarding Permissions step, click `Open Settings` for:
   - Screen Recording
   - Microphone
   - Accessibility
   - Input Monitoring
3. Grant permissions in System Settings.
4. Return to the app:
    - Status updates automatically (within ~0.5s).
5. Confirm UI shows `Granted` for all required permissions.
6. Quit app and run again from Xcode.
7. Confirm permissions remain granted for the same app identity.
8. If the app still does not appear, use `+` in the Screen Recording pane and add the built `.app` from DerivedData manually.

## If permission keeps resetting

1. Verify the active Xcode scheme is still the same app target.
2. Verify bundle identifier did not change.
3. Verify signing team/certificate did not change.
4. Remove duplicate old test identities from:
   - `System Settings > Privacy & Security > Screen & System Audio Recording`
   - `System Settings > Privacy & Security > Accessibility`
5. Re-run once from Xcode and re-grant for the stable identity.
6. If signing remains ad-hoc (`Sign to Run Locally`), recreate/run from a real App target with automatic signing.

## Exit criteria

- Permission state is reproducible across two Xcode runs.
- Onboarding permission gate reflects real granted status and allows continue only when all required permissions are granted/confirmed.
