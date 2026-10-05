# VoxtralCore (Vendored)

Minimal vendored package used by `petal`.

## Scope

- Keeps only the `VoxtralCore` library target.
- Removes app, CLI, conversion scripts, tests, and screenshots.

## Build

```bash
swift build --package-path mlx-voxtral-swift
```

## Notes

- Model download behavior is driven by hardcoded `repoId` values in source.
- License text is maintained at repository root in `LICENSE.md`.
