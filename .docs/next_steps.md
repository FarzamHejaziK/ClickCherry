---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Publish `v0.1.29` GitHub release (in progress).
2. Why now: User requested creating a new release with current UI/installer/icon updates.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/CHANGELOG.md` with `0.1.29` release notes dated 2026-02-22.
  - Prepare release commit + `v0.1.29` tag push to trigger `/Users/farzamh/code-git-local/task-agent-macos/.github/workflows/release.yml`.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-release-preflight CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-22).
5. Manual tests:
  - Pending release workflow completion check on GitHub Actions.
6. Exit criteria:
  - Tag `v0.1.29` is pushed and GitHub Release workflow starts successfully.

1. Step: Ship DMG background without instruction text and with icon-based install arrow (in progress).
2. Why now: User requested removing text labels from DMG installer artwork and replacing the typed `>` with a cleaner icon.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/.github/workflows/release.yml`:
    - removed DMG background title/subtitle text drawing.
    - replaced text chevron with symbol-rendered `chevron.right.circle.fill` and subtle glow.
    - preserved existing icon coordinates and DMG layout mechanics.
4. Automated tests:
  - `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "release.yml ok"'` (pass on 2026-02-22).
5. Manual tests:
  - `awk '/cat > "\\$DMG_BG_SCRIPT" <<\\x27SWIFT\\x27/{flag=1;next}/^          SWIFT$/{flag=0}flag' .github/workflows/release.yml > /tmp/make_dmg_background_preview.swift`
  - `swift /tmp/make_dmg_background_preview.swift /tmp/dmg-background-preview.png`
  - `sips -g pixelWidth -g pixelHeight /tmp/dmg-background-preview.png` (generated successfully; `1520x960`).
  - Pending user visual confirmation on next DMG artifact.
6. Exit criteria:
  - User confirms the released DMG background has no text and uses the new icon-based direction cue.

1. Step: Validate Dock icon optical-size normalization across macOS 15 and macOS 26 (in progress).
2. Why now: User reported the app icon appears larger than neighboring Dock icons on macOS 15 while looking normal on macOS 26.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Assets.xcassets/AppIcon.appiconset/icon_16x16.png`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Assets.xcassets/AppIcon.appiconset/icon_32x32.png`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Assets.xcassets/AppIcon.appiconset/icon_128x128.png`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Assets.xcassets/AppIcon.appiconset/icon_256x256.png`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Assets.xcassets/AppIcon.appiconset/icon_512x512.png`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`.
  - Regenerated all slots from a single adjusted 1024 master to keep per-size rendering consistent.
  - Refined rounded-rectangle alpha mask to increase corner roundness based on user visual feedback.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-icon-fix CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-22).
5. Manual tests:
  - Launched `/tmp/taskagent-dd-icon-fix/Build/Products/Debug/ClickCherry.app`, confirmed process startup via `pgrep`, then terminated app.
  - Pending user-side Dock visual confirmation on both macOS 15 and macOS 26.
6. Exit criteria:
  - User confirms Dock icon size appears visually aligned with neighboring apps on macOS 15 and remains acceptable on macOS 26.

1. Step: Keep Input Monitoring hidden in onboarding/settings permissions UI unless reintroduced intentionally (in progress).
2. Why now: User requested removing Input Monitoring permission from onboarding and settings for now.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Onboarding/Pages/PermissionsStepView.swift`:
    - removed `Input Monitoring` row from onboarding permissions panel.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/SettingsPageView.swift`:
    - removed `Input Monitoring` row from settings permissions panel.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/OnboardingStateStore.swift`:
    - removed Input Monitoring from onboarding required-permissions gating.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSAppTests/OnboardingStateStoreTests.swift`:
    - aligned permission-step expectations with new required set.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-22; 89 tests).
5. Manual tests:
  - Launched `/tmp/taskagent-dd-ci-test/Build/Products/Debug/ClickCherry.app`, confirmed startup, then terminated app.
  - Pending user-side visual confirmation that onboarding/settings no longer show Input Monitoring rows.
6. Exit criteria:
  - User confirms Input Monitoring is absent in onboarding/settings and onboarding continues when Screen Recording, Microphone, and Accessibility are granted.

1. Step: Keep temporary Settings reset controls removed pending future re-introduction decision (in progress).
2. Why now: The temporary reset toggle/action in `Settings > Model Setup` was developer-only and was requested to be removed from current UI.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/SettingsPageView.swift`:
    - removed `Temporary Reset Toggle` section.
    - removed `Enable temporary full reset` toggle state binding and UI control.
    - removed `Run Temporary Reset (Clear Keys + Onboarding)` UI action.
    - preserved `Start Over (Show Onboarding)` behavior.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-22; 89 tests).
5. Manual tests:
  - Launched `/tmp/taskagent-dd-ci-test/Build/Products/Debug/ClickCherry.app`, confirmed process startup, then terminated app.
  - Pending user-side UI confirmation that Settings no longer shows the temporary reset controls.
6. Exit criteria:
  - User confirms the temporary reset controls remain hidden in Settings and no regression is observed in model setup view.

1. Step: Publish permission-stability release and validate on two Macs (in progress).
2. Why now: Recent fixes removed Input Monitoring as a runtime blocker and reduced Screen Recording prompt-loop friction; release validation is needed on real DMG installs.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift`:
    - recording preflight no longer blocks on Input Monitoring.
    - run-task startup no longer aborts when Escape monitor cannot start (run continues).
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSAppTests/MainShellStateStoreTests.swift`:
    - adjusted preflight and monitor-failure expectations to match optional Input Monitoring runtime policy.
  - Added consolidated incident report:
    - `/Users/farzamh/code-git-local/task-agent-macos/.docs/permissions_incident_report.md`.
4. Automated tests:
  - `xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -configuration Debug build` (pass on 2026-02-22).
  - `xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -configuration Debug test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-22).
5. Manual tests:
  - Pending user-side release DMG validation on both devices:
    - onboarding still shows Input Monitoring row.
    - recording can start when Input Monitoring is not granted.
    - agent run can start when Input Monitoring is not granted.
    - Accessibility remains required for agent run.
6. Exit criteria:
  - GitHub release published and two-device DMG validation confirms runtime no longer hard-blocks on Input Monitoring while onboarding visibility remains intact.

1. Step: Validate Screen Recording settings-only click flow to eliminate repeated native dialog loops (in progress).
2. Why now: User confirmed dialog-loop failure remains in `v0.1.26` (`Open Settings` can repeatedly surface the Screen Recording native prompt and onboarding stays blocked).
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/PermissionService.swift`:
    - Screen Recording polling path stays check-only (`CGPreflightScreenCaptureAccess`) with no request API call.
    - Screen Recording click path now avoids native request and uses Settings-only open behavior with passive bounded recheck probes.
    - preserved existing UI text/copy.
4. Automated tests:
  - `xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -configuration Debug build` (pass on 2026-02-22).
  - `xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -configuration Debug test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-22).
5. Manual tests:
  - Local smoke: launched `/Users/farzamh/Library/Developer/Xcode/DerivedData/TaskAgentMacOSApp-hcmwhqcntcyxesavzhrufsmixgfu/Build/Products/Debug/ClickCherry.app`, confirmed startup, terminated debug instance.
  - Pending user-side runtime verification from GitHub release DMG:
    - Screen Recording click no longer traps user in repeated native dialog.
    - granted toggle in Settings converges to `Granted` state in onboarding.
6. Exit criteria:
  - User confirms no repeated Screen Recording dialog loop and status convergence after Settings toggle.

1. Step: Validate bounded post-click permission sync behavior on two macOS devices using GitHub release build (in progress).
2. Why now: User reported that permissions can be granted in System Settings while onboarding still shows `Not Granted`, with repeated/sticky Screen Recording dialogs and missing Input Monitoring row.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/PermissionService.swift`:
    - removed passive screen-recording probe churn from polling path.
    - added bounded Screen Recording recheck probes after user click (`1.2s`, `3.5s`, `8.0s`).
    - added temporary Screen Recording grant cache (`180s`) for in-process status convergence.
    - increased Input Monitoring registration keepalive to `30s` and added temporary grant cache (`180s`).
    - kept UI copy unchanged.
4. Automated tests:
  - `xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -configuration Debug build` (pass on 2026-02-22).
  - `xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -configuration Debug test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-22).
5. Manual tests:
  - Local smoke: launched `/Users/farzamh/Library/Developer/Xcode/DerivedData/TaskAgentMacOSApp-hcmwhqcntcyxesavzhrufsmixgfu/Build/Products/Debug/ClickCherry.app`, confirmed process startup, terminated debug instance.
  - Pending user-side two-device runtime checks from GitHub release DMG:
    - Screen Recording: prompt does not loop; granted state flips in-app.
    - Microphone: click is deterministic (no no-op path).
    - Accessibility: remains stable.
    - Input Monitoring: row appears and can be granted.
6. Exit criteria:
  - Two-device runtime validation confirms all four permission rows register and app-side statuses converge without repeated prompt loops.

