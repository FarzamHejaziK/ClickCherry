# Architecture Overview

ClickCherry is a native SwiftUI macOS app with local-first task workspaces and LLM-backed extraction/execution.

## Core Modules

- Task/workspace persistence services
- Recording capture and recording metadata handling
- Task extraction pipeline from recorded media
- Execution engine (desktop + terminal action loop)
- Onboarding/provider configuration and key storage

## Runtime Flow

```mermaid
flowchart TD
  A["User records task"] --> B["Recording stored in task workspace"]
  B --> C["Extraction service generates heartbeat markdown"]
  C --> D["Main shell displays task + clarifications"]
  D --> E["Execution runner performs tool loop"]
  E --> F["Run summary and logs persisted"]
```

## Design Principles

- Local-first task data and artifacts
- Explicit macOS permission preflight
- Testable service boundaries
- Prompt text loaded from file-based prompt catalog
