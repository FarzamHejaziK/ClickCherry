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
2. Why now: Core route logic is implemented; manual verification is the remaining gate to close this step.
3. Code tasks: None for routing; next code under Step 0.5 is onboarding screens scaffold (welcome, provider setup, permissions, ready).
4. Automated tests: Route-selection unit tests are passing.
5. Manual tests: Startup smoke check passed via `swift run TaskAgentMacOS`; still needed: visual confirmation that fresh state shows onboarding and complete provider state shows main shell.
6. Exit criteria: Visual route checks pass and worklog marks Step 0.5 routing sub-step complete.
