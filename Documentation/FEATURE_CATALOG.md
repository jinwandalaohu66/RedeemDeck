# CodeVault Feature Catalog

This catalog defines the single production entry and canonical state owner for each user-facing feature.

| Feature | Production entry | Canonical owner | Verification |
| --- | --- | --- | --- |
| App shell | `ContentView` → `MainView` | `AppSession` + typed `LibraryRoute` | root-navigation UI tests |
| Code library | App launch → `LibraryView` | `AppRecord` + `DashboardRepository` | inventory, compact count, pending resume, sort, and swipe UI tests |
| App metadata and artwork | Library Add/Edit App → `AppEditorSheet` | `AppStoreLookupService` actor + `AppRecord` | build and manual lookup |
| Code categories | Manage Codes → `CodeCategoryListView` | immutable `CodeCategorySummary` + `DashboardRepository` | category-isolation and navigation tests |
| CSV import | Library Add menu → `ImportConfigurationSheet` | `CSVImporter` model actor | parser, category assignment, and import tests |
| Get codes | App row → native quantity `Alert` → `CodeRetrievalView` | `CodeVaultRepository.reserveCodes` + persisted retrieval ID | atomic quantity, category isolation, earliest-expiry, and UI tests |
| Retrieval result | `CodeRetrievalView` | immutable `PreparedCodeSelection` + `CodeRetrievalResultView` | code/link/poster, copy, save, resume, and Undo tests |
| Code management | App trailing swipe → `AppCodeManagementView` | `DashboardRepository` + `CodeVaultRepository` | native swipe and typed navigation UI tests |
| Code browser | Manage Codes → category → `CodeCategoryBrowserView` | `DashboardRepository.loadCategoryCodes` | search, filter, paging, and count tests |
| Code details | Code browser row → `CodeDetailView` | immutable `CodeRowSummary` + `CodeVaultRepository` | direct navigation, lifecycle, and UI tests |
| Poster export | Retrieval result or code detail → Poster | `QRCodeService` actor + `QRPosterRenderer` + `PhotoLibrarySaver` actor | portrait PNG, photo save, Vision decode, and poster UI tests |
| Expiration reminders | Settings → Reminders | `ExpirationNotificationService` actor | request and reconciliation tests |
| Backup and restore | Settings → Backup and Restore | `BackupRepository` + `BackupCodec` actors | legacy migration and schema-4 round-trip tests |
| Archive | App/category/batch action → Settings → Archived Items | archive timestamps + `CodeVaultRepository` | native Alert, archive, and restore tests |
| Transient feedback | Successful copy/save/import/archive/status action | root-owned `AppFeedbackCenter` | UI assertions and simulator review |

## Navigation contract

- `MainView` owns the only `NavigationStack` path. Management, category, code-detail, pending-retrieval, and result destinations are typed `LibraryRoute` values.
- Tapping an App row or Get Codes action presents one native Alert. The user enters a quantity and, only when necessary, chooses a code category from the Alert actions.
- Confirming the Alert pushes exactly one `CodeRetrievalView`. Reservation occurs atomically while that destination loads; there is no retrieval Sheet or intermediate form page.
- Returning from a prepared result keeps unsent codes Pending. The library exposes one Continue Retrieval section, and recent retrievals reopen the same result destination.
- Raw code search, filters, status editing, and details exist only below Manage Codes. Management pages never expose a Get Codes action and are not an intermediate step in the daily retrieval flow.
- App, category, code, and retrieval destinations receive immutable summaries; live SwiftData models and `@Query` do not cross navigation or actor boundaries.
- Import batches remain persistence and audit metadata rather than a navigation level.
- Settings is a modal utility surface opened from the library toolbar.
- There is no Today dashboard, alternate tab root, campaign page, recipient page, template page, distribution-history page, or parallel router.

## Interaction contract

