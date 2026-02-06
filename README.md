# Task Agent macOS

Fully native macOS app for learning and replaying desktop tasks from recordings.

## Stack
- Swift
- SwiftUI
- Local-first storage

## Initial Scope
- Import workflow recording (`.mp4`)
- Generate task spec (`HEARTBEAT.md`)
- Clarification loop (`## Questions`)
- Local scheduled runs (while app is open)

## Project Layout
- `app/` SwiftUI app source
- `docs/` product and architecture docs

## Next Steps
1. Create Xcode SwiftUI app target.
2. Add permissions preflight (Screen Recording, Accessibility, Automation).
3. Implement task import + task spec generation flow.
