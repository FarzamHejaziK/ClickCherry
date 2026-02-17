---
description: Testing guidance for TaskAgentMacOSApp, including local commands and known sandbox limitations.
---

# Testing Guide

## Why test results differ between Codex and local machine

- The Codex runtime is sandboxed.
- This app uses Swift Observation macros (`@Observable`), which require `swift-plugin-server` during compile/test.
- In this sandbox, macro expansion may fail with:
  - `ObservationMacros.ObservableMacro could not be found`
  - `swift-plugin-server produced malformed response`
- That failure is environmental, not a deterministic app-code assertion failure.

## Source of truth

- Treat local Xcode or local terminal runs as the authoritative test result.
- Use Codex test runs here mainly for quick smoke checks when environment permits.

## Recommended local test commands

CI-exact build command:

```bash
xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /tmp/taskagent-dd-ci-build \
  CODE_SIGNING_ALLOWED=NO build
```

CI-exact unit-test command:

```bash
xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /tmp/taskagent-dd-ci-test \
  -parallel-testing-enabled NO \
  -only-testing:TaskAgentMacOSAppTests \
  CODE_SIGNING_ALLOWED=NO test
```

Optional: force a specific Xcode when multiple versions are installed.

```bash
DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer xcodebuild ...
```

## Operational notes

- Use a dedicated `-derivedDataPath` to avoid permission or lock conflicts.
- Avoid running multiple `xcodebuild` commands concurrently against the same DerivedData path.
- If you hit stale lock issues, remove the chosen DerivedData directory and rerun.
- CI currently runs with Xcode 16.4; command parity alone does not guarantee result parity if local Xcode is different.
- Unit tests run inside an XCTest host app process. To avoid macOS Keychain popups during test runs, `KeychainAPIKeyStore` automatically uses in-memory storage when `XCTestConfigurationFilePath` is present.
- Runtime behavior is unchanged outside XCTest: provider keys are still read/written in macOS Keychain.
