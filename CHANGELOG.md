# Changelog

All notable user-facing changes to RedeemDeck will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and release tags use semantic versioning.

## [0.1.0] - Unreleased

### Added

- Native App, code-category, and inventory management for iPhone, iPad, and Mac.
- Atomic multi-code retrieval with Available, Pending, Sent, and Expired states.
- Code, redemption-link, and stacked QR-poster output modes.
- Local expiration reminders and complete backup export and merge restore.
- English and Simplified Chinese localization.

### Changed

- Rebuilt the upstream workflow around a local-first, retrieval-focused architecture.
- Renamed the product, Xcode project, targets, modules, and production types to RedeemDeck.

### Removed

- App Store Connect credentials, JWT generation, tracked links, Cloudflare Worker code, CloudKit, remote notifications, analytics-like visit tracking, and unsupported redemption inference.