1. Step: Validate two-device permission registration behavior after deeper TCC registration fixes (in progress).
2. Why now: User reproduced mismatched behavior across macOS 26 and macOS 15, including missing privacy-list rows and a microphone click no-op.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/PermissionService.swift`:
    - restored longer permission-pane settle delays and retries.
    - always opens target Settings pane when permission is already granted (all four permissions).
    - switched Input Monitoring probe to run-loop-backed event-tap burst probing.
    - switched Screen Recording probe to ScreenCaptureKit-only capture path.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/DesktopScreenshotService.swift`:
    - added `captureMainDisplayPNGScreenCaptureKitOnly(...)` for registration-only probing without CLI fallback.
  - Constraint honored:
    - no UI text changes in onboarding/settings permission surfaces for this increment.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-perm-fix-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-22 local run; 37 tests passed).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -configuration Release -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-release-perm-signed build` (pass on 2026-02-22 local run; signed with local Apple Development identity).
5. Manual tests:
  - Local smoke: launched `/tmp/taskagent-dd-perm-fix-test/Build/Products/Debug/ClickCherry.app`, confirmed process startup, then terminated test instance.
  - Local smoke: launched `/tmp/taskagent-dd-release-perm-signed/Build/Products/Release/ClickCherry.app`, confirmed process startup, then terminated test instance.
  - Packaged local release artifacts for user runtime validation:
    - `/tmp/ClickCherry-macos-permission-fix-2026-02-22-signed.zip`
    - `/tmp/ClickCherry-macos-permission-fix-2026-02-22-signed.dmg`
  - Gatekeeper note: this local build is Apple-Development signed but not notarized; first launch on secondary devices may require right-click -> Open.
  - Pending user-side validation on both devices from `/Applications` install path.
6. Exit criteria:
  - On both macOS 26 and macOS 15 test machines, `ClickCherry` consistently appears in Screen Recording, Microphone, Accessibility, and Input Monitoring lists after row actions, with no microphone click no-op.

1. Step: Validate deterministic permission click behavior without UI copy changes (in progress).
2. Why now: User reported high friction in permission onboarding/settings and requested behavior fixes while keeping existing permission-screen text unchanged.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/PermissionService.swift`:
    - removed first-click session gating that previously deferred Settings open for Screen Recording, Accessibility, and Input Monitoring.
    - now runs request/probe and opens target Settings pane in the same click when still not granted.
    - kept first-time native Microphone prompt behavior for `.notDetermined`, with Settings fallback for denied/restricted.
    - reduced open-delay and retry timing to improve responsiveness.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-perm-fast-open build` (pass on 2026-02-21 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-perm-fast-open-tests test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-21 local run).
5. Manual tests:
  - Local smoke: launched `/tmp/taskagent-dd-perm-fast-open/Build/Products/Debug/ClickCherry.app` and confirmed process startup.
  - Pending user-side runtime checks on DMG-installed app from `/Applications`:
    - one click on `Screen Recording`, `Accessibility`, `Input Monitoring` opens target Settings pane.
    - `Microphone` first-time prompt behavior is preserved.
    - app appears in all required privacy lists after grant.
6. Exit criteria:
  - Permission onboarding/settings no longer requires extra clicks for Screen Recording, Accessibility, and Input Monitoring, and runtime DMG validation confirms consistent list visibility.

1. Step: Validate release artifact naming update (versioned DMG filename) on next tagged release run (in progress).
2. Why now: User requested versioned DMG names and clarified that release page should emphasize DMG-only uploaded artifact.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/.github/workflows/release.yml`:
    - DMG output name now includes tag version (for example `ClickCherry-macos-v0.1.23.dmg`).
    - release artifact upload path switched to `ClickCherry-macos-*.dmg`.
    - release notes artifact line now references the versioned DMG name.
    - publish step now releases `ClickCherry-macos-*.dmg`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/docs/release-process.md` to document versioned DMG naming and clarify GitHub source archives cannot be removed.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/.docs/open_source.md` release strategy wording to match versioned DMG output.
4. Automated tests:
  - `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "release.yml ok"'` (pass on 2026-02-21 local run).
5. Manual tests:
  - Pending next tag-based release verification:
    - release asset filename includes version (for example `ClickCherry-macos-vX.Y.Z.dmg`).
    - uploaded workflow artifact is DMG-only.
    - GitHub platform source archives are still visible (expected platform behavior).
6. Exit criteria:
  - Next release run publishes a versioned DMG filename and release notes reflect the same artifact name.

1. Step: Validate DMG-installed permission registration visibility after follow-up non-AX registration hardening (in progress).
2. Why now: User confirmed follow-up failure where only Accessibility showed `ClickCherry`; Screen Recording, Microphone, and Input Monitoring still missed the app row after `Open Settings`.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/PermissionService.swift`:
    - increased registration-settle delays and open retries for privacy-pane navigation.
    - added screen recording registration probe (best-effort screenshot capture path).
    - added microphone registration probe (best-effort short-lived capture session path).
    - added input monitoring burst probe (event tap + global monitor with delayed second pass).
    - switched to mixed policy: re-enabled native prompts where needed for registration, while avoiding first-click prompt/settings overlap.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/OnboardingStateStore.swift`:
    - changed `refreshPermissionStatus` to passive `currentStatus` reads so polling never triggers native permission dialogs.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Onboarding/Pages/PermissionsStepView.swift`:
    - added follow-up helper text instructing relaunch from `/Applications` and retry of `Open Settings` when rows are missing.
    - updated helper text to explain Settings-list grant flow.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/SettingsPageView.swift`:
    - added the same retry guidance copy in Settings -> Permissions.
    - updated helper text to explain Settings-list grant flow.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-perm-dialog-deconflict-build build` (pass on 2026-02-21 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-perm-dialogless-test test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-21 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-perm-required-dialogs test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-21 local run).
5. Manual tests:
  - Pending user-side runtime checks on DMG-installed app:
    - ensure app is launched from `/Applications`.
    - click each permission row and confirm `ClickCherry` appears in corresponding privacy list.
    - relaunch and repeat to confirm consistency.
6. Exit criteria:
  - Permission rows consistently surface `ClickCherry` in target macOS privacy panes for DMG-installed runtime.

1. Step: Validate temporary Settings full-reset toggle with TCC reset + app relaunch in runtime (in progress).
2. Why now: User reported that the temporary reset did not actually clear permissions, so the flow was hardened to reset TCC entries and relaunch the app for permission-state refresh.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/SettingsPageView.swift`.
  - Added temporary guarded control in Model Setup:
    - toggle gate: `Enable temporary full reset`
    - action button: `Run Temporary Reset (Clear Keys + Onboarding)` (disabled until toggle enabled).
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift` with `resetSetupAndReturnToOnboarding()` to:
    - clear OpenAI/Gemini keys
    - force onboarding reset
    - attempt TCC permission resets for app bundle ID
    - relaunch app on successful permission reset.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-temp-reset2 -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-21 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - open Settings -> Model Setup.
    - confirm reset button is disabled until toggle is enabled.
    - enable toggle, run reset, and confirm app relaunches then onboarding restarts from welcome.
    - confirm OpenAI/Gemini saved state is cleared.
    - confirm permission pills require re-grant after relaunch.
6. Exit criteria:
  - Temporary toggle reliably resets onboarding + keys and re-triggers permission onboarding after relaunch.

1. Step: Validate post-launch app-window relocation for cross-display `open_app`/`open_url` scenarios (in progress).
2. Why now: User still reproduces wrong-display app activation when the target app is already open on another monitor before run start.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/DesktopActionExecutor.swift`.
  - Added AX-based post-launch relocation:
    - `openApp(named:)` now activates and repositions the target app's front window onto the display currently under the anchored pointer (selected run display context).
    - `openURL(_:)` now repositions the resulting frontmost regular app window to the same display context after URL open.
  - Kept failure mode non-blocking: if AX window mutation is unavailable for a specific app/window state, app launch still succeeds.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-21 local run).
5. Manual tests:
  - Pending user-side runtime checks on 2+ displays:
    - pre-open Chrome on Display 1.
    - set run display to Display 2 and trigger a run with `open_app` Chrome action.
    - confirm Chrome activates/moves to Display 2 before subsequent agent actions.
    - repeat inverse direction (pre-open on Display 2, run on Display 1).
6. Exit criteria:
  - App launches/URL opens no longer remain pinned to the previous display when app windows already exist on another monitor.

1. Step: Validate temporary run-log screenshot visibility for multi-display drift debugging (in progress).
2. Why now: User requested temporary screenshot thumbnails directly in run logs to inspect where the agent is actually acting.
3. Code tasks:
  - Wired OpenAI runner `screenshotLogSink` into `MainShellStateStore` runtime state:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift`
  - Added per-run in-memory screenshot buckets (`runScreenshotLogByRunID`) for active runs only.
  - Added temporary screenshot strip rendering under run logs:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/TaskDetailPageView.swift`
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-run-screenshots build` (pass on 2026-02-21 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-run-screenshots test -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests` (pass on 2026-02-21 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - start a run and expand the newest run disclosure; confirm screenshot thumbnails are visible under logs.
    - verify screenshots correspond to where the agent is actually acting.
6. Exit criteria:
  - User confirms screenshot strip helped validate display/action drift; then remove this temporary debug surface.

1. Step: Validate multi-display task execution stays on selected run screen after run-start focus handoff and launch-settle hardening (in progress).
2. Why now: User still observed actions surfacing on the other monitor (app launcher/app open), even after overlay/screenshot display fixes.
3. Code tasks:
  - Updated run desktop preparation to preserve + activate Finder after hiding other regular apps so frontmost context is not left on the app window’s previous display:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift`
  - Added pre-launch focus-settle delay after selected-display anchor for `open_app` and `open_url`:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/OpenAIAutomationEngine.swift`
  - Added selected-display focus priming for global Spotlight shortcut path (`cmd+space`) before shortcut injection:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/OpenAIAutomationEngine.swift`
  - Added regression coverage:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests.swift`
    - `runToolLoopPrimesDisplayBeforeCmdSpaceShortcut`
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-display-rootcause-fix-r4 test -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-21 local run).
5. Manual tests:
  - Pending user-side runtime checks on 2+ displays:
    - run task on display A, verify launcher/app-open actions happen on display A.
    - run task on display B, verify launcher/app-open actions happen on display B.
    - verify no unexpected app-switcher/launcher UI appears on the non-selected monitor during run.
