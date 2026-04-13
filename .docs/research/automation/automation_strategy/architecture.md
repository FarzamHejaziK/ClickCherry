---
description: Architecture and routing model for ClickCherry automation.
---

# Automation Strategy Architecture

## Desired Architecture

ClickCherry should evolve toward three action layers:

1. Browser-semantic extension bridge
   - for webpage content in Chrome and other supported browsers
   - first release uses a first-party Chrome extension plus a direct app bridge
   - transport target for v1:
     - native messaging
   - optional later evolution:
     - expose the same browser surface through MCP if cross-server composition becomes valuable

2. `accessibility_action`
   - for native macOS UI
   - backed by macOS Accessibility APIs

3. `desktop_action`
   - for visual fallback only
   - used when semantic targeting is unavailable or untrustworthy

## Native Accessibility Control Direction

Focus:

- add a macOS semantic surface for native app interaction

Proposed capabilities:

- `press`
- `set_value`
- `focus_window`
- `select_menu_item`
- `read_focused_element`
- `find_element`

Implementation note:

- use AXUIElement-based APIs in native Swift
- prefer accessibility over pixel clicks for dialogs, menus, buttons, and standard controls
- explicitly keep deeper/custom AX surfaces and browser chrome support out of the first accessibility release

## Planner Routing Policy

This routing policy is cross-cutting and applies as the three layers come online:

1. approved browser MCP tools
2. accessibility action
3. deterministic shortcut or app/URL action
4. visual desktop action

Within the browser-semantic layer, the planner should assume:

1. real user Chrome session required:
   - use the first-party extension bridge
2. managed/custom browser mode explicitly requested or later enabled:
   - use managed Playwright
3. browser chrome / OS / non-DOM:
   - use accessibility, deterministic actions, or desktop fallback

Policy examples:

- "open Chrome" -> `open_app`
- "click Login on LinkedIn" -> browser semantic action
- "choose File > Export in a native app" -> accessibility action or shortcut
- "click a node in a canvas" -> visual action

## Tooling Recommendations

### Browser Layer

Recommended approach:

- first-party MV3 extension
- native messaging bridge
- app-owned pairing and reconnect flow
- content-script DOM automation first
- optional future MCP adapter only if and when a broader tool-host architecture proves valuable

Why:

- gives ClickCherry control over onboarding, trust, diagnostics, and reconnect behavior
- avoids opaque third-party handshake flows
- avoids fighting Chrome's default-profile remote debugging restrictions when real user-session automation is required
- keeps v1 closer to Chrome Web Store-safer permissions by deferring `chrome.debugger`

Extension recommendation:

- use a first-party ClickCherry extension as the main real-session path
- defer `chrome.debugger` until concrete workflow gaps prove the DOM-only path is insufficient
- treat Playwright MCP Bridge as research/fallback only

### Accessibility Layer

Recommended approach:

- native Swift implementation over macOS Accessibility APIs

Why:

- best integration with current app
- no extra runtime dependency for native app semantics

## Relationship To Managed Playwright

Managed Playwright remains useful and should stay in the product for:

- deterministic regression coverage
- clean automation sessions
- isolated browser testing
- workflows that do not require the user's live browser state

The extension path is not a replacement for that mode. It is the correct main path for real-session browser use.
