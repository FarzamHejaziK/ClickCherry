# Task Agent macOS

Task Agent macOS is a native macOS app for learning and replaying desktop tasks from recordings.

## Open Source Baseline

This repository is open source and contribution-ready.

- License: MIT (`/LICENSE`)
- Contributions: welcomed via pull requests (`/CONTRIBUTING.md`)
- DCO required on commits (`git commit -s`)
- Conduct expectations: `/CODE_OF_CONDUCT.md`
- Security reporting policy: `/SECURITY.md`
- Governance and review authority: `/GOVERNANCE.md`, `/MAINTAINERS.md`
- Brand/trademark usage: `/TRADEMARK.md`

## Public Documentation

- `/docs/README.md`
- `/docs/getting-started.md`
- `/docs/development.md`
- `/docs/architecture.md`
- `/docs/release-process.md`

## Internal Maintainer Docs

Internal planning and implementation logs are in `/.docs/`.

## Project Layout

- `TaskAgentMacOSApp/`: Swift app code and tests
- `docs/`: public contributor documentation
- `.docs/`: internal maintainers' planning and work tracking
- `.github/`: CI, release, PR, and issue workflows/templates

## Quick Build

```bash
xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/taskagent-dd-local \
  CODE_SIGNING_ALLOWED=NO build
```
