---
description: Consolidated report of macOS permission failures, root causes, and mitigation strategies used during the 2026-02 to 2026-03 incident cycle.
---

# Permissions Incident Report (2026-02 to 2026-03)

## Scope

- App: `ClickCherry` (`TaskAgentMacOSApp`)
- Surface: onboarding permissions step + Settings -> Permissions
- Permissions involved:
  - Screen Recording
  - Microphone
  - Accessibility
  - Input Monitoring

## Symptom Summary

- `Open Settings` could feel slow or inconsistent.
- System Settings opened but `ClickCherry` was sometimes missing from permission lists.
- Screen Recording prompt/list behavior could appear inconsistent or get polluted by old local test app names.
- Microphone could work in local Xcode builds and still fail in the public DMG.
- Permission toggles in System Settings were not always reflected in app status quickly.
- Input Monitoring frequently did not show `ClickCherry` in the list.

## Root Causes Identified

1. TCC registration race / identity timing:
   - Permission panes could open before OS registration settled for the running app identity.
   - Multiple app copies (DMG mount, Downloads, `/Applications`, Xcode DerivedData, renamed backups) increased mismatch risk.

2. Duplicate request/open paths:
   - Earlier flow combined multiple request/status/open calls in close succession, increasing race probability and prompt churn.

3. Permission-type asymmetry on macOS:
   - Accessibility and Microphone grant models differ from Screen Recording/Input Monitoring.
   - Input Monitoring list appearance is tied to real global-event registration behavior, not only a simple status read.

4. Prompt-loop and polling interaction:
   - Aggressive re-request behavior plus UI polling increased repeated native prompt surfaces.

5. Release-signing mismatch for Microphone in hardened-runtime DMGs:
   - Local Xcode builds were signed as `Apple Development` and could show the native microphone prompt.
   - GitHub DMG builds were re-signed as `Developer ID Application` with hardened runtime.
   - The release-signing path originally omitted `com.apple.security.device.audio-input`, so notarized DMGs could fail to trigger the microphone dialog even though local Xcode builds worked.

6. Screen Recording stale path entries during local A/B signing experiments:
   - Screen Recording could retain exact filenames from temporary backup/test `.app` copies.
   - This produced misleading System Settings rows such as renamed backup apps instead of the current `/Applications/ClickCherry.app`.
   - The stale row was a test-environment artifact, not a user-facing bundle-ID identity bug in the final shipped app.

## Mitigations Implemented

1. Single action path per click:
   - Consolidated permission-row behavior to one request/open flow per user action.

2. Bounded settle/recheck behavior:
   - Kept bounded convergence checks where needed without re-triggering native prompts during passive polling.

3. Product policy adjustment:
   - Input Monitoring remains present in onboarding, but is no longer enforced as a blocker for recording start or agent run start.
   - If unavailable, run/record continues with reduced Escape-stop capability.

4. Hardened-runtime microphone entitlement fix:
   - Added `/Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp/ClickCherry.entitlements`.
   - Included `com.apple.security.device.audio-input` in both:
     - Xcode app-target signing
     - GitHub release workflow `codesign --options runtime --entitlements ...`
   - Added a release-workflow check that fails if the final signed app is missing the microphone entitlement.

5. In-flight microphone request-state preservation:
   - Prevented onboarding/settings refresh logic from changing the microphone CTA mid-request.
   - Removed the misleading `Grant Access -> Open Settings` flip that could happen before macOS resolved the native prompt request.

6. Clean-slate DMG validation discipline:
   - Deleted duplicate local app variants before public-artifact testing.
   - Reset `ScreenCapture` globally and reset bundle-specific `Microphone`, `Accessibility`, and `ListenEvent` state before end-to-end DMG tests.

## What Is Fixed vs Outstanding

- Fixed:
  - Public `v0.1.44` DMG installs now show the native microphone prompt from a clean install/reset path.
  - Public `v0.1.44` DMG installs now preserve the expected microphone CTA while a live permission request is in flight.
  - Screen Recording stale-name confusion was explained and mitigated by cleaning duplicate app copies and using a global `tccutil reset ScreenCapture`.
  - Recording preflight no longer blocks on Input Monitoring.
  - Agent run no longer blocks on Input Monitoring monitor-start failure.
  - Accessibility remains enforced for agent run preflight.

- Outstanding (OS/runtime-dependent):
  - Input Monitoring list visibility can still be inconsistent across devices.
  - Network transport instability can still cause transient LLM retries/cancellations unrelated to permission state.

## Operational Guidance

1. Run exactly one app copy from `/Applications` during permission grant.
2. Unmount DMG and quit all duplicate app instances before testing.
3. Validate permission-sensitive bugs with the GitHub DMG, not only local Xcode builds.
4. For Screen Recording anomalies after local signing experiments, prefer a global `tccutil reset ScreenCapture` plus clean reinstall over bundle-specific resets.
5. For Microphone anomalies, treat the native macOS dialog as the required first-registration path; there is no manual `+` add flow in System Settings.

## Validation Strategy Used

- Automated:
  - `MainShellStateStoreTests` and `OnboardingStateStoreTests` focused runs.
  - Release build/test validation after entitlements were wired into both Xcode and the release workflow.

- Manual:
  - Two-device runtime checks across macOS 26 + macOS 15.
  - Cross-check app-side status against System Settings list/toggles and dialog behavior.
  - A/B runtime-signing experiments:
    - hardened runtime without mic entitlement: DMG-style microphone failure
    - hardened runtime with mic entitlement: native prompt succeeds
    - non-runtime local signing: native prompt succeeds
  - Clean-slate GitHub DMG reinstall for `v0.1.44` after deleting all local variants and resetting Screen Recording globally.

## Notes

- This report is intentionally implementation-focused and non-UI-text specific.
- Related historical issue tracking remains in `.docs/open_issues.md`.
