# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project uses Semantic Versioning.

## [Unreleased]

### Added
- Open-source governance, contribution, and release scaffolding.

## [0.1.24] - 2026-02-22

### Changed
- Permission clicks for Screen Recording, Accessibility, and Input Monitoring now perform registration requests and open target System Settings panes in the same interaction when still ungranted.
- Microphone flow keeps first-time native prompt behavior for `.notDetermined` and uses System Settings fallback for denied/restricted states.
- Reduced permission pane open delay/retry timing to improve perceived responsiveness while preserving registration probes.

## [0.1.23] - 2026-02-21

### Changed
- Permission request behavior now uses required native macOS dialogs where registration needs them (notably Microphone), while preventing first-click overlap with immediate Settings navigation.
- Follow-up permission clicks now route to targeted System Settings panes when a permission remains ungranted.
- Updated onboarding/settings permission helper copy to reflect the mixed dialog + settings flow.

## [0.1.22] - 2026-02-21

### Added
- Additional permission guidance in onboarding/settings: if a privacy list does not show `ClickCherry`, relaunch from `/Applications` and retry `Open Settings`.

### Changed
- Further hardened DMG-installed permission registration behavior for non-Accessibility panes:
  - increased permission-pane open settle timing and retry behavior.
  - added best-effort registration probes for Screen Recording, Microphone, and Input Monitoring before opening System Settings.

## [0.1.21] - 2026-02-21

### Added
- Permissions onboarding/settings now include explicit guidance to run `ClickCherry` from `/Applications` for reliable macOS Privacy-list registration.

### Changed
- Hardened permission request flow to reduce TCC registration races when opening System Settings:
  - removed duplicate pre-request calls from permission-row actions.
  - delayed privacy-pane navigation after request calls and added one retry open across required permissions.

## [0.1.20] - 2026-02-21

### Added
- Temporary guarded Settings reset utility (`Enable temporary full reset` + `Run Temporary Reset`) to clear provider keys and restart onboarding.

### Changed
- Hardened temporary setup reset to attempt TCC permission revocation for app-related services and relaunch the app on successful reset so onboarding permission state refreshes correctly.
- Updated Settings copy to clearly indicate automatic relaunch on successful permission reset and manual fallback path when OS-managed reset is unavailable.

## [0.1.16] - 2026-02-19

### Added
- In-app `Start Over (Show Onboarding)` action in Settings to reliably reset onboarding without manual uninstall steps.

### Changed
- Window titlebar now uses native title visibility with `ClickCherry`.
- Main shell detail and sidebar scroll indicators were hidden for cleaner UI.
- Release workflow/docs remain DMG-first with contributor policy simplified (no DCO sign-off requirement).

## [0.1.0] - 2026-02-16

### Added
- Initial public open-source baseline for contribution workflow and repository governance.
