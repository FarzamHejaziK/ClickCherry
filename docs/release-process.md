# Release Process

## Versioning

- Use tags in `vMAJOR.MINOR.PATCH` format (example: `v0.1.7`)
- Update [`CHANGELOG.md`](../CHANGELOG.md) before tagging

## Release Workflow

1. Push a version tag
2. GitHub Actions `Release` workflow builds the app
3. App is Developer ID signed
4. Artifact is submitted to Apple Notary
5. Notarization is polled until accepted/rejected/timeout
6. Ticket is stapled to the app
7. GitHub Release page is generated with structured notes (`Changes`, `Fixes`, `Artifacts`)
8. DMG is published to GitHub Releases

## Create a Release

```bash
git tag v0.1.7
git push origin v0.1.7
```

## Required Secrets

- `APPLE_DEVELOPER_ID_APPLICATION_CERT_BASE64`
- `APPLE_DEVELOPER_ID_APPLICATION_CERT_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

If any secret is missing, release fails fast.

## Current Artifact/Platform Notes

- Current release artifacts:
  - `ClickCherry-macos.dmg` (premium styled drag-to-install Finder layout with:
    - custom branded background art
    - single-icon install composition (background avoids duplicating app icon art)
    - tuned icon/text placement
    - app volume icon
    - `ClickCherry.app` + Applications drop link)
- GitHub automatically adds `Source code (zip)` and `Source code (tar.gz)` to releases; these are platform-provided and not controlled by this workflow.
- Release page notes are auto-generated from commit history between tags.
- Current release runner/build target is arm64 macOS
- Universal (arm64+x86_64) delivery can be added as a follow-up release enhancement
