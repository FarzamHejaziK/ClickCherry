---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Start the generic MCP harness foundation for Phase 2 and connect it to Playwright MCP Bridge.
2. Why now: The browser-profile experiments and follow-up research clarified that real-user-session webpage automation should move through an approved MCP server path rather than a Playwright-specific wrapper or default-profile CDP takeover. The next work should move into the first concrete MCP runtime slice.
3. Code tasks:
  - Implement the generic MCP runtime in the app:
    - approved server registry
    - process lifecycle
    - tool discovery
    - tool invocation routing
  - Connect Playwright MCP in extension mode as the first approved browser server.
  - Remove or fence off any planner/runtime path that treats the default Chrome profile as a supported CDP relaunch target.
  - Define the first approved browser MCP tool subset for webpage work.
  - Update the execution prompt so browser MCP tools are preferred for webpage DOM work.
  - Preserve desktop fallback behavior for:
    - browser chrome
    - OS dialogs
    - canvas or non-DOM surfaces
  - Leave workspace-local Xcode artifacts such as `xcuserdata` out of the shipped commit scope.
4. Automated tests:
  - Keep the focused Phase 1 suite green:
    - `xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/clickcherry-phase1-dd -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/PromptCatalogServiceTests -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests CODE_SIGNING_ALLOWED=NO test`
  - Add MCP runtime tests for:
    - approved-server registration
    - tool discovery
    - tool invocation routing
    - startup / transport failure handling
  - Add Playwright MCP integration tests for extension-mode startup and first browser-tool calls.
5. Manual tests:
  - Confirm tasks that ask for the real default Chrome profile no longer route into a long timeout or misleading "supported" flow.
  - Start the app-side MCP harness and validate connection to the installed Playwright MCP Bridge.
  - Validate URL/title/snapshot flows in the user's real Chrome session through Playwright MCP.
  - Validate simple logged-in DOM actions in the user's real session on a site like LinkedIn once the first approved tool subset exists.
  - Validate that desktop fallback behavior remains intact when browser semantics are unavailable.
6. Exit criteria:
  - Docs, planner policy, and implementation all agree that ClickCherry is using a generic MCP harness and the default Chrome profile is not a CDP takeover target.
  - The app can start an approved MCP server, discover tools, and execute at least the first Playwright MCP browser-tool slice.
  - Playwright MCP Bridge works as the first real-session browser path, with desktop fallback still intact.
