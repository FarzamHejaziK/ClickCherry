# Getting Started

## Prerequisites

- macOS 14+
- Xcode 16+
- Git

## Clone

```bash
git clone https://github.com/FarzamHejaziK/task-agent-macos.git
cd task-agent-macos
```

## Build

```bash
xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/taskagent-dd-local \
  CODE_SIGNING_ALLOWED=NO build
```

## Run Tests

```bash
xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/taskagent-dd-local-tests \
  -only-testing:TaskAgentMacOSAppTests \
  CODE_SIGNING_ALLOWED=NO test
```

## First Contribution

- Pick an issue labeled `good first issue` or `help wanted`.
- Open a small PR with tests and docs updates.
- Sign commits with DCO (`git commit -s`).
