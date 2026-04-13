---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Start the first-party Chrome extension path for real-session browser automation.
2. Why now: The Playwright MCP Bridge spike gave us the important learning we needed: the bridge is useful as research, but its handshake, token pairing, and product UX are too opaque to be the main browser path. The next work should move into a ClickCherry-controlled browser connection flow.
3. Code tasks:
  - Define the first-party browser bridge contract:
    - extension <-> app handshake
    - pairing token lifecycle
    - per-profile trust state
    - reconnect behavior
  - Build the MV3 extension skeleton:
    - service worker
    - content script
    - minimal onboarding/connect UI
  - Build the native messaging host integration on macOS.
  - Implement the first browser action slice in the extension:
    - URL/title read
    - DOM snapshot/read helpers
    - click
    - type/fill
    - key press
    - scroll
    - wait-for element/text
  - Keep screenshots in the app and route visual verification through the existing app capture path.
  - Fence Playwright MCP Bridge off as research/fallback only; do not keep it on the main real-session critical path.
  - Preserve desktop fallback behavior for:
    - browser chrome
    - OS dialogs
    - canvas or non-DOM surfaces
  - Leave workspace-local Xcode artifacts such as `xcuserdata` out of the shipped commit scope.
4. Automated tests:
  - Keep the focused Phase 1 suite green:
    - `xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/clickcherry-phase1-dd -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/PromptCatalogServiceTests -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests CODE_SIGNING_ALLOWED=NO test`
  - Add browser-bridge tests for:
    - pairing request/approval/reconnect
    - native messaging transport encoding/decoding
    - per-profile token persistence
    - app-side browser action routing
  - Add extension-side tests or fixtures for:
    - DOM selection/read helpers
    - click/type/wait behavior on representative pages
5. Manual tests:
  - Pair the app with a local Chrome profile using the new ClickCherry-controlled connect flow.
  - Validate reconnect without repeated approval or copy/paste token setup.
  - Validate URL/title/snapshot-style DOM reads in the user's real Chrome session through the first-party extension.
  - Validate simple logged-in DOM actions in the user's real session on a site like LinkedIn and Google Docs.
  - Validate that desktop fallback behavior remains intact when browser semantics are unavailable.
6. Exit criteria:
  - Docs, planner policy, and implementation all agree that ClickCherry is using a first-party extension for the main real-session browser path.
  - The app can pair with Chrome, reconnect automatically, and execute the first DOM-focused browser action slice.
  - The app no longer depends on Playwright MCP Bridge for the main real-session browser path, and desktop fallback remains intact.