6. Exit criteria:
  - No cross-screen drift for app/launcher actions during repeated runs on both displays.

1. Step: Validate run-history numbering in Runs panel after descending-label fix (in progress).
2. Why now: User reported numbering semantics were reversed relative to visible newest-first ordering.
3. Code tasks:
  - Updated run label calculation:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/TaskDetailPageView.swift`
  - Labels now use `Run (totalRuns - idx)` so top row is the latest/highest run number.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-run-label-fix build` (pass on 2026-02-21 local run).
5. Manual tests:
  - Pending user-side runtime check:
    - open any task with 2+ runs and confirm numbering decreases top to bottom.
6. Exit criteria:
  - Runs panel numbering matches newest-first list order semantics (latest run has highest number at top).

1. Step: Validate multi-display run/record overlay targeting after stable display-ID fix (in progress).
2. Why now: User reported run-task HUD and red border appearing on different screens despite selecting a single screen.
3. Code tasks:
  - Updated stable display modeling and screencapture-index mapping:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/RecordingCaptureService.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift`
  - Updated run HUD overlay targeting:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/AgentControlOverlayService.swift`
  - Updated display picker thumbnail loading to use explicit screencapture indexes:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/NewTaskPageView.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/TaskDetailPageView.swift`
  - Added regression coverage:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSAppTests/MainShellStateStoreTests.swift` (`startRunTaskNowUsesSelectedDisplayScreencaptureIndexForBothOverlays`).
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-display-fix build` (pass on 2026-02-21 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-display-fix test -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-21 local run).
5. Manual tests:
  - Pending user-side runtime checks on 2+ displays:
    - choose each run display and confirm `Agent is running` HUD + red border stay on the same selected display.
    - choose each recording display and confirm red border + produced recording target the same selected display.
6. Exit criteria:
  - No remaining cross-screen mismatch between selected display and run/record overlays/capture output.

1. Step: Validate LLM transport hardening + new provider-error canvases in local runtime (in progress).
2. Why now: LLM calls now use a fresh session per request and provider-specific actionable errors; runtime confirmation is needed for VPN-heavy scenarios.
3. Code tasks:
  - Added decision record:
    - `/Users/farzamh/code-git-local/task-agent-macos/.docs/LLM_calls_hardening.md`
  - Added normalized provider error model:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/LLMUserFacingIssue.swift`
  - Added UI canvas for actionable LLM failures:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/LLMUserFacingIssueCanvasView.swift`
  - Updated OpenAI/Gemini transport and mapping:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/OpenAIAutomationEngine.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/GeminiVideoLLMClient.swift`
  - Updated run/extraction state + UI wiring:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/TaskDetailPageView.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/RecordingFinishedDialogView.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/MainShellView.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Previews/RootViewPreviews.swift`
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-llm-hardening build` (pass on 2026-02-21 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-llm-hardening test -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests -only-testing:TaskAgentMacOSAppTests/GeminiVideoLLMClientTests` (pass on 2026-02-21 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - run-task flow: validate invalid credentials, rate limit, quota, and billing/tier errors render the canvas with expected actions.
    - recording extraction flow: validate same four classes render in the recording-finished dialog.
    - preview inspection: verify `LLM Issue - *` canvases in `RootViewPreviews`.
6. Exit criteria:
  - Fresh-session transport behavior is confirmed stable in repeated VPN-on runs and all four provider error classes are shown via canvas with actionable remediation paths.

1. Step: Validate run-task preflight dialog behavior in runtime (in progress).
2. Why now: Run-task gating changed to a combined preflight flow (OpenAI key + Accessibility) and needs user-side interaction confirmation.
3. Code tasks:
  - Added `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RunTaskPreflightDialogCanvasView.swift`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift` with `RunTaskPreflightDialogState` and missing-item checks.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/MainShellView.swift` to present run-task preflight as a sheet.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Previews/RootViewPreviews.swift` with `Run Task Preflight Dialog` preview.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-run-preflight build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-run-preflight test -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - click `Run task` with missing OpenAI key -> run preflight appears with OpenAI row only.
    - click `Run task` with key present but Accessibility missing -> run preflight appears with Accessibility row only.
    - resolve both items and click `Check again` -> run starts.
6. Exit criteria:
  - Run-task setup is gated by the new combined preflight dialog and old duplicated permission/key gates are no longer used for run start.

1. Step: Validate new extraction progress canvas in runtime and finalize sizing if needed (in progress).
2. Why now: User requested a more visible modern extraction progress indicator and a canvas preview.
3. Code tasks:
  - Added `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/TaskExtractionProgressCanvasView.swift`.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/RecordingFinishedDialogView.swift` to use animated extraction canvas overlay.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Previews/RootViewPreviews.swift` with:
    - `Recording Finished Dialog (Extracting)`
    - `Extraction Progress Canvas`.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-extraction-progress test -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - trigger extraction from recording-finished dialog and confirm new progress canvas is visible/legible.
    - open `RootViewPreviews` and verify `Extraction Progress Canvas` animation.
6. Exit criteria:
  - Extraction progress surface is clearly visible and accepted in both preview and runtime.

1. Step: Validate recording border visibility + target consistency after display-refresh/overlay hardening (in progress).
2. Why now: User reported missing red border during recording after display-target mapping changes.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/ScreenDisplayIndexService.swift`:
    - stopped using `NSScreen.main` for index ordering
    - mapped `Display 1` to `CGMainDisplayID()` and preserved AppKit order for remaining displays.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift`:
    - refresh/validate selected display at record-start time before showing border and launching capture.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/RecordingOverlayService.swift`:
    - use higher window level for the border overlay
    - fallback to first available screen if index resolution fails.
  - Added `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSAppTests/ScreenDisplayIndexServiceTests.swift`.
  - Added `startCapture` invalid-selection regression test in `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSAppTests/MainShellStateStoreTests.swift`.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/ScreenDisplayIndexServiceTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks on 2+ displays:
    - start recording on each display and confirm red border is visible on that display.
    - confirm border and recorded video match the same physical display.
6. Exit criteria:
  - Border is visible during recording and no display mismatch remains across at least one full record/stop cycle per display option.

1. Step: Force preflight sheet dismissal on primary actions and disable backdrop hit-testing (completed, pending runtime confirmation).
2. Why now: User still observed non-working actions despite prior modal rendering fixes.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - backdrop set to non-hit-testable
    - `Not now` and `Open Settings` now call both state action + SwiftUI sheet dismiss.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks for button responsiveness.
6. Exit criteria:
  - `Not now` and `Open Settings` always respond and close dialog deterministically.

1. Step: Remove white sheet host box and restore preflight button hit-testing (completed, pending runtime confirmation).
2. Why now: User reported white box behind dialog and continued non-working buttons.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/MainShellView.swift`:
    - applied transparent presentation background for preflight sheet.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - set decorative overlays to non-hit-testable.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - white host box no longer visible
    - dialog buttons are clickable.
6. Exit criteria:
  - Dialog appears without white host box and controls are interactive.

1. Step: Move recording preflight dialog to native sheet presentation for reliable interactivity (completed, pending runtime confirmation).
2. Why now: Multiple fixes to custom overlay hit-testing did not resolve user-reported non-interactive controls.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/MainShellView.swift`:
    - moved recording preflight presentation to `.sheet(isPresented:)`
    - removed recording preflight from root `ZStack` overlay branch.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - added `showsBackdrop` flag so same component can render cleanly inside sheet context.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local rerun; first run hit transient test-bundle creation error).
5. Manual tests:
  - Pending user-side runtime checks:
    - verify typing in Gemini field
    - verify all buttons respond
    - verify dismiss path via `Not now`.
6. Exit criteria:
  - Preflight dialog controls are fully interactive in runtime.

1. Step: Disable preflight backdrop tap-dismiss to restore control interactivity (completed, pending runtime confirmation).
2. Why now: User still reported no interactive controls; outside-tap gesture path remained a likely event-routing conflict.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - removed backdrop tap-to-dismiss gesture
    - rely on explicit dialog actions for dismissal/continue.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - verify all dialog controls are clickable/editable.
    - verify `Not now` dismisses dialog.
6. Exit criteria:
  - Dialog controls are fully interactive in runtime.

1. Step: Rehost recording preflight modal as root ZStack layer and restore outside-click dismiss (completed, pending runtime confirmation).
2. Why now: User still reported full dialog non-interactivity and inability to return by clicking outside dialog area.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/MainShellView.swift`:
    - moved preflight/missing-key modal presentation from `.overlay` to root `ZStack` top layer.
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - backdrop tap now dismisses dialog
    - dialog surface consumes taps to avoid accidental outside-dismiss while interacting inside.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local rerun; first run hit transient test-bundle creation error).
5. Manual tests:
  - Pending user-side runtime checks:
    - verify typing in Gemini field works
    - verify preflight buttons respond
    - verify clicking outside dialog dismisses modal.
6. Exit criteria:
  - Dialog is fully interactive and outside-click dismiss works.

1. Step: Harden recording preflight dialog hit-testing so controls remain interactive (completed, pending runtime confirmation).
2. Why now: User still reported non-interactive dialog despite prior interaction fix.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - set backdrop dim layer to non-hit-testable
    - explicitly enabled hit-testing on dialog card
    - added explicit content shape for stable event targeting
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks for clickable buttons and editable Gemini field.
6. Exit criteria:
  - Dialog controls are fully interactive in runtime.

