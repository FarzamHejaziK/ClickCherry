---
description: Open-source strategy decisions, governance, contribution model, and release operations
---

# Open Source Strategy

## Goals

- Keep contribution friction low.
- Keep final review/merge authority with project owner.
- Publish repeatable releases on GitHub.
- Keep internal maintainers' process docs in `/.docs/` while providing strong public docs in `/docs/`.

## Locked Decisions (2026-02-16)

- Hosting:
  - GitHub (`https://github.com/FarzamHejaziK/task-agent-macos`)
- License:
  - MIT (`/LICENSE`)
- Contribution legal model:
  - DCO required (`git commit -s`) with CI validation
  - No CLA for now
- Governance/review authority:
  - BDFL-style final decision authority by owner
  - Owner approval required before merges to `main`
  - `CODEOWNERS` currently routes all paths to owner
- Brand policy:
  - Source code is open under MIT
  - `ClickCherry` brand/name/logo usage is reserved and controlled by project owner
  - public policy file: `/TRADEMARK.md`
- Release strategy:
  - GitHub Releases with version tags (`vMAJOR.MINOR.PATCH`)
  - Release workflow performs Developer ID signing + notarization + stapling
  - Release workflow uploads only DMG (`ClickCherry-macos.dmg`)
  - GitHub's default source archives (`Source code (zip)` and `Source code (tar.gz)`) remain visible and are not controlled by workflow file uploads
  - DMG distribution uses a premium styled Finder drag-to-install layout:
    - branded background art
    - background intentionally avoids duplicate app icon rendering
    - tuned icon/text positions
    - volume icon
    - `ClickCherry.app` + Applications drop link
  - Release page body is generated in a structured format (`Changes`, `Fixes`, `Artifacts`) from commit history between tags
  - Workflow requires repository signing/notarization secrets and fails fast if missing
- Documentation split:
  - Public contributor docs in `/docs/`
  - Internal planning and execution docs remain in `/.docs/`
  - Current repo choice is to keep tracking `/.docs/` and `AGENTS.md` until explicitly changed by owner
  - Public docs presentation direction favors a visual, quickstart-first README and concise guide hub (while keeping technical details project-specific).
  - Public docs must clearly and prominently communicate the local-first privacy model: local workspace data remains on-device; network usage is limited to direct API calls from the local app to OpenAI/Gemini using user-owned keys, with no ClickCherry relay server.
- Security/community contact:
  - security reports and policy contacts use `clickcherry.app@gmail.com`

## Rationale Snapshot

- MIT was selected for maximum adoption simplicity.
- DCO is selected as low-overhead legal attestation.
- Centralized review authority protects product direction while accepting broad contribution.
- Public docs and templates reduce onboarding friction and improve PR quality.

## Implemented Repository Baseline

- Governance/process files:
  - `/CONTRIBUTING.md`
  - `/CODE_OF_CONDUCT.md`
  - `/GOVERNANCE.md`
  - `/MAINTAINERS.md`
  - `/SECURITY.md`
  - `/CHANGELOG.md`
  - `/TRADEMARK.md`
- GitHub collaboration scaffolding:
  - `/.github/CODEOWNERS`
  - `/.github/PULL_REQUEST_TEMPLATE.md`
  - `/.github/ISSUE_TEMPLATE/*`
  - `/.github/workflows/ci.yml`
  - `/.github/workflows/dco.yml`
  - `/.github/workflows/release.yml`
- Public docs:
  - `/docs/README.md`
  - `/docs/getting-started.md`
  - `/docs/development.md`
  - `/docs/architecture.md`
  - `/docs/release-process.md`

## Pending Follow-ups

- Configure repository branch protection in GitHub settings:
  - require PRs before merge
  - require status checks (`CI`, `DCO`)
  - require review from code owners
  - restrict direct pushes to `main`
- Decide whether to stop tracking `/.docs/` and `AGENTS.md` in git later.
