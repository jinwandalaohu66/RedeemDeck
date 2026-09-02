# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a vulnerability, exposed credential, or report that contains working App Store offer codes.

Use GitHub's private vulnerability reporting for this repository when it is available. If it is not enabled, contact the maintainer privately through the contact method on their GitHub profile and include only the information needed to reproduce the issue.

You should receive an acknowledgement within seven days. Please allow time for a fix and coordinated disclosure before sharing the issue publicly.

## Protecting sensitive data

- Never attach real offer codes, App Store Connect `.p8` keys, tokens, or provisioning profiles.
- Replace bundle identifiers, Apple team identifiers, app IDs, and code values with synthetic examples.
- Fully redact codes before capturing screenshots or sharing diagnostics.
- Revoke any credential immediately if it was committed or posted accidentally; removing it from a later commit is not sufficient.
- Treat exported `.codevaultbackup` files as secrets: they contain complete, unmasked redemption codes.

## Local protection boundaries

CodeVault stores its database in the app sandbox and relies on the device passcode and normal iOS data protection. It does not provide a second authentication gate or a separate encryption layer over the SwiftData database. Codes are shown in full in the app, so device access, screenshots, clipboard contents, backups, and exported files all require normal operational protection.
