# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project uses Semantic Versioning.

## [Unreleased]

### Added
- Open-source governance, contribution, and release scaffolding.

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
