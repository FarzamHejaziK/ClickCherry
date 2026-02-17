# Architecture Overview

Task Agent macOS is a native SwiftUI macOS application with local-first task
workspaces and LLM-backed task extraction/execution workflows.

## High-Level Components

- Task workspace and persistence services
- Recording ingestion and metadata handling
- Task extraction pipeline from recordings
- Execution engine and runtime run logging
- Onboarding and provider key management

## Core Principles

- Local-first storage for user task data
- Explicit permission preflight for macOS capabilities
- Deterministic, testable service boundaries where possible

For implementation sequencing and internal design rationale, maintainers use
`/.docs/plan.md` and `/.docs/design.md`.
