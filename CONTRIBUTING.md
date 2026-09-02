# Contributing to RedeemDeck

Focused bug fixes, deterministic tests, accessibility improvements, and localization corrections are welcome.

## Development setup

1. Open `RedeemDeck.xcodeproj` with Xcode 26.1 or later.
2. Select an Apple Developer team and use a bundle identifier owned by that team.
3. Build for iOS or iPadOS 17+, or macOS 14+.

RedeemDeck has no third-party package, server, account, or CloudKit dependency.

## Before changing a feature

Read [Documentation/FEATURE_CATALOG.md](Documentation/FEATURE_CATALOG.md) and find the existing production entry, route, state owner, feedback pattern, and error mapping. A replacement must migrate every caller and remove the displaced implementation; do not add a parallel page, router, state model, or permanently hidden version.

## Engineering principles

- Prefer native SwiftUI containers and controls.
- Keep one canonical production entry and state owner per feature.
- Pass immutable summaries across navigation and actor boundaries.
- Keep parsing, persistence, backup, poster rendering, artwork loading, and file operations away from the main actor.
- Split files by responsibility before they become difficult to review.
- Keep compatibility models isolated and document an explicit removal gate.
- Show localized, actionable messages instead of raw errors or internal enum values.
- Add or update deterministic tests for behavior changes.
- Use synthetic App IDs and codes in tests, fixtures, and screenshots.
- Never commit real codes, backups, credentials, signing material, or provisioning profiles.

## Pull requests

Keep each pull request scoped to one coherent change. Explain the user-visible result, compatibility impact, and verification performed. Run the relevant build and tests from [README.md](README.md) before requesting review, and update the feature catalog when an entry point, owner, or contract changes.

By contributing, you agree that your contribution is licensed under the repository's [MIT License](LICENSE).
