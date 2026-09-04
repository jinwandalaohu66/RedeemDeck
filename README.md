# RedeemDeck

[English](README.md) | [简体中文](README.zh-Hans.md)

RedeemDeck is a private, native offer-code manager for Apple developers. It turns App Store Connect CSV exports into an organized inventory and keeps the daily workflow focused on one task: getting the right codes to the right people quickly.

## Highlights

- Import App Store offer-code and promo-code CSV files.
- Separate subscriptions, discounts, campaigns, and other products into code categories.
- Retrieve an exact quantity with earliest-expiring inventory selected first.
- Copy codes or redemption links, share with the system share sheet, and save QR posters.
- Generate compact posters with App artwork, expiration details, and an editable greeting.
- Resume unfinished retrievals without returning codes to inventory accidentally.
- Search, filter, edit, archive, and restore codes from a secondary management flow.
- Schedule local expiration reminders.
- Export complete backups and merge them safely on restore.
- Use the App in English or Simplified Chinese on iPhone, iPad, and Mac.

## Workflow

1. Add an App or import a CSV export from App Store Connect.
2. Assign the codes to a category such as a subscription, launch offer, or discount.
3. Choose **Get**, enter a quantity, and work from the prepared result.
4. Copy, share, or save only what was actually sent.

RedeemDeck uses four effective states:

| State | Meaning |
| --- | --- |
| Available | The code remains in inventory. |
| Pending | The code was prepared but has not been output yet. |
| Sent | A copy, completed share, or successful poster save moved the code out of local inventory. |
| Expired | The expiration date has passed. |

**Sent does not mean redeemed.** Apple does not expose a public, anonymous endpoint that reliably confirms redemption for an individual code. RedeemDeck does not guess by repeatedly opening redemption URLs, and it does not require an App Store Connect API key.

## Privacy and storage

RedeemDeck has no account system, analytics SDK, advertising SDK, custom backend, CloudKit container, or remote-push service. Its SwiftData database stays in the App sandbox. Network access is limited to App Store metadata and artwork lookup, plus links that the user explicitly opens.

Cross-device transfer is explicit: export a backup, then restore it on another device. A `.redeemdeckbackup` file contains complete, unmasked codes and is not encrypted by RedeemDeck, so handle it as sensitive data. Backups created by the upstream CodeVault build remain importable through a compatibility type.

## Requirements

- Xcode 26.1 or later
- iOS or iPadOS 17.0 or later
- macOS 14.0 or later
- An Apple Developer team for installation on a physical device

The project has no third-party package dependencies.

## Build and run

```sh
git clone https://github.com/jinwandalaohu66/RedeemDeck.git
cd RedeemDeck
open RedeemDeck.xcodeproj
```

In Xcode:

1. Select the `RedeemDeck` target.
2. Choose your team under **Signing & Capabilities**.
3. Replace the bundle identifier if `app.safevault` is not available to your team.
4. Select a simulator, iPhone, iPad, or **My Mac**, then run the App.

Changing the bundle identifier creates a separate installation and separate local database. Export a backup before deleting an existing build.

## CSV format

App Store Connect exports can be imported directly. A minimal compatible file is:

```csv
Offer Code,Redemption URL
EXAMPLECODE,https://apps.apple.com/redeem?ctx=offercodes&id=123456789&code=EXAMPLECODE
```

The first column may be named `Code`, `Offer Code`, or `Promo Code`. If redemption URLs are absent, select the target App during import so RedeemDeck can build them. Never commit working codes, exported backups, signing material, or App Store Connect keys.

## Architecture

- SwiftUI for native navigation, lists, alerts, menus, and sharing
- SwiftData for local persistence
- Swift concurrency and model actors for parsing, persistence, poster rendering, and file operations
- UserNotifications for local reminders
- Core Image, Vision, and Photos for QR generation, scan verification, and export

The canonical feature owners and compatibility boundaries are documented in [Documentation/FEATURE_CATALOG.md](Documentation/FEATURE_CATALOG.md). The replacement history is documented in [Documentation/REBUILD_MIGRATION.md](Documentation/REBUILD_MIGRATION.md).

## Verification

Build the iOS target without signing:

```sh
xcodebuild \
  -project RedeemDeck.xcodeproj \
  -scheme RedeemDeck \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the deterministic core test suite on macOS:

```sh
xcodebuild \
  -project RedeemDeck.xcodeproj \
  -scheme RedeemDeck \
  -destination 'platform=macOS' \
  -only-testing:RedeemDeckTests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Do not disclose working codes or credentials in an issue; follow [SECURITY.md](SECURITY.md) for private reports.

## Provenance and license

RedeemDeck is a substantial derivative of [mcomisso/CodeVault](https://github.com/mcomisso/CodeVault), based on upstream commit `bf07e2c720c851aaf032ae0fd2244572a037b6c4`. See [NOTICE.md](NOTICE.md) for attribution.

Source code is available under the [MIT License](LICENSE). The license preserves the original copyright and identifies the RedeemDeck modifications as copyright © 2026 WENLUZHANG. Project-name and endorsement guidance is in [TRADEMARKS.md](TRADEMARKS.md).
