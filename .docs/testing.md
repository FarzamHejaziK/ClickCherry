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

Unit tests only:

```bash
xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/taskagent-dd-local \
  -only-testing:TaskAgentMacOSAppTests \
  CODE_SIGNING_ALLOWED=NO test
```

Full test suite:

```bash
xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/taskagent-dd-local \
  CODE_SIGNING_ALLOWED=NO test
```

Build only:

```bash
xcodebuild -project /Users/farzamh/code-git-local/task-agent-macos/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/taskagent-dd-local \
  CODE_SIGNING_ALLOWED=NO build
```

## Operational notes

- Use a dedicated `-derivedDataPath` to avoid permission or lock conflicts.
- Avoid running multiple `xcodebuild` commands concurrently against the same DerivedData path.
- If you hit stale lock issues, remove the chosen DerivedData directory and rerun.