1. Step: Restore interactivity in recording preflight dialog controls (completed, pending runtime confirmation).
2. Why now: User reported that buttons were non-functional and API key field was not editable.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - removed backdrop tap gesture that could intercept dialog interactions
    - constrained inline key messages to Gemini-specific messages in Gemini row
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - click `Not now`, `Check again`, `Open Settings`, and `Save` and confirm each action responds.
    - place cursor in Gemini key field and verify typing/paste works.
6. Exit criteria:
  - Preflight dialog is fully interactive and accepts Gemini key input.

1. Step: Compact recording preflight action widths and align footer actions to inner grid (completed, pending runtime visual confirmation).
2. Why now: User reported buttons were too wide and footer action alignment still looked awkward.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - reduced action widths
    - aligned footer action row (`Not now`, `Check again`) to panel content insets
    - retained `Save` and `Open Settings` width parity
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local rerun; first run hit transient test-bundle creation error).
5. Manual tests:
  - Pending user-side runtime visual check that footer actions now feel balanced.
6. Exit criteria:
  - Footer action alignment is visually balanced and button widths are no longer oversized.

1. Step: Equalize visual button widths in recording preflight dialog (completed, pending runtime visual confirmation).
2. Why now: User reported that `Save` vs `Open Settings` and `Not now` vs `Check again` looked awkward and misaligned.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - made `Save` and `Open Settings` share identical visible width
    - made `Not now` and `Check again` share identical visible width
    - adjusted button label/frame ordering so style capsule width is truly fixed
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime visual check in dialog preview/runtime.
6. Exit criteria:
  - Top and footer action buttons have equal visual widths and appear balanced.

1. Step: Fix recording preflight row alignment and Gemini key entry layout to match requested design (completed, pending runtime visual confirmation).
2. Why now: User feedback reported remaining alignment issues and requested Gemini key entry pattern without saved/unsaved status tag.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - enforced one shared right action-column width for `Save` and `Open Settings` buttons
    - switched Gemini entry row to icon + input field with eye/paste controls and no status pill
    - retained missing-only requirement rendering and existing dialog actions
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - confirm row/button alignment matches expected reference
    - confirm Gemini input row style is accepted (no saved/unsaved tag)
6. Exit criteria:
  - Dialog layout and Gemini entry row match the requested alignment/style pattern.

1. Step: Finalize recording preflight dialog styling to match Settings/button patterns (completed, pending runtime visual confirmation).
2. Why now: Latest user review flagged visual mismatch with Settings and non-standard button treatments in the new preflight dialog.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`:
    - aligned panel/dialog structure with settings-style material cards and separators
    - standardized all dialog actions (`Not now`, `Check again`, `Open Settings`, `Save`) to `ccPrimaryActionButton()`
    - tuned heading/body typography to match existing shell dialog rhythm
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - open preflight dialog and confirm visual language matches Settings page cards/buttons.
    - confirm `Check again`/`Open Settings`/`Save` actions remain functional.
6. Exit criteria:
  - Recording preflight dialog is visually and interactionally consistent with existing Settings/UI button patterns.

1. Step: Ship combined recording preflight dialog for missing setup items (completed, pending runtime confirmation).
2. Why now: Users needed one place to resolve recording prerequisites instead of separate prompts and fragmented settings checks.
3. Code tasks:
  - Added aggregated recording preflight state and gating in:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift`
    - `startCapture()` now blocks and opens combined dialog when any required item is missing.
  - Added new dialog UI:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreflightDialogCanvasView.swift`
    - includes missing-only requirement rows, inline Gemini key save, and per-permission settings links.
  - Wired dialog overlay in:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/MainShellView.swift`
  - Added/updated tests:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSAppTests/MainShellStateStoreTests.swift`
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-recpreflight-build2 build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-recpreflight-test2 test -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime checks:
    - with missing Gemini + permissions, click Record and confirm combined dialog appears.
    - grant/save items one by one and confirm resolved items disappear from dialog.
    - click `Check again` and confirm capture starts only when all required items are satisfied.
6. Exit criteria:
  - Recording start path has one combined preflight dialog that shows only missing requirements.

1. Step: Harden Input Monitoring registration from permission actions (completed, pending runtime confirmation).
2. Why now: Users still reported that clicking Input Monitoring did not show `ClickCherry` in the privacy list.
3. Code tasks:
  - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/PermissionService.swift`:
    - after `CGRequestListenEventAccess()`, perform a temporary event-tap probe to force the same API path used by Escape monitoring.
    - increased delayed Settings-open timing for Input Monitoring from `0.35s` to `0.8s`.
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-inputmon-build build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-inputmon-test test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime validation:
    - click `Input Monitoring` in preflight/settings.
    - verify `ClickCherry` appears in `Privacy & Security > Input Monitoring`.
6. Exit criteria:
  - Clicking Input Monitoring permission action reliably results in visible `ClickCherry` entry in the Input Monitoring list.

1. Step: Fix permissions preflight so ClickCherry is registered before opening Microphone/Input Monitoring panes (completed, pending runtime confirmation).
2. Why now: Users can click preflight permission actions and still not see `ClickCherry` in the target macOS list, creating setup confusion.
3. Code tasks:
  - Updated permission request/open flow:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/PermissionService.swift`
    - added `requestAccessAndOpenSystemSettings(for:)`.
    - microphone now requests first and opens Settings after the user responds.
    - input monitoring now requests first and opens Settings after a short delay.
  - Updated callers:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/OnboardingStateStore.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift`
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-permfix-build build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-permfix-test test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime validation:
    - click `Microphone (Voice)` in preflight and verify `ClickCherry` appears in `Privacy & Security > Microphone`.
    - click `Input Monitoring` in preflight and verify `ClickCherry` appears in `Privacy & Security > Input Monitoring`.
6. Exit criteria:
  - Preflight permission clicks reliably register `ClickCherry` in the relevant macOS privacy list.

1. Step: Add missing-provider-key preflight dialogs for extraction and run (completed, pending runtime confirmation).
2. Why now: Users can trigger extraction/run without required provider keys, which leads to avoidable failures and unclear recovery paths.
3. Code tasks:
  - Updated key-preflight and routing state:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift`
    - added shared missing-key dialog state model and key guards for Gemini extraction + OpenAI run.
    - added redirect action to Settings (`openSettingsForMissingProviderKeyDialog()`).
  - Added modern shared modal canvas:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/MissingProviderKeyDialogCanvasView.swift`
  - Wired dialog presentation in shell + recording-finished sheet:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/MainShellView.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/RecordingFinishedDialogView.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Previews/RootViewPreviews.swift`
  - Added/updated tests:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSAppTests/MainShellStateStoreTests.swift`
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-missingkeys-build CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-20 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-missingkeys-test3 -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-20 local run).
5. Manual tests:
  - Pending user-side runtime validation:
    - from recording flow, click `Extract task` with no Gemini key and confirm dialog appears and `Open Settings` redirects.
    - from task detail, click `Run` with no OpenAI key and confirm dialog appears and `Open Settings` redirects.
    - confirm dialog styling matches bottom-action pattern used in other app dialogs.
6. Exit criteria:
  - Extraction never starts without Gemini key.
  - Run never starts without OpenAI key.
  - Missing-key dialog consistently provides Settings redirect in both flows.

1. Step: Validate new in-app onboarding reset flow on user runtime devices (in progress).
2. Why now: Manual deep uninstall/reset is unreliable for onboarding recovery; user still reported missing onboarding after cleanup.
3. Code tasks:
  - Added onboarding reset notification hook:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/AppNotifications.swift`
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/RootView.swift`
  - Added state-reset entry point:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Models/MainShellStateStore.swift`
  - Added UI action:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/SettingsPageView.swift`
  - Added automated coverage:
    - `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSAppTests/MainShellStateStoreTests.swift`
4. Automated tests:
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" build` (pass on 2026-02-19 local run).
  - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests test` (pass on 2026-02-19 local run).
5. Manual tests:
  - Performed: shell-level onboarding reset + relaunch verification (`defaults` reset + app relaunch).
  - Pending: user-side runtime validation of `Settings -> Model Setup -> Start Over (Show Onboarding)`.
6. Exit criteria:
  - Clicking `Start Over (Show Onboarding)` immediately opens onboarding welcome.
  - Relaunch keeps onboarding route until the user completes onboarding again.

1. Step: Hide right-column scrollbar in task detail view (completed, pending runtime visual confirmation).
2. Why now: User reported an awkward persistent vertical bar on the right detail column.
3. Code tasks:
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/TaskDetailPageView.swift` to apply `.scrollIndicators(.never)` on the main `ScrollView`.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-rightscroll-build CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-19 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-rightscroll-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-19 local run).
5. Manual tests:
   - Pending user-side visual check in task detail page.
6. Exit criteria: Right detail column no longer shows the awkward vertical scroll bar.

1. Step: Show `ClickCherry` name in macOS title/navigation bar (completed, pending runtime visual confirmation).
2. Why now: User requested stable titlebar branding with app name visible in window chrome.
3. Code tasks:
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/AppMain.swift`:
     - `WindowGroup("ClickCherry")`
     - `.windowToolbarStyle(.unified(showsTitle: true))`
   - Simplified `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Titlebar/WindowTitlebarBranding.swift` to enforce native window title visibility (`ClickCherry`) and removed custom accessory-title path.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-titlebar-build CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-19 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-titlebar-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-19 local run).
5. Manual tests:
   - Pending user-side runtime check that title bar shows `ClickCherry` consistently.
6. Exit criteria: App window title/navigation bar visibly shows `ClickCherry` on launch.

1. Step: Remove DCO requirement from contribution policy and CI (completed).
2. Why now: User requested OpenClaw-style contributing flow without commit sign-off requirements.
3. Code tasks:
   - Removed DCO enforcement workflow:
     - deleted `/Users/farzamh/code-git-local/task-agent-macos/.github/workflows/dco.yml`.
   - Updated contributor-facing docs to remove DCO requirements:
     - `/Users/farzamh/code-git-local/task-agent-macos/CONTRIBUTING.md`
     - `/Users/farzamh/code-git-local/task-agent-macos/docs/getting-started.md`
     - `/Users/farzamh/code-git-local/task-agent-macos/docs/development.md`
     - `/Users/farzamh/code-git-local/task-agent-macos/.github/PULL_REQUEST_TEMPLATE.md`
   - Updated policy/source-of-truth docs:
     - `/Users/farzamh/code-git-local/task-agent-macos/.docs/open_source.md`
     - `/Users/farzamh/code-git-local/task-agent-macos/.docs/plan.md`
     - `/Users/farzamh/code-git-local/task-agent-macos/.docs/design.md`
4. Automated tests:
   - `ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml"); puts "ci.yml ok"; YAML.load_file(".github/workflows/release.yml"); puts "release.yml ok"'` (pass on 2026-02-19 local run).
