---
description: Architecture and routing model for ClickCherry automation.
---

# Automation Strategy Architecture

## Desired Architecture

ClickCherry should evolve toward three action layers:

1. Browser-semantic MCP tools
   - for webpage content in Chrome and other supported browsers
   - exposed through a generic app-owned MCP harness
   - first approved browser server:
     - Playwright MCP in extension mode for the user's real Chrome session
   - optional later browser server:
     - Playwright MCP in managed/custom-profile mode

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
   - use Playwright MCP Bridge through the generic MCP harness
2. managed/custom browser mode explicitly requested or later enabled:
   - use managed Playwright MCP mode
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

- Swift-hosted generic MCP runtime
- approved MCP server registry / allowlist
- Playwright MCP as the first browser server
- Playwright MCP Bridge as the first real-session browser integration

Why:

- keeps the app extensible beyond one browser server
- reduces adaptation work when Playwright MCP evolves
- lets prompt policy guide tool use without a heavy Playwright-specific facade
- avoids fighting Chrome's default-profile remote debugging restrictions when real user-session automation is required

Extension recommendation:

- use Playwright MCP Bridge first as the off-the-shelf real-session extension path
- only consider a custom extension after the generic MCP harness is in place and a concrete capability gap is proven

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

The extension path is not a replacement for that mode. It is the correct complement for real-session browser use.
