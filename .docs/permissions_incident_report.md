---
description: Consolidated report of macOS permission failures, root causes, and mitigation strategies used during 2026-02 incident cycle.
---

# Permissions Incident Report (2026-02)

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
- Screen Recording prompt could appear repeatedly and feel stuck.
- Permission toggles in System Settings were not always reflected in app status quickly.
- Input Monitoring frequently did not show `ClickCherry` in the list.
- Behavior varied across macOS versions/devices.

## Root Causes Identified

1. TCC registration race / identity timing:
   - Permission panes could open before OS registration settled for the running app identity.
   - Multiple app copies (DMG mount, Downloads, `/Applications`, Xcode DerivedData) increased mismatch risk.

2. Duplicate request/open paths:
   - Earlier flow combined multiple request/status/open calls in close succession, increasing race probability and prompt churn.

3. Permission-type asymmetry on macOS:
   - Accessibility and Microphone grant models differ from Screen Recording/Input Monitoring.
   - Input Monitoring list appearance is tied to real global-event registration behavior, not only a simple status read.

4. Prompt-loop and polling interaction:
   - Aggressive re-request behavior plus UI polling increased repeated native prompt surfaces.

## Mitigations Implemented

1. Single action path per click:
   - Consolidated permission-row behavior to one request/open flow per user action.

2. Delayed Settings open + retries:
   - Added bounded per-permission settle delay and retry open to reduce early-pane race failures.

3. Passive status polling:
   - Polling paths use passive status checks to avoid accidental prompt re-trigger.

4. Bounded post-click convergence probes:
   - Added delayed recheck probes and short-lived grant cache windows for status convergence after user toggles.

5. Screen Recording prompt-loop reduction:
   - Screen Recording click path hardened toward Settings-first behavior with bounded recheck instead of repeated native request churn.

6. Input Monitoring registration strategy:
   - Added persistent registration attempts (event tap/global monitor lifecycle) to improve list registration opportunity.
   - Also changed product policy to reduce user friction where OS behavior remains inconsistent.

7. Product policy adjustment:
   - Input Monitoring remains present in onboarding, but is no longer enforced as a blocker for recording start or agent run start.
   - If unavailable, run/record continues with reduced Escape-stop capability.

## What Is Fixed vs Outstanding

- Fixed:
  - Recording preflight no longer blocks on Input Monitoring.
  - Agent run no longer blocks on Input Monitoring monitor-start failure.
  - Accessibility remains enforced for agent run preflight.

- Outstanding (OS/runtime-dependent):
  - Input Monitoring list visibility can still be inconsistent across devices.
  - Network transport instability can still cause transient LLM retries/cancellations unrelated to permission state.

## Operational Guidance

1. Run exactly one app copy from `/Applications` during permission grant.
2. Unmount DMG and quit all duplicate app instances before testing.
3. For permission anomalies, reset per-service TCC entries and relaunch.
4. Validate with a release-built app (tag/release artifact), not mixed debug + DMG copies.

## Validation Strategy Used

- Automated:
  - `MainShellStateStoreTests` and `OnboardingStateStoreTests` focused runs.
  - Debug build/test validation for each permission-flow increment.

- Manual:
  - Two-device runtime checks across macOS 26 + macOS 15.
  - Cross-check app-side status against System Settings list/toggles and dialog behavior.

## Notes

- This report is intentionally implementation-focused and non-UI-text specific.
- Related active issue tracking remains in `.docs/open_issues.md`.
