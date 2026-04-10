---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Re-scope Phase 2 browser automation around supported browser-session modes.
2. Why now: Phase 2 experiments validated managed Playwright/CDP for custom profiles, but also showed that the user's default Chrome profile is not a reliable CDP takeover target. The next work needs to align implementation with that platform reality before more browser-action surface area is added.
3. Code tasks:
  - Keep managed/custom-profile Playwright as the supported `browser_action` baseline.
  - Remove or fence off any planner/runtime path that treats the default Chrome profile as a supported CDP relaunch target.
  - Design the real-user-session browser path around:
    - Chrome extension for active-tab DOM control
    - native app bridge / native messaging host
    - clear routing between managed-browser mode and real-user-session mode
  - Preserve desktop fallback behavior for:
    - browser chrome
    - OS dialogs
    - canvas or non-DOM surfaces
  - Leave workspace-local Xcode artifacts such as `xcuserdata` out of the shipped commit scope.
4. Automated tests:
  - Keep the focused Phase 1 suite green:
    - `xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/clickcherry-phase1-dd -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/PromptCatalogServiceTests -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests CODE_SIGNING_ALLOWED=NO test`
  - Keep the browser-sidecar contract tests green while the managed-profile path remains active.
  - Add future extension-bridge contract tests before treating real-user-session browser automation as ready.
5. Manual tests:
  - Re-run a managed-profile browser task and confirm webpage navigation/actions still work through the supported managed Playwright path.
  - Confirm tasks that ask for the real default Chrome profile no longer route into a long timeout or misleading "supported" flow.
  - Validate that desktop fallback behavior remains intact when browser semantics are unavailable.
  - When the extension path exists, manually validate real logged-in workflows such as LinkedIn and Google Docs inside the user's actual Chrome session.
6. Exit criteria:
  - Docs, planner policy, and implementation all agree that managed Playwright is the supported baseline and the default Chrome profile is not a CDP takeover target.
  - Managed-profile browser automation remains working and test-covered.
  - The next real-user-session browser phase has a concrete extension/native-bridge design and validation plan.
