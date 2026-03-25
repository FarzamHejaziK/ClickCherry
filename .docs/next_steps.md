---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Keep the previous computer-use implementation and defer OpenAI built-in `computer` adoption.
2. Why now: The OpenAI built-in `computer` evaluation regressed a simple Dock hover task that the previous implementation handled reliably, and the migrated path could falsely report success.
3. Code tasks:
  - Keep the reverted non-OpenAI state as the baseline implementation.
  - Do not reintroduce the OpenAI built-in `computer` path, prompt changes, or supporting screenshot-viewer work into the active app path.
  - If OpenAI computer use is revisited later, require a fresh spike that proves initial screenshot grounding and reliable postcondition verification before any product integration.
4. Automated tests:
  - N/A (docs-only decision update).
5. Manual tests:
  - N/A (docs-only decision update; decision based on the user-observed Dock hover regression during local runtime evaluation).
6. Exit criteria:
  - Open issue records the OpenAI computer-use regression and the mitigation decision.
  - Current execution queue no longer assumes OpenAI built-in `computer` will ship.
