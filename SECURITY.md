# Security Policy

## Reporting a vulnerability

Do not open a public issue for a vulnerability, exposed credential, or report containing working App Store offer codes. Use GitHub private vulnerability reporting when it is available. Otherwise, contact the maintainer privately through the contact method on the maintainer's GitHub profile and include only the information required to reproduce the problem.

Please allow time for investigation and coordinated disclosure before publishing details.

## Protecting sensitive data

- Never attach real offer codes, App Store Connect `.p8` keys, tokens, or provisioning profiles.
- Replace bundle identifiers, Apple team identifiers, App IDs, and code values with synthetic examples.
- Fully redact codes before capturing screenshots or sharing diagnostics.
- Revoke a credential immediately if it was committed or posted accidentally; deleting it in a later commit is not sufficient.
- Treat `.redeemdeckbackup`, compatible `.codevaultbackup`, and exported JSON files as secrets. They contain complete, unmasked codes.

## Local protection boundary

RedeemDeck stores its database in the App sandbox and relies on the device passcode and normal Apple-platform data protection. It does not add a second authentication gate or a separate encryption layer over the SwiftData store. Codes are shown in full, so device access, screenshots, clipboard contents, exported files, and system backups require normal operational protection.

The App does not contain redemption-status detection, an App Store Connect credential flow, analytics, or a custom backend. A report should not include an API key or live code to demonstrate a problem.
