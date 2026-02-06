---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Unblock local Swift test toolchain.
2. Why now: This was previously blocking tests, but is now resolved.
3. Code tasks: None.
4. Automated tests: `swift test` already passing.
5. Manual tests: Confirm `xcode-select -p` still returns `/Applications/Xcode.app/Contents/Developer` if toolchain issues recur.
6. Exit criteria: Complete.

1. Step: Step 0.5 routing wire-up.
2. Why now: Routing + onboarding scaffold are implemented; visual verification is the remaining gate to close the onboarding UI sub-step.
3. Code tasks: Connect provider/permission toggles to real services (Keychain + permission checks) after visual walkthrough confirms flow.
4. Automated tests: Onboarding state machine + route tests are passing in `swift test`.
5. Manual tests: Walk through all 4 onboarding steps and verify gating: provider step blocks until OpenAI/Anthropic + Gemini; permissions step blocks until all three permissions; ready step `Finish Setup` transitions to main shell.
6. Exit criteria: Visual walkthrough passes and worklog marks this Step 0.5 onboarding scaffold sub-step complete.

1. Step: Step 0.5 persistence wiring (next).
2. Why now: Persistence wiring is implemented; manual relaunch verification is now the final gate for this sub-step.
3. Code tasks: None for baseline persistence; optional follow-up is replacing provider booleans with secure text entry + real key values.
4. Automated tests: Persistence + onboarding tests are passing in `swift test` (12 tests).
5. Manual tests: Complete onboarding, relaunch app, and verify onboarding is skipped; clear saved provider keys and onboarding flag, relaunch, and verify onboarding returns.
6. Exit criteria: Relaunch behavior matches persisted setup state.

1. Step: Step 0.5 UX hardening (next).
2. Why now: Implemented; now requires full interactive walkthrough to close the sub-step.
3. Code tasks: None for baseline UX; optional refinement is replacing per-key save buttons with inline validate-on-submit flow and obscured “saved” chip behavior.
4. Automated tests: Onboarding/persistence suite passing in `swift test` (15 tests).
5. Manual tests: Enter OpenAI+Gemini and verify continue enabled; clear OpenAI and enter Anthropic+Gemini and verify continue enabled; clear both core providers and verify continue disabled; relaunch app and verify key-presence state persists from Keychain.
6. Exit criteria: Provider setup behavior is manually confirmed end-to-end.

1. Step: Step 0.5 permission grant UX (next).
2. Why now: Implemented with settings deep links and in-app status display; still needs manual confirmation against real macOS permissions.
3. Code tasks: Optional follow-up is adding a concrete automation-permission probe for a selected target app to replace manual confirmation button.
4. Automated tests: Permission mapping/status refresh tests passing.
5. Manual tests: Use `Open Settings` for Screen Recording/Accessibility/Automation; grant each permission; click `Check Status` for Screen Recording and Accessibility; use automation confirmation control and verify all three show `Granted`; confirm continue is disabled until all are granted.
6. Exit criteria: Permissions flow is manually validated on-device and onboarding proceeds only when all required permissions are confirmed granted.
