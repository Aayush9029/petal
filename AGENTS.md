# Petal for macOS

Petal is a free, open-source macOS menu bar app for local-first dictation. The user presses a shortcut, speaks, and Petal pastes the transcript into the front app. It is a SwiftUI app with a local Swift package (`PetalKit`) on the Point-Free stack. Status: active, shipped through GitHub Releases with Sparkle updates.

## Commands

| Task | Command |
|------|---------|
| Build (no signing) | `xcodebuild -project petal.xcodeproj -scheme petal -destination 'platform=macOS' -derivedDataPath .derived/build CODE_SIGNING_ALLOWED=NO build` |
| Package tests | `swift test --package-path PetalKit` |
| Phase gate (packages, app build, `aria2c` smoke test) | `./scripts/phase-gate.sh` |
| Phase gate with the app E2E test | `PETAL_RUN_E2E=1 ./scripts/phase-gate.sh` |
| End-to-end model matrix | `./scripts/ci/e2e-full-matrix.sh` |
| Live cloud cleanup tests (costs money) | `PETAL_CLOUD_TESTS=1 swift test --package-path PetalKit --filter CloudCleanupIntegrationTests` |
| Local signed release | `./scripts/release/create-release.sh` |

## Architecture

- `petal/`: the app target. `App/` holds `AppModel`, the status item, Settings, and Sparkle update checks.
- `PetalKit/`: one target for each dependency client (`AudioClient`, `TranscriptionClient`, `PasteClient`, `FloatingCapsuleClient`, `CloudCleanupClient`, and more) and each feature (`ModelDownloadFeature`, `RouterFeature`, `CloudCleanupFeature`, `Onboarding`). Put new logic in `PetalKit`, behind a `@DependencyClient`.
- `PetalKit/KeyboardShortcuts` and `mlx-voxtral-swift/` are vendored local packages. Edit them only for a Petal need.
- Speech models run on device through FluidAudio (CoreML), argmax, MLX (`mlx-audio-swift`, `mlx-swift-lm`), and ONNX Runtime. Petal W1, the on-device cleanup model, runs through MLX.
- `aria2c` ships inside the app bundle for model downloads. The release signs it separately (`scripts/release/sign-aria2c.sh`).
- The URL scheme is `petal://` (for example `petal://start`, `petal://setup`). The Raycast extension in `../petal-raycast` uses it. Do not rename a deep link without a change to that extension.
- Petal writes `~/Documents/petal/history/history.json` and `~/Documents/petal/model-catalog.json`. `../petal-raycast` reads both files, so keep their format compatible.

## Models

- Keep the RAM budget of a default model under 8 GB on the Mac. Do not add a model that needs a top-tier Mac.
- Before you add a large model, ask the owner. Show a warning in the model picker for a heavy model, and suggest it for file transcription only.
- If a change does not touch the model set or the download code, skip the full model download test.

## Release

1. Merge the change to `main`.
2. Build and sign the app on this Mac, and run the end-to-end model tests on that build.
3. Replace the installed app in `/Applications` with the new build, and give it the microphone and accessibility permissions again.
4. Publish a GitHub release with the tag `vX.Y.Z`. Put screenshots of new UI in the release notes.
5. `.github/workflows/release.yml` then archives, notarizes, makes the DMG, uploads it, and pushes `appcast.xml` to `main`.

- Do not edit `appcast.xml` by hand. The workflow writes it, and Sparkle reads it from `main` through `SUFeedURL`.
- The workflow needs the repository secrets `APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, and `SPARKLE_PRIVATE_KEY`.
- `secret_keys/` and `ops/private/` hold the local copies of these keys. Both are git-ignored. Never commit them.

## Rules

- This repository is public. Do not commit personal data, local paths, keys, or model weights.
- The capsule is a floating panel. Let clicks pass through the panel outside the visible capsule, so the app under it stays usable.
- Keep the capsule animations subtle: a slow sway while the user speaks, a faster spin while Petal processes, and a red glow before a delete.
- Test permission changes from a clean permission state.
