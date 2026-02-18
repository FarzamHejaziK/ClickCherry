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
7. Notarized ZIP and DMG are published to GitHub Releases

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
  - notarized `ClickCherry-macos.zip`
  - `ClickCherry-macos.dmg` (containing the notarized app)
- Current release runner/build target is arm64 macOS
- Universal (arm64+x86_64) delivery can be added as a follow-up release enhancement
