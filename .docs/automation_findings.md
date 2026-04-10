# Automation Findings

## Summary

ClickCherry's current desktop execution loop is strong on screenshot capture, coordinate normalization, and post-action screenshots, but it still relies too heavily on visual clicking for targets that should be handled semantically. This creates two recurring failure modes:

- grounding misses: the model clicks a nearby icon or control instead of the intended one
- false success: the model reports success after a click event is injected, even when the intended target was not actually activated

These are known problems in computer-use agents and should be treated as expected failure classes, not edge cases.

## Current Observations In This Repo

- The OpenAI desktop runner already normalizes coordinates to the selected display and supports crop/grid screenshot workflows.
- The runner captures a fresh screenshot after tool execution, which gives us a good base for verification-driven behavior.
- Visual click tool outputs still resolve to a generic success payload today, which makes it easy for the model to over-credit a click as success.
- The prompt already encourages `open_app` and discourages terminal-based UI scripting, but it does not yet enforce a strong semantic-first routing policy or a "no success without evidence" rule.

## External Findings

### 1. Visual GUI agents still struggle with fine-grained grounding

Research and benchmark work on computer-use agents consistently shows that small, adjacent, icon-only, and visually similar controls are hard for current models to target reliably. This is especially true in high-resolution UIs, dense toolbars, docks, and professional app surfaces.

### 2. Verification is stronger than first-shot clicking

Recent grounding work suggests that models are often better at judging whether an action succeeded than at selecting the right pixel on the first try. This means a verification-driven loop is a high-leverage mitigation.

### 3. High-resolution and scaling issues are real

Multiple tools and public issues document errors caused by coordinate scaling, Retina/display conversion mismatches, and visually tiny targets. Even when the model conceptually finds the right target, execution can still land on the wrong nearby element.

### 4. Semantic control is more reliable than pixels

Where semantic handles exist, they should be preferred:

- browser DOM actions for website content
- macOS Accessibility actions for native UI
- deterministic app open/focus and keyboard paths for common shell-level actions

### 5. Playwright is powerful but not universal

Playwright is the right tool for DOM-backed website interaction, but it does not cover all Chrome or system interactions. It does not semantically control all browser chrome UI, OS sheets, permission prompts, or canvas-heavy content.

## Key Concepts

## Semantic Actions

Semantic actions target UI by identity instead of pixel location.

Examples:

- open Google Chrome by app name
- click a web button by DOM role and label
- press a native macOS button by accessibility role and title

Benefits:

- less sensitive to layout shifts
- less sensitive to coordinate mistakes
- easier to verify after execution

## Accessibility Actions

Accessibility actions use the macOS accessibility tree rather than mouse coordinates.

Examples:

- press a button by AX role/title
- set a text field value by AX identifier or label
- select a menu item through AX menu traversal
- inspect the focused window or element

These are ideal for native app controls when the app exposes good accessibility metadata.

## Playwright / CDP Attachment

For website content in Chrome, the agent should prefer a browser-semantic path:

1. launch or focus Chrome
2. connect via CDP remote debugging
3. attach Playwright to the browser session
4. operate on pages through DOM locators and assertions

Important limits:

- Chrome must be launched with remote debugging enabled for CDP attachment
- profile/session choice matters because it determines login state and cookies
- Playwright is best for webpage content, not every browser-UI surface

## Routing Matrix

| Target surface | Preferred action type | Notes |
|---|---|---|
| Open/focus Chrome | deterministic app action | `open_app` should be preferred over Dock clicking |
| Navigate to website | browser semantic action or deterministic URL open | avoid address-bar pixel flows when possible |
| Website links, buttons, forms | browser semantic action | use DOM/role/text/test-id targeting |
| Browser tab strip / toolbar / extension icon | accessibility or shortcut | not standard webpage DOM |
| Native app buttons, menus, dialogs | accessibility action | use AX when available |
| OS permission prompts, pickers, sheets | desktop action or accessibility | depends on what AX exposes |
| Canvas/WebGL/custom-rendered web UI | visual fallback | semantic handles may not exist |
| Image-only / ambiguous tiny targets | visual fallback with zoom and verification | force higher-confidence workflow |

## Recommended Product Direction

ClickCherry should move to a three-layer action model:

1. browser semantic actions for DOM-backed website interaction
2. accessibility actions for native macOS UI
3. desktop visual actions as fallback only

This preserves the current desktop runner, but changes its role from "primary action mechanism" to "last-resort executor" for ambiguous or non-semantic targets.

## Immediate Reliability Recommendations

- Prefer semantic actions over visual clicks whenever possible.
- Never treat "click event injected" as equivalent to "task step succeeded."
- Require postcondition evidence before final success.
- Force crop/zoom/grid on small or ambiguous visual targets.
- Track false-success rate separately from raw action success.

## Locked Decisions

The current implementation sequence is now locked to these defaults:

- Phase 2 will use managed Chrome as the default browser-semantic baseline.
- Phase 3 will start with standard native controls only:
  - buttons
  - text fields
  - checkboxes and radio buttons
  - dialogs and sheets
  - menu items
  - window focus

These are intentional scoping decisions, not long-term limits. The design should remain extensible so later phases can add:

- user-profile browser startup or attachment flows
- deeper AX traversal for more complex app surfaces
- browser chrome support such as tab strip, toolbar, and omnibox targeting

## Sources Consulted

- Anthropic computer use documentation
- OpenAI computer use documentation
- OSWorld benchmark paper and project page
- ScreenSpot-Pro grounding work
- Visual test-time scaling work for GUI grounding
- public Retina / coordinate mismatch automation issues
- macOS UI automation ecosystem documentation
