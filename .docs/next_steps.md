---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Complete post-reorg runtime regression validation for the new feature-first source layout.
2. Why now: The repository has been reorganized into `App`, `Features`, `Core`, `UI`, and `Resources`, and automated build/test coverage is green. The next risk is not more folder churn; it is confirming that the moved prompt/resources paths and the re-grouped app flows still behave cleanly in interactive runtime usage.
3. Code tasks:
  - Keep the new layout stable and avoid slipping back into type-based catch-all folders.
  - Fix only structural fallout found during validation:
    - path assumptions
    - build-phase resource copying
    - stale file references or test-target wiring
  - Keep prompt loading file-backed through `PromptCatalogService` under `Resources/Prompts`.
  - Leave workspace-local Xcode artifacts such as `xcuserdata` out of the shipped commit scope.
4. Automated tests:
  - Run `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -parallel-testing-enabled NO test`.
  - Run `xcodebuild build -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -parallel-testing-enabled NO build`.
  - If any prompt/resource follow-up lands, rerun `xcodebuild test -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj -scheme TaskAgentMacOSApp -destination "platform=macOS" -parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests/PromptCatalogServiceTests test`.
5. Manual tests:
  - Launch the debug app from the reorganized project and confirm it starts cleanly.
  - Complete onboarding through permissions/provider setup.
  - Open MainShell, create/open a task, and navigate between the main pages.
  - Import or record a task recording and confirm the post-recording flow still appears.
  - Run extraction and confirm prompt loading still works from the moved `Resources/Prompts` source and bundled locations.
  - Start one execution run and confirm run history, screenshots, and task reopening still behave normally.
6. Exit criteria:
  - No missing-file, missing-resource, or prompt-loading regressions remain after the folder move.
  - The app builds and the test suite passes from the reorganized project layout.
  - Interactive smoke validation passes for onboarding, MainShell, recording/extraction, and one execution run.
  - The repository is ready to resume feature work without another structural cleanup pass first.