5. Manual tests:
   - N/A (docs/workflow policy change).
6. Exit criteria: Contribution docs and CI no longer require `Signed-off-by` trailers.

1. Step: DMG installer icon/drop geometry correction (completed, pending release visual confirmation).
2. Why now: The mounted installer looked cheap/misaligned with app/drop icons appearing too low and visually clipped.
3. Code tasks:
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/.github/workflows/release.yml` DMG generator to:
     - increase background/window canvas size,
     - reposition drag arrow/text composition,
     - replace long `-->` style arrow artwork with a single `>` chevron icon,
     - use centered `ClickCherry.app` and Applications drop-link coordinates,
     - remove redundant dashed target box art from background.
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/docs/release-process.md` and `/Users/farzamh/code-git-local/task-agent-macos/.docs/open_source.md` notes to reflect the new centered layout decision.
4. Automated tests:
   - `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "release.yml ok"'` (pass on 2026-02-19 local run).
5. Manual tests:
   - Pending next release artifact mount in Finder:
     - confirm app icon and Applications drop-link are centered and not clipped.
     - confirm install dialog uses a single `>` icon (not long `-->` artwork).
6. Exit criteria: Installer opens with clean centered drag-to-install composition and no clipped icon look.

1. Step: Simplify contributor workflow doc to OpenClaw-style minimal guide (completed).
2. Why now: Contributor guidance felt heavier than desired; user requested a simpler contributing experience.
3. Code tasks:
   - Rewrote `/Users/farzamh/code-git-local/task-agent-macos/CONTRIBUTING.md` to a concise format:
     - quick links
     - contribution paths
     - short before-PR checklist
     - review policy
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/.docs/open_source.md` strategy wording to lock this simpler contributor-doc direction.
4. Automated tests:
   - N/A (docs-only).
5. Manual tests:
   - N/A (docs-only).
6. Exit criteria: `CONTRIBUTING.md` remains concise and easy to follow while preserving review requirements.

1. Step: Release artifact scope narrowed to DMG-only upload (completed, pending next release confirmation).
2. Why now: User requested release page assets to show only DMG from workflow output.
3. Code tasks:
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/.github/workflows/release.yml` to stop creating/uploading `ClickCherry-macos.zip`.
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/.github/workflows/release.yml` release notes + publish step to include only `ClickCherry-macos.dmg`.
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/docs/release-process.md` and `/Users/farzamh/code-git-local/task-agent-macos/.docs/open_source.md` to reflect DMG-only upload policy and note GitHub's automatic source archives.
4. Automated tests:
   - `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "release.yml ok"'` (pass on 2026-02-19 local run).
5. Manual tests:
   - Pending next tag release verification:
     - release assets uploaded by workflow include only `ClickCherry-macos.dmg`.
     - confirm expected GitHub-managed `Source code (zip)` and `Source code (tar.gz)` still appear.
6. Exit criteria: Workflow-generated upload assets are DMG-only on the next release.

1. Step: Recording stop crash mitigation in finished-recording preview sheet (completed, pending runtime confirmation).
2. Why now: Stopping a recording could crash the app while presenting the review sheet (`SIGABRT` in AVKit/SwiftUI metadata initialization path).
3. Code tasks:
   - Added `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/RecordingPreviewPlayerView.swift` (`NSViewRepresentable` around `AVPlayerView`).
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/RecordingFinishedDialogView.swift` to:
     - replace SwiftUI `VideoPlayer` with `RecordingPreviewPlayerView`.
     - defer player construction by 250ms after sheet appearance.
     - cancel pending player setup on dismiss and cleanly release player.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-crashfix-build CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-19 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-crashfix-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-19 local run).
5. Manual tests:
   - Pending user-side runtime validation:
     - start recording -> stop -> verify review sheet opens without crash.
     - repeat multiple times (including short recordings) and verify stability.
6. Exit criteria: Recording stop no longer crashes and finished-recording sheet consistently opens on local runtime devices.

1. Step: Sidebar empty-state text centering (completed, pending visual confirmation).
2. Why now: `No tasks yet.` in the left task column was not visually centered and looked misaligned.
3. Code tasks:
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/MainShellSidebarView.swift` to center the empty-state text with `.frame(maxWidth: .infinity, alignment: .center)`.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-build CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-19 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-19 local run).
5. Manual tests:
   - Pending user-side runtime visual confirmation in the sidebar empty state.
6. Exit criteria: `No tasks yet.` is horizontally centered in the task column empty state.

1. Step: DMG installer duplicate-icon cleanup + clearer Applications target (completed, pending release artifact confirmation).
2. Why now: The installer showed awkward duplicate ClickCherry icon visuals and unclear Applications drop affordance.
3. Code tasks:
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/.github/workflows/release.yml` DMG background generator to remove embedded app icon art (so Finder only shows the real draggable app icon).
   - Tuned installer background copy/arrow/target placement to better align with the real Applications drop link.
4. Automated tests:
   - `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "release.yml ok"'` (pass on 2026-02-19 local run).
5. Manual tests:
   - Pending next release artifact mount in Finder to confirm no duplicate app icon appears and drag target reads clearly.
6. Exit criteria: Mounted DMG shows one ClickCherry app icon and a visually clear Applications drop target.

1. Step: Sidebar task-column scrollbar visual cleanup (completed, pending runtime confirmation).
2. Why now: The right-side bar in the task column looked awkward and regressed the cleaner look users expected.
3. Code tasks:
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/MainShellSidebarView.swift` to hide sidebar scroll indicators.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-build CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-19 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-19 local run).
5. Manual tests:
   - Pending user-side runtime visual confirmation in task sidebar.
6. Exit criteria: Sidebar no longer shows the distracting right scroll bar in normal usage.

1. Step: Premium DMG installer polish (completed, pending release-run visual verification).
2. Why now: Styled DMG improved drag-to-install UX, but still lacked the polished background/layout feel common in top macOS apps.
3. Code tasks:
   - Enhanced `/Users/farzamh/code-git-local/task-agent-macos/.github/workflows/release.yml` DMG generation with:
     - generated branded background image
     - tuned icon/text layout
     - app volume icon
     - quieter/stabler hdiutil invocation
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/docs/release-process.md` artifact notes.
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/.docs/open_source.md` release strategy wording.
4. Automated tests:
   - `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "release.yml ok"'` (pass on 2026-02-18 local run).
5. Manual tests:
   - Pending next tag-based release run:
     - mount DMG and verify background art renders.
     - verify drag path is visually clear (`ClickCherry.app` -> Applications).
     - verify icon spacing/text readability on Retina display.
6. Exit criteria: Published DMG has premium Finder presentation comparable to polished mainstream macOS installers.

1. Step: Styled drag-to-install DMG in release workflow (completed, pending next release run confirmation).
2. Why now: Plain DMG UX felt manual/unstyled compared to standard polished macOS app installers.
3. Code tasks:
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/.github/workflows/release.yml` to build DMG via `create-dmg` with a Finder layout:
     - `ClickCherry.app` icon placement
     - Applications drop link placement
     - styled drag-to-install window
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/docs/release-process.md` artifact notes to describe styled DMG behavior.
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/.docs/open_source.md` release strategy wording.
4. Automated tests:
   - `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "release.yml ok"'` (pass on 2026-02-18 local run).
5. Manual tests:
   - Pending next tag-based release run: open produced DMG in Finder and confirm drag-to-install layout is styled and clear.
6. Exit criteria: GitHub release publishes a styled DMG showing `ClickCherry.app` and Applications drop link in a polished Finder layout.

1. Step: README privacy wording clarification (completed).
2. Why now: Privacy messaging needed explicit wording that LLM traffic goes directly from the local app to provider APIs with no ClickCherry server in between.
3. Code tasks:
   - Updated top privacy callout in `/Users/farzamh/code-git-local/task-agent-macos/README.md` to explicitly state direct local-to-OpenAI/Gemini calls. (Completed)
   - Updated `Privacy` section in `/Users/farzamh/code-git-local/task-agent-macos/README.md` to state no ClickCherry relay/proxy for LLM requests. (Completed)
   - Aligned strategy wording in `/Users/farzamh/code-git-local/task-agent-macos/.docs/open_source.md`. (Completed)
4. Automated tests:
   - N/A (docs-only).
5. Manual tests:
   - N/A (docs-only).
6. Exit criteria: README privacy language explicitly states direct local calls to OpenAI/Gemini and no ClickCherry relay server.

