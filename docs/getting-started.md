# Getting Started

## Prerequisites

- macOS 14+
- Xcode 16+
- Git

## Clone

```bash
git clone https://github.com/FarzamHejaziK/ClickCherry.git
cd ClickCherry
```

## Build

```bash
xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/taskagent-dd-local \
  CODE_SIGNING_ALLOWED=NO build
```

## Run Unit Tests

```bash
xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /tmp/taskagent-dd-local-tests \
  -parallel-testing-enabled NO \
  -only-testing:TaskAgentMacOSAppTests \
  CODE_SIGNING_ALLOWED=NO test
```

## First Contribution Checklist

- Pick an issue (`good first issue`, `help wanted`, or docs task)
- Keep PRs focused and small when possible
- Add or update tests for behavior changes
- Update public docs when behavior/flow changes
