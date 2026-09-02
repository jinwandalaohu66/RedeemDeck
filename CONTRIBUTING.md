# Contributing to CodeVault

Bug reports, focused fixes, tests, localization improvements, and accessibility improvements are welcome.

## Development setup

1. Open `CodeVault.xcodeproj` with Xcode 26.1 or later.
2. Select your Apple Developer Team and use a bundle identifier owned by that team.
3. Build for iOS/iPadOS 17+ or macOS 26.1+.

No iCloud container or third-party package is required.

## Change rules

- Keep one production entry and one state owner for each feature.
- Prefer native SwiftUI containers and controls.
- Keep persistence, parsing, networking, backup, poster rendering, and file operations off the main actor.
- Split files by responsibility before they become difficult to review.
- Add or update deterministic tests for behavior changes.
- Use synthetic app IDs and codes in tests and screenshots.
- Never commit real codes, credentials, provisioning profiles, private keys, or unmasked backups.

Run the affected build and tests before opening a pull request. Changes remain licensed under the repository's [MIT License](LICENSE).
