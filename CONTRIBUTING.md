# Contributing to Petal

Thanks for helping improve Petal. Bug reports, feature proposals, documentation improvements, and focused code changes are welcome.

## Before You Start

- Search the existing issues before opening a new one.
- Use GitHub Issues for reproducible bugs and concrete feature requests.
- Do not open a public issue for a suspected vulnerability. Follow the private reporting instructions in [SECURITY.md](SECURITY.md).
- Keep each pull request focused on one change.

## Development Setup

Petal is a native macOS app built with Swift, SwiftUI, Xcode, and local Swift packages. An Apple Silicon Mac and a current Xcode installation are recommended.

1. Fork and clone the repository.
2. Open `petal.xcodeproj` in Xcode.
3. Select the `petal` scheme and the `My Mac` destination.
4. Let Xcode resolve the Swift package dependencies.
5. Build and run the app.

Petal needs microphone and accessibility permissions for its main workflows. Test permission-related changes from a clean permission state when practical.

## Validation

Run the repository's phase gate before submitting a code change:

```sh
./scripts/phase-gate.sh
```

The script builds or tests the Swift packages, builds the app without requiring a signing identity, and runs the bundled `aria2c` smoke test. End-to-end app testing can be enabled with:

```sh
PETAL_RUN_E2E=1 ./scripts/phase-gate.sh
```

For UI changes, also verify the affected workflow manually and include screenshots or a short recording in the pull request when useful.

## Pull Requests

- Create a descriptive branch from `main`.
- Write clear commit messages that explain the purpose of the change.
- Add or update tests when behavior changes.
- Update documentation when setup, behavior, or user-facing functionality changes.
- Complete the pull request template and link any related issue.
- Avoid committing generated build products, local settings, credentials, model files, or other secrets.

By participating in this project, you agree to follow the [Code of Conduct](.github/CODE_OF_CONDUCT.md).
