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

## Release Preflight Checks

Run a local Release build and verify prompt catalog assets are present in the app bundle before tagging:

```bash
xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -configuration Release -destination "platform=macOS" -derivedDataPath /tmp/taskagent-release-preflight build
find /tmp/taskagent-release-preflight/Build/Products/Release/ClickCherry.app/Contents/Resources/Prompts -maxdepth 3 -type f
```

Expected files include:

- `Prompts/task_extraction/prompt.md`
- `Prompts/task_extraction/config.yaml`
- `Prompts/execution_agent/prompt.md`
- `Prompts/execution_agent/config.yaml`
- `Prompts/execution_agent_openai/prompt.md`
- `Prompts/execution_agent_openai/config.yaml`

## Required Secrets

- `APPLE_DEVELOPER_ID_APPLICATION_CERT_BASE64`
- `APPLE_DEVELOPER_ID_APPLICATION_CERT_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

If any secret is missing, release fails fast.

## Current Artifact/Platform Notes

- Current release artifacts:
  - `ClickCherry-macos-vMAJOR.MINOR.PATCH.dmg` (for example: `ClickCherry-macos-v0.1.23.dmg`) with premium styled drag-to-install Finder layout:
    - custom branded background art
    - single-icon install composition (background avoids duplicating app icon art)
    - tuned icon/text placement and centered Finder icon/drop geometry (no bottom-clipped icon layout)
    - app volume icon
    - `ClickCherry.app` + Applications drop link)
- GitHub automatically adds `Source code (zip)` and `Source code (tar.gz)` to releases; these platform-provided source archives cannot be disabled by workflow uploads.
- Release page notes are auto-generated from commit history between tags.
- Current release runner/build target is arm64 macOS
- Universal (arm64+x86_64) delivery can be added as a follow-up release enhancement
