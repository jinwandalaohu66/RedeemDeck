# Contributing to CodeVault

Thanks for helping improve CodeVault. Bug reports, focused fixes, tests, documentation, and accessibility improvements are all welcome.

## Before you start

- Search existing issues and pull requests before opening a duplicate.
- For a substantial feature or architectural change, open an issue first so the approach can be discussed.
- Never include real offer codes, App Store Connect credentials, provisioning profiles, or private keys in an issue, test fixture, screenshot, or commit.
- Follow [SECURITY.md](SECURITY.md) for vulnerabilities or other sensitive reports.

## Development setup

1. Fork and clone the repository.
2. Open `CodeVault.xcodeproj` with Xcode 26.1 or later.
3. Select the `CodeVault` target and choose your Apple Developer team.
4. Use a unique bundle identifier and an iCloud container owned by your team. See the README's [signing and CloudKit instructions](README.md#signing-and-cloudkit-in-a-fork).
5. Build and run on macOS 26.1+, or on an iOS/iPadOS 17+ simulator or device.

The project does not use third-party package dependencies.

## Making a change

- Create a focused branch from `main`.
- Prefer reusing or simplifying existing components over adding parallel abstractions.
- Keep user-facing behaviour consistent across iOS, iPadOS, and macOS where the platform permits it.
- Add or update tests when behaviour changes.
- Use synthetic codes and app identifiers in tests and documentation.
- Keep unrelated formatting or generated-file changes out of the pull request.

## Running tests

Use Xcode's Test action for the `CodeVault` scheme, or run:

```sh
xcodebuild \
  -project CodeVault.xcodeproj \
  -scheme CodeVault \
  -destination 'platform=macOS' \
  test
```

Before submitting, also build the platform affected by your change and check the modified flow in the running app.

## Pull requests

A useful pull request includes:

- A concise explanation of the problem and solution.
- The Apple platforms and OS versions tested.
- The relevant test results.
- Before-and-after images for visible UI changes, with all codes and account information masked.
- A linked issue when one exists.

By contributing, you agree that your contribution will be licensed under the repository's [MIT License](LICENSE).