1. Step: README privacy-first messaging hardening (completed).
2. Why now: Privacy is a core product value and should be explicit at first glance for users and contributors.
3. Code tasks:
   - Added bold privacy callout near the top of `/Users/farzamh/code-git-local/task-agent-macos/README.md`. (Completed)
   - Added a dedicated `Privacy` section in `/Users/farzamh/code-git-local/task-agent-macos/README.md` clarifying local-first behavior and direct provider API calls via user keys. (Completed)
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/.docs/open_source.md` to lock this public-docs privacy messaging direction. (Completed)
4. Automated tests:
   - N/A (docs-only).
5. Manual tests:
   - N/A (docs-only).
6. Exit criteria: README prominently states local-first privacy guarantees and the direct-API-call model.

1. Step: Provider key `Save/Update` action alignment (completed, pending visual confirmation).
2. Why now: In Model Setup, the `Saved/Not saved` pills and `Save/Update` actions looked visually misaligned and awkward.
3. Code tasks:
   - Updated shared provider row layout in `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Shared/ProviderKeyEntryPanelView.swift` to use one fixed right action column width for both status and action.
   - Updated `Save/Update` button label to fill that fixed action column so its visible button geometry aligns with status pills.
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-build CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-18 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-18 local run).
5. Manual tests:
   - Pending user-side visual confirmation in onboarding `Provider Setup` and settings `Model Setup`.
6. Exit criteria: Status pills and action buttons are visually aligned in both provider rows on onboarding and settings.

1. Step: Recording finished dialog button parity (completed, pending visual confirmation).
2. Why now: `Record again` looked inconsistent with other primary actions and broke visual cohesion.
3. Code tasks:
   - Updated `Record again` in `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/RecordingFinishedDialogView.swift` to use `.ccPrimaryActionButton()`. (Completed)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-build CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-18 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (pass on 2026-02-18 local run).
5. Manual tests:
   - Pending user-side visual check of the recording finished dialog.
6. Exit criteria: `Record again` has the same visual style as the app’s primary action buttons.

1. Step: Onboarding bottom footer-strip removal (completed, pending visual confirmation).
2. Why now: The onboarding pages showed an unnecessary white footer band that visually broke the page.
3. Code tasks:
   - Removed `safeAreaInset` footer bar treatment and rendered onboarding footer as a bottom overlay on the same backdrop. (Completed)
   - Removed divider/background strip styling from `OnboardingFooterBar` while keeping navigation controls and step indicator intact. (Completed)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -configuration Debug -derivedDataPath /tmp/taskagent-dd-onboarding-nobar build` (pass on 2026-02-18 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-onboarding-nobar-test test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests` (pass on 2026-02-18 local run).
5. Manual tests:
   - Pending user-side Canvas/runtime confirmation that onboarding no longer has a dedicated white footer strip.
6. Exit criteria: Footer controls remain functional and the white bottom band is removed across onboarding steps.

1. Step: Settings right-column centering + narrower provider/permissions panels (completed, pending visual confirmation).
2. Why now: Settings had the same over-wide panel feel as onboarding and needed centered, narrower content on large displays.
3. Code tasks:
   - Centered settings detail content within the right column. (Completed)
   - Set `Model Setup` and `Permissions` section max width to `640` so panels match onboarding width behavior. (Completed)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -configuration Debug -derivedDataPath /tmp/taskagent-dd-settings-center build` (pass on 2026-02-18 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-settings-center-test test -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests` (pass on 2026-02-18 local run).
5. Manual tests:
   - Pending user-side visual confirmation for `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/MainShell/Pages/SettingsPageView.swift`.
6. Exit criteria: Settings provider panel appears centered and not overly wide on large windows.

1. Step: Onboarding Provider Setup width tightening on wide screens (completed, pending visual confirmation).
2. Why now: Provider Setup still read too wide on large displays and needed stronger side margins.
3. Code tasks:
   - Reduced Provider Setup step max content width in onboarding flow from `720` to `640` while keeping centered layout. (Completed)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -configuration Debug -derivedDataPath /tmp/taskagent-dd-provider-width build` (pass on 2026-02-18 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-provider-width-test test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests` (pass on 2026-02-18 local run).
5. Manual tests:
   - Pending user-side Canvas/runtime visual confirmation for `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Onboarding/OnboardingFlowView.swift`.
6. Exit criteria: Provider Setup panel appears narrower and better balanced on wide windows.

1. Step: Onboarding Welcome page modernization (completed, pending visual confirmation).
2. Why now: The Welcome step still looked sparse/awkward and did not match the more modern visual quality of the newer onboarding pages.
3. Code tasks:
   - Reworked `WelcomeStepView` visual hierarchy with a compact intro badge, stronger heading/subheading scale, and cleaner spacing. (Completed)
   - Replaced the sparse hero-only center with a two-column glass card:
     - app hero on the left.
     - three setup highlight rows on the right (`Connect providers`, `Grant macOS access`, `Start automating`). (Completed)
   - Kept onboarding flow behavior unchanged (content-only redesign). (Completed)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -configuration Debug -derivedDataPath /tmp/taskagent-dd-welcome-modern build` (pass on 2026-02-18 local run).
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-welcome-modern-test test -only-testing:TaskAgentMacOSAppTests/OnboardingStateStoreTests` (pass on 2026-02-18 local run).
5. Manual tests:
   - Pending user-side Canvas/runtime visual confirmation for `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Onboarding/Pages/WelcomeStepView.swift`.
6. Exit criteria: Welcome step looks balanced and modern in light/dark modes without changing onboarding behavior.

1. Step: Onboarding light-mode permissions shadow polish (completed, pending Canvas confirmation).
2. Why now: Light mode showed an overly strong shadow below the Permissions card that looked awkward compared with dark mode.
3. Code tasks:
   - Made Permissions panel shadow theme-aware:
     - dark mode keeps stronger depth.
     - light mode removes panel shadow entirely. (Completed)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-permissions-shadow-tune CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-18 local run).
5. Manual tests:
   - Pending user-side Xcode Canvas check in light mode for `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Previews/RootViewPreviews.swift`.
6. Exit criteria: Permissions card no longer shows the heavy bottom shadow in light mode while dark mode remains visually good.

1. Step: Onboarding footer action parity + light-mode preview enforcement (completed, pending user Canvas confirmation).
2. Why now: Onboarding footer controls looked inconsistent (`Skip`/`Back` vs `Continue`) and Canvas previews were defaulting to dark mode.
3. Code tasks:
   - Apply shared primary action style to onboarding footer controls:
     - `Back` and `Skip` now use `CCPrimaryActionButtonStyle` to match `Continue`/`Finish Setup`. (Completed)
   - Force preview color scheme to light mode for onboarding/main-shell preview wrappers and recording dialog preview. (Completed)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-onboarding-button-lightmode CODE_SIGNING_ALLOWED=NO build` (pass on 2026-02-18 local run).
5. Manual tests:
   - Source-level verification completed:
     - `Back`/`Skip` use `.ccPrimaryActionButton()`.
     - previews include `.preferredColorScheme(.light)`.
   - Pending user-side Xcode Canvas confirmation:
     - open `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Previews/RootViewPreviews.swift`
     - confirm onboarding preview variants render in light mode and footer actions look uniform.
6. Exit criteria: Onboarding footer buttons are visually consistent and Canvas previews default to light mode.

1. Step: Release notarization reliability hardening for transient GitHub runner network drops (completed in workflow, pending run confirmation).
2. Why now: Recent release run stayed `In Progress` for hours and failed with `NSURLErrorDomain -1009` while waiting on notary status.
3. Code tasks:
   - Replace `xcrun notarytool submit --wait` with:
     - submit + capture submission ID (Completed).
     - explicit status polling with retry on transient network failures (Completed).
     - bounded wait timeout and explicit invalid/rejected log handling (Completed).
     - timestamp + elapsed-time logging per poll for easier queue/runtime diagnosis (Completed).
   - Validate next release tag run completes notarization with the new flow. (In progress)
4. Automated tests:
   - `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "release.yml ok"'` (pass on 2026-02-18 local run).
5. Manual tests:
   - Manual workflow review:
     - confirm submission ID is persisted via `GITHUB_ENV`.
     - confirm polling retries `NSURLErrorDomain -1009`/offline errors.
     - confirm accepted/invalid/rejected/timeout paths are explicit. (Completed)
6. Exit criteria: A release workflow run completes with notarization accepted under the new submit+poll flow; transient network blips no longer cause immediate failure.

1. Step: CI-local parity verification with CI command shape (completed).
2. Why now: Recent CI failures needed reproducible local evidence using the same `xcodebuild` flags and target selection as `.github/workflows/ci.yml`.
3. Code tasks:
   - Keep local verification commands aligned to CI:
     - build: `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-build CODE_SIGNING_ALLOWED=NO build` (Completed locally)
     - tests: `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-ci-test -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test` (Completed locally)
   - Added deterministic test fixes for:
     - `GeminiVideoLLMClientTests.analyzeVideoUploadsPollsAndGeneratesExtractionOutput`
     - `MainShellStateStoreTests.extractFromFinishedRecordingCreatesTaskOnlyAfterExtractionReturns` (Completed locally)
   - Rerun GitHub CI and compare runner `.xcresult` with local logs only if failures persist. (In progress)
   - Keep `extractFromFinishedRecordingCreatesTaskOnlyAfterExtractionReturns` on time-based wait helper (`Task.sleep` polling) to avoid yield-scheduler flake regressions. (Completed locally)
4. Automated tests:
   - Build command above (pass on 2026-02-17 local run).
   - Test command above (pass on 2026-02-17 local run).
5. Manual tests:
   - N/A (command parity + log verification task).
6. Exit criteria: CI and local use identical command shape, deterministic local failures are addressed, and the next GitHub CI run confirms green.

1. Step: Open-source baseline rollout and launch hardening (active).
2. Why now: The repository now has a concrete OSS strategy (MIT + owner review authority) and needs immediate launch-ready follow-through.
3. Code tasks:
   - Add `Applications` symlink into DMG payload for drag-to-install flow. (Completed)
   - Add DMG packaging to release artifacts while keeping notarized ZIP distribution. (Completed)
   - Generate richer OpenClaw-style release pages (structured `Changes`/`Fixes`/`Artifacts` notes with versioned release names). (Completed)
   - Configure GitHub branch protection to require PRs, passing checks (`CI`), and owner/code-owner review. (Pending)
   - Configure release signing/notarization secrets and wire signed artifact steps in release workflow. (Pending)
   - Publish initial launch issues/labels (`good first issue`, `help wanted`, `documentation`). (Pending)
   - Refresh public docs style with visual, quickstart-first structure:
     - rewrite `README.md` with hero/badges/flow/quick links (Completed).
     - refine README top hero with final product tagline + stronger logo/CTA visual treatment (Completed).
     - rewrite `/docs/*` guides with clearer contributor/operator orientation (Completed).
   - Keep `/docs/` contributor guides current as onboarding/release flows evolve. (In progress)
   - Keep `/.docs/open_source.md` as the strategy source of truth for OSS decisions and tradeoffs. (In progress)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-oss-baseline -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - Review `/README.md` and `/docs/*` as a new contributor and confirm setup/release/contribution flow is clear.
   - Review governance and policy docs (`/CONTRIBUTING.md`, `/GOVERNANCE.md`, `/SECURITY.md`) for consistency with the locked strategy.
6. Exit criteria: Repo can accept external PRs with clear governance, contribution process, and release documentation; pending secrets/branch rules are explicitly tracked.

1. Step: UI/UX: New Task recording controls (multi-display + mic + Escape-to-stop) (active).
2. Why now: User wants `New Task` to show available displays only when multiple displays exist, allow microphone selection, and keep the UI out of the way while still being easy to stop (Escape + HUD).
3. Code tasks:
   - Show display picker under `Start recording` only when multiple displays are available. (Implemented)
   - Start capture hides the main app windows after capture begins (desktop stays clear). (Implemented)
   - Stop capture restores the app windows and focuses the app again (Escape stop matches Stop button flow). (Implemented)
   - Show microphone selection under `New Task` only when multiple microphone devices are available. (Implemented)
   - Fix explicit microphone selection so recording stop succeeds (avoid `Capture audio device <id> not found`). (Implemented)
   - Ensure the red border overlay appears on the selected display (display ordering matches `screencapture -D`). (Implemented)
   - Add a transparent HUD during recording that says `Press Escape to stop recording`. (Implemented)
   - Ensure the recording HUD is not captured into the saved recording output. (Implemented)
   - Support Escape-to-stop for recording; only hide the app UI when Escape monitoring starts successfully. (Implemented)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-recording-esc-micfix CODE_SIGNING_ALLOWED=NO build`
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/taskagent-dd-recording-esc-micfix-tests -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - Runtime: with 2+ displays connected, open `New Task` and confirm the display picker appears and selecting `Display 1/2/...` changes the display that gets the red border overlay (including non-main displays positioned left/below the main display).
   - Runtime: with only 1 display connected, confirm the picker is not shown.
   - Runtime: with 2+ microphone devices available, confirm the microphone dropdown appears and selecting a non-default mic:
     - records with microphone audio.
     - stops cleanly and saves a `.mov` (no `Capture audio device ... not found` error).
   - Runtime: click record on `New Task` and confirm:
     - the app window hides immediately after capture starts (when Escape monitoring starts), even if the app window is on a secondary display.
     - a transparent HUD appears that says `Press Escape to stop recording`.
     - the HUD does not appear inside the saved `.mov` output.
     - pressing Escape stops recording, restores/focuses the app, and navigates to the new task detail view.
6. Exit criteria: `New Task` stays minimal while allowing multi-display + mic selection when needed; recording hides the app UI during capture; and pressing Escape stops recording and restores the app (same as Stop).

1. Step: UI/UX: Permissions Preflight panel (modern) (pending manual confirmation).
2. Why now: User wants the Permissions step to match the new modern onboarding style, with careful alignment and no icon focus.
3. Code tasks:
   - Redesign Permissions Preflight into a single glass panel with aligned rows and consistent button columns. (Implemented)
   - Remove the hero/app-icon illustration from Permissions (no icon focus on this step). (Implemented)
   - Remove `Check Status` buttons; keep status pills updated automatically (polling) and rely on `Open Settings` as the primary action. (Implemented)
   - Remove the Automation permission row (no longer required). (Implemented)
   - Add Microphone permission to support screen recordings with voice. (Implemented)
   - Add `Skip` to the Permissions footer (matches Provider Setup). (Implemented)
   - Remove the Testing shortcut panel (Skip covers bypass). (Implemented)
   - Update Input Monitoring copy to clarify it is only used to detect `Escape` for stopping a run. (Implemented)
   - Validate spacing/alignment in Canvas and tune if needed. (Pending user-side confirmation)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-permissions-mic-noskiptestpanel CODE_SIGNING_ALLOWED=NO build`
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-permissions-mic-noskiptestpanel-tests -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - In Xcode Canvas, open `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Previews/RootViewPreviews.swift`, select `Startup - Permissions`, and confirm:
      - rows have consistent alignment and button columns line up.
      - there are no `Check Status` buttons.
      - `Open Settings` stays aligned (does not shift) across `Granted` vs `Not Granted` status-pill widths.
       - no hero/app icon appears on this step.
       - there is no Automation row.
       - Microphone (Voice) appears.
       - `Skip` is available in the footer.
       - there is no Testing shortcut panel.
6. Exit criteria: Permissions Preflight matches the redesign direction and looks visually aligned (no per-row drift).

1. Step: UI/UX: Provider Setup panel (OpenAI + Gemini) (pending manual confirmation).
2. Why now: Provider Setup is part of the same onboarding redesign and still needs local Canvas confirmation for alignment.
3. Code tasks:
   - Limit onboarding Provider Setup to OpenAI + Gemini only. (Implemented)
   - Keep Provider Setup as a single glass panel with consistent row alignment. (Implemented)
   - Align provider logos with the left edge of the API key input fields. (Implemented)
   - Add Keychain storage note (keys are stored locally and only used to authenticate provider API requests). (Implemented)
   - Remove onboarding `Remove` buttons; Save/Update only. (Implemented)
   - Keep `Skip` in the footer for Provider Setup. (Implemented)
   - Remove the warning line below the Provider Setup panel (Skip covers bypass). (Implemented)
   - Validate spacing/alignment in Canvas and tune if needed. (Pending user-side confirmation)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-provider-keychain-copy2 CODE_SIGNING_ALLOWED=NO build`
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-provider-keychain-copy2-tests -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - In Xcode Canvas, open `/Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp/Views/Previews/RootViewPreviews.swift`, select `Startup - Provider Setup`, and confirm:
      - Save/Update aligns with the status pill.
     - provider logos align with the left edge of the API key fields.
     - Keychain storage note appears under the subtitle.
     - only OpenAI and Gemini are present.
     - no warning line appears below the panel.
     - `Skip` appears in the footer.
6. Exit criteria: Provider Setup matches the redesign direction and looks visually aligned (no per-row drift).

1. Step: Code health: Split large view files into per-page subviews (completed).
2. Why now: `MainShellView.swift` and `OnboardingFlowView.swift` were getting too large; splitting by page reduces merge conflicts and makes UI iteration faster.
3. Code tasks:
   - Split main shell into sidebar + per-page views (`New Task`, `Task`, `Settings`) and move `VisualEffectView` to a shared file. (Implemented)
   - Split onboarding into shared components + per-step pages (`Welcome`, `Provider Setup`, `Permissions`, `Ready`). (Implemented)
4. Automated tests:
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-refactor-pages CODE_SIGNING_ALLOWED=NO build`
   - `xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -derivedDataPath /tmp/taskagent-dd-refactor-pages-tests -only-testing:TaskAgentMacOSAppTests CODE_SIGNING_ALLOWED=NO test`
5. Manual tests:
   - In Xcode Canvas, re-check `Startup - Welcome/Provider Setup/Permissions/Ready` and `MainShell - New Task/Settings` previews render. (Pending user-side confirmation)
6. Exit criteria: No behavior changes; compilation/tests remain green with smaller files.

1. Step: UI/UX documentation baseline (completed, docs-only).
2. Why now: UI/UX changes need a single source-of-truth log that explicitly follows plan and design decisions.
3. Code tasks:
   - Added `/Users/farzamh/code-git-local/task-agent-macos/.docs/ui_ux_changes.md`.
   - Updated `/Users/farzamh/code-git-local/task-agent-macos/AGENTS.md` with required UI/UX change logging/alignment rules.
4. Automated tests:
   - N/A (docs-only).
5. Manual tests:
   - N/A (docs-only).
6. Exit criteria: UI/UX governance instructions and canonical log exist and are ready for future UI changes.

1. Step: Step 4 execution agent (active, highest priority).
2. Why now: User explicitly prioritized execution-agent delivery as the most important milestone.
3. Code tasks:
   - Keep implemented baseline stable:
     - `Run Task` is wired to OpenAI execution (`OpenAIAutomationEngine` / `OpenAIComputerUseRunner`) (no provider routing in v1 UI).
     - runtime clarifications append into `## Questions`.
     - run summaries persist under `runs/`.
     - execution-agent prompt is loaded from `Prompts/execution_agent_openai/prompt.md` + `config.yaml`.
     - app branding baseline is set to `ClickCherry` (bundle/display name) with macOS AppIcon slots populated from the approved logo asset. (Implemented)
     - keep top-bar branding clean:
       - render `ClickCherry` in the top bar aligned near traffic-light controls via a left `NSTitlebarAccessoryViewController`.
       - keep icon to the left of the name with small native-looking size.
       - avoid SwiftUI title-bar toolbar placements (`.principal`, `.navigation`, `.toolbarRole(.editor)`) that introduce capsule/border rendering.
   - Execution provider UI is OpenAI-only (no segmented control / selection persistence).
   - Include host OS version string in the execution-agent prompt (via `{{OS_VERSION}}` placeholder). (Implemented)
   - Add a custom `terminal_exec` tool to the execution tool loop for unrestricted terminal command execution (absolute-path or PATH-resolved executables). (Implemented)
   - Keep OpenAI tool surface stable:
     - runner exposes both `desktop_action` and `terminal_exec`.
   - Keep OpenAI execution prompt organized and action-explicit:
     - separate sections for `desktop_action` help and `terminal_exec` help.
     - include full `desktop_action` action reference and accepted input forms so tool calls are predictable. (Implemented)
   - Keep default `wait` action duration at `0.5s` (when model omits duration). (Implemented)
   - Keep mouse cursor visible in LLM screenshots to improve hover/mouse-move task reliability. (Implemented)
   - Ensure LLM screenshots never include the “Agent is running” HUD by failing closed when exclusion-capable capture is unavailable. (Implemented)
   - Keep full text/tool history but send only the latest screenshot image block per LLM turn to control payload size growth. (Implemented)
   - Enforce terminal-vs-desktop boundary at runtime (block UI/visual terminal commands and redirect to `desktop_action`). (Implemented)
   - Before each run, hide other regular apps to provide a cleaner screen for the agent. (Implemented)
   - Keep screenshot size under a conservative base64 payload budget (downscale/re-encode when required). (Implemented)
   - Expose model-visible screenshots in Diagnostics so users can review the exact images sent to the model. (Implemented)
   - Keep cursor presentation unchanged during agent takeover (normal cursor size, no cursor-following halo overlay), including cancellation/monitor-start-failure paths. (Implemented)
   - Expand action coverage through tool-loop path (scroll/right-click/move/cursor_position implemented; drag and richer UI control still pending).
   - Fix keyboard shortcut injection reliability:
     - handle special keys like `space`.
     - improve text typing reliability for system UI targets (Spotlight, etc.) by using clipboard-paste typing with clipboard restore (cmd+v).
     - remove AppleScript `System Events` usage entirely to avoid macOS Automation permission prompts. (Implemented; unknown keys now fail with an explicit unsupported-key error)
   - Add loop guardrails to avoid “stuck tool_use spam”:
     - after N repeated invalid tool inputs, stop and append a blocking question into `## Questions` in `HEARTBEAT.md`.
   - Keep unresolved runtime-question generation on ambiguity/failure and persist to `HEARTBEAT.md`.
   - Implement current baseline policies:
     - allow run with unresolved questions and ask clarifications from run report.
     - no deterministic local action-plan synthesis; model tool calls are the only action authority.
     - desktop actions: zero retries before generating clarification questions (transport/network retries are allowed).
     - no per-step confirmation gates and no app allowlist/blocklist.
     - failure-only screenshot artifacts and no max step/runtime limits.
   - Keep provisional choices tracked in `.docs/revisits.md`.
   - Keep run status surfaced in task detail.
4. Automated tests:
   - Keep passing:
     - automation-engine outcome tests (`success`/`needs clarification`/`failed`).
     - run-trigger persistence tests (heartbeat question writeback + run-summary writes).
     - iterative tool-loop parser/execution smoke checks.
   - Markdown runtime-question append/dedup tests.
   - Add richer tool-action integration tests (drag and multi-display coordinate/origin cases; scroll/right-click/move are covered).
   - Add tests for `terminal_exec` tool definition + dispatch (PATH resolution + stdout/stderr capture). (Implemented)
   - Keep OpenAI parity tests passing for `terminal_exec` (execution output, visual-command rejection, PATH-resolved executable). (Implemented)
   - Keep coverage for `cursor_position` tool action mapping + payload return format. (Implemented)
   - Keep coverage for latest-image-only request compaction and visual terminal-command rejection. (Implemented)
   - Keep coverage for base64 image-size budget math (encoded 5 MB limit). (Implemented)
   - Keep coverage for LLM screenshot-log emission (initial + tool-result captures). (Implemented)
   - Keep state-store coverage for desktop preparation before run start. (Implemented)
   - Keep state-store coverage for takeover cursor-presentation activation/deactivation paths. (Implemented)
   - Add tool-input parsing tests for:
     - click coordinate schema variants (array/nested/top-level)
     - key schema variants (`key` vs `text`) and special keys like space
   - Add tests for loop guardrails (stop after repeated invalid tool inputs).
5. Manual tests:
   - Run at least one real task and verify desktop actions occur.
   - While the run is executing:
     - confirm `Diagnostics (LLM + Screenshot) -> Execution Trace` shows `tool_use` entries and local action entries (click/type/open/wait).
     - if no `tool_use` entries appear, the model is returning text-only completion; adjust the execution-agent prompt accordingly.
   - In `Diagnostics`, click `Copy Trace` and paste into Notes/Terminal to confirm clipboard formatting is readable.
   - Click `Stop` during an active run and confirm:
     - status becomes `Run cancelled.`
     - no new questions are appended into `HEARTBEAT.md` for the cancelled run.
   - While the run is executing, confirm:
     - a centered "Agent is running" overlay is visible.
     - pressing `Escape` cancels the run and the overlay disappears.
     - cursor presentation remains normal while takeover is active (no enlarged cursor and no halo overlay).
   - Confirm clicking `Run Task` minimizes the app window immediately (agent overlay remains visible).
   - Confirm cursor presentation remains unchanged after run completion/cancellation.
   - Confirm the model can use `terminal_exec` to open an app (example command: `open -a "Google Chrome"`).
   - Confirm Diagnostics -> `LLM Screenshots` matches what the model received during the run.
   - Confirm top-bar brand near traffic lights has no capsule/border and icon renders with correct aspect ratio (not stretched/compressed).
   - Temporarily revoke Screen Recording, Accessibility, or Input Monitoring permission and confirm clicking `Run Task`:
     - triggers a permission prompt (or opens System Settings)
     - does not start a run until permissions are granted
   - Validate ambiguity/failure writes blocking questions to `HEARTBEAT.md`.
   - Answer generated question and rerun to confirm progression.
6. Exit criteria: First execution-agent baseline can run a task, generate blocking questions when needed, and persist outcomes.

1. Step: Defer top-bar branding issue `OI-2026-02-11-007` (backlog).
2. Why now: User requested to pause this path; current attempts are inconsistent and should not block execution-agent priorities.
3. Code tasks:
   - Do not continue titlebar-branding implementation work in this cycle.
   - Keep issue tracked in `.docs/open_issues.md` and revisit in `.docs/revisits.md`.
4. Automated tests:
   - N/A (docs-only defer update).
5. Manual tests:
   - N/A (deferred).
6. Exit criteria: Defer decision is recorded and remains visible in active planning docs.

1. Step: Keep `OI-2026-02-08-003` open (deferred clarification-panel local verification).
2. Why now: Clarification UI verification is deferred while execution-agent milestone is in progress.
3. Code tasks:
   - Keep clarification parser/apply behavior unchanged during Step 4 execution-agent work.
   - Preserve regression tests for question parsing and markdown apply.
4. Automated tests:
   - Keep `HeartbeatQuestionService` tests passing.
   - Keep `MainShellStateStore` clarification persistence tests passing.
5. Manual tests:
   - Deferred by decision; do not run now.
6. Exit criteria: Issue remains tracked until deferred local verification is executed and confirmed.

1. Step: Defer `OI-2026-02-07-001` microphone selection bug (backlog).
2. Why now: Mitigation remains available via `System Default Microphone`; execution-agent baseline has higher delivery priority.
3. Code tasks:
   - Keep current mitigation and fallback messaging unchanged.
   - Resume mic diagnostics after Step 4 execution-agent baseline lands.
4. Automated tests: N/A (deferred backlog item).
5. Manual tests: N/A (deferred backlog item).
6. Exit criteria: Issue remains tracked in `.docs/open_issues.md` with mitigation and clear next action.

1. Step: Track `OI-2026-02-09-004` prompt resource-collision issue (deferred).
2. Why now: Anthropic execution runner is unblocked via embedded prompt; prompt file-packaging fix is a secondary concern after core computer-use loop.
3. Code tasks:
   - Keep execution-agent prompt embedded while current Xcode resource collision persists.
   - Design and implement prompt resource namespacing for multiple prompt folders.
4. Automated tests:
   - Build/test validation after namespacing fix to confirm no duplicate resource outputs.
5. Manual tests:
   - Add a second prompt folder with `prompt.md` and `config.yaml`, then verify project builds without collisions.
6. Exit criteria: Multiple prompt folders can coexist with required filenames and build cleanly.

1. Step: Step 5 scheduling while app is open (next, after Step 4 baseline).
2. Why now: Scheduling depends on a reliable execution-agent run path.
3. Code tasks:
   - Add natural-language schedule input and deterministic validation.
   - Persist schedule config per task and show `next run` and `last run` in task detail.
   - Wire scheduler trigger path while app is open and write run history updates.
4. Automated tests:
   - Schedule parser validation tests.
   - Scheduler trigger/deduplication tests.
   - State-store tests for schedule persistence and status projection (`next run`/`last run`).
5. Manual tests:
   - Configure short interval and verify scheduled run triggers while app is open.
   - Restart app and verify schedule reload behavior.
   - Confirm task detail status updates after at least one scheduled fire.
6. Exit criteria: At least one task runs successfully on schedule with correct status updates.
