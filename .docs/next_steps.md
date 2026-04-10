---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Manually validate Phase 1 of the semantic automation plan in the live app.
2. Why now: Phase 1 is now implemented in code and covered by focused automated tests, but the behavioral change is only complete once live runs confirm that visual clicks no longer self-credit as success and that deterministic actions are preferred in the common app-open and URL-open cases.
3. Code tasks:
  - Keep Phase 1 scoped to the current desktop runner:
    - semantic-first prompt rules
    - verification-gated visual click semantics
    - evidence-required completion handling
  - Fix only Phase 1 fallout found during validation:
    - prompt wording mismatches
    - tool-result wording or state mismatches
    - missing verification transitions after click actions
  - Leave Phase 2 browser-semantic work and Phase 3 accessibility work out of this validation slice.
  - Leave workspace-local Xcode artifacts such as `xcuserdata` out of the shipped commit scope.
4. Automated tests:
  - Run `xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/clickcherry-phase1-dd -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/PromptCatalogServiceTests -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests CODE_SIGNING_ALLOWED=NO test`.
  - If Phase 1 follow-up changes land, rerun the same focused suite before widening coverage.
  - After live validation passes, run the broader macOS build/test commands before moving to Phase 2.
5. Manual tests:
  - Launch the debug app and run a task like "open Chrome" or "open Safari"; confirm the agent uses `open_app` rather than clicking a Dock icon.
  - Run a task like "go to linkedin.com" and confirm the agent prefers `open_url` or another deterministic path rather than address-bar clicking.
  - Run a task that requires a visual click on a small or adjacent target and confirm the agent does not claim `SUCCESS` immediately after the click; it should inspect the next screenshot first.
  - Force or observe an unclear click outcome and confirm the run continues or asks for clarification instead of reporting success without evidence.
  - Confirm successful visual-click runs now include screenshot-based evidence before the run settles as complete.
6. Exit criteria:
  - Focused automated coverage for the Phase 1 runner and prompt changes is green.
  - Live runs show deterministic app/URL actions being preferred where applicable.
  - Visual clicks no longer imply success on injection alone.
  - Final success after a visual click requires observable screenshot evidence.
  - The repo is ready to begin Phase 2 browser-semantic design and implementation.