- Main list rows have no decorative leading symbols. App rows retain App artwork; category and code rows remain text-only.
- App-row swipe actions use the concise native labels Get, Manage, Edit, and Archive; longer descriptions remain available in contextual menus and confirmations.
- Non-destructive swipe actions use the native adaptive system tint instead of the App accent color. This preserves SF Symbol contrast in both appearances; destructive archive actions retain the system red role.
- The empty library is informational only. Import Code File and Add App exist once, in the native Add menu in the top-trailing toolbar.
- The library has no bottom search field. Sorting stays in the native title menu; raw-code search remains contextual to the management browser.
- Codes are always shown in full. Each code or link row has one trailing copy button that temporarily changes to a checkmark.
- Retrieval is one canonical page, not separate code/link/poster pages. Its only content chrome is the native segmented Picker at the top; duplicate App artwork, product metadata, status header, divider, and redundant Share action are absent. The Picker sits directly on the grouped system background. Codes and Links use inset-grouped Lists, while Poster uses one real `ZStack` card pile rather than a horizontal page view: only the top poster can be dragged, and the next prepared poster is already visible underneath.
- Code, Link, and Poster layers retain stable structural identity while switching the segmented Picker, so prepared posters and the selected card are preserved. The result page has no redundant top-trailing Share action.
- The bottom action is an intrinsic-width 44-point native prominent glass capsule on iOS 26, with the existing size, material, and press behavior preserved. Its colors are explicit and deterministic: light appearance uses a black button with white label and symbol; dark appearance uses a white button with black label and symbol. Earlier systems use the same color contract with the native bordered-prominent fallback.
- Poster output is a compact black portrait card with a square high-contrast white scan field, rounded QR modules and finder patterns, App name, expiration, and an editable per-App greeting. The QR center always contains either downloaded App artwork or a generated initial fallback, without a white icon plate.
- The poster pile renders at most its top three real posters. A short drag springs fully home; a committed left or right swipe removes the top poster, promotes the cards below, and returns the removed poster to the back. It never rests between cards and never generates an entire large batch on the UI actor.
- Rounded poster codes are decoded by Vision in automated tests; visual styling must not replace scan verification.
- Poster generation, export preparation, and photo writes run away from the main actor. App artwork is fetched once per batch operation.
- A code has four effective states: Available, Pending, Sent, and Expired. Expiration is computed from its date and takes precedence over delivery state.
- Preparing a retrieval moves Available codes to Pending. Copying, completing a system share, or successfully saving a poster moves only affected Pending codes to Sent and offers Undo.
- Sent means the code left local inventory. CodeVault does not claim to detect whether App Store redemption actually occurred.
- A pending retrieval exposes Return to Inventory as one direct primary toolbar action. It never collapses its only command into an ellipsis menu, and still requires the existing confirmation Alert.
- Destructive archive and Return to Inventory decisions use native SwiftUI Alerts. Blocking failures use localized Alerts; successful transient operations use the shared feedback presenter.

## Persisted compatibility boundary

`Campaign`, `Recipient`, `MessageTemplate`, `DistributionRecord`, `ActivityEvent`, and legacy tracking properties remain only because existing SwiftData stores and older backups may contain those records. They have no production entry, page, command, status inference, or background service. New activity records are not written. `BackupRepository` preserves existing records while restoring older user data.

The retired redeemed and revoked fields remain storage-only compatibility properties on `OfferCode`. Startup migration maps old redeemed records to Sent and old revoked records to Archive, then clears those retired flags. Backup restore passes through the same adapter.

`OfferCode.retrievalID` is the durable owner of Pending retrievals. The additive startup migration assigns an ID to any older reserved code that lacks one. `AppRecord.qrGreeting` is optional and uses a lightweight additive store migration. Backup schema 4 persists both retrieval ownership and the per-App poster greeting; schema 1–3 archives remain decodable because the newer fields are optional.

Owner: the SwiftData schema and backup compatibility layer.

Removal gate:

1. Add an explicit versioned SwiftData migration that proves old stores open without data loss.
2. Increment the backup schema and provide a decoder or migrator for every supported archive version.
3. Verify upgrade fixtures containing each compatibility model and tracked-link field.

## Dynamic entries

- No App Intent, Widget, Live Activity, URL handler, remote notification, Share Extension, Objective-C selector, or C bridge enters the library workflow.
- Local notification taps open the canonical app shell.
- File import and export are presented only by the canonical Library and Settings surfaces.
