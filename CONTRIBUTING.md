# Contributing to ClickCherry

Thanks for contributing.

## Quick Links

- Docs hub: [`/docs/README.md`](docs/README.md)
- Getting started: [`/docs/getting-started.md`](docs/getting-started.md)
- Day-to-day development: [`/docs/development.md`](docs/development.md)
- Architecture: [`/docs/architecture.md`](docs/architecture.md)
- Security policy: [`/SECURITY.md`](SECURITY.md)
- Code of Conduct: [`/CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)

## How to Contribute

1. **Bug fixes / small improvements**: open a focused PR.
2. **Bigger changes** (new features, architecture, major UX): open an Issue first to align scope.
3. **Questions**: open an Issue.

## Before You Open a PR

- Keep the PR scoped to one concern.
- Add/update tests for behavior changes.
- Run local checks:

```bash
xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS,arch=arm64" \
  -parallel-testing-enabled NO \
  -only-testing:TaskAgentMacOSAppTests \
  CODE_SIGNING_ALLOWED=NO test
```

- Include what changed, why, and manual verification notes in PR description.

## Review Policy

- Maintainer review is required before merge.
- Final merge authority remains with the project owner (BDFL model).
