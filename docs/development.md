# Development Guide

## Repository Layout

- `TaskAgentMacOSApp/` - Swift app code, tests, project files
- `docs/` - public documentation
- `.github/` - CI, release, issue/PR templates, policy workflows
- `.docs/` - internal maintainer planning and execution logs

## Prompt Files

All production prompts live under:

- `TaskAgentMacOSApp/TaskAgentMacOSApp/Prompts/`

Each prompt folder must contain:

- `prompt.md`
- `config.yaml` (with at least `version` and `llm`)

## Testing

Recommended CI-parity test command:

```bash
xcodebuild -project TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /tmp/taskagent-dd-ci-test \
  -parallel-testing-enabled NO \
  -only-testing:TaskAgentMacOSAppTests \
  CODE_SIGNING_ALLOWED=NO test
```

## Pull Request Expectations

- Project builds locally
- Unit tests pass locally
- Behavior changes include tests
- Relevant docs are updated in the same PR
- Commits are DCO signed
