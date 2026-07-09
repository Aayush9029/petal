# Settings Design QA

- Source visual truth: `/Users/yush/Library/Application Support/CleanShot/media/media_lgiQvnF0FO/Screenshot Alcove2026-07-09 at 18.04.45@2x.png` and `/Users/yush/Library/Application Support/CleanShot/media/media_dUNEZPgsre/Screenshot Alcove2026-07-09 at 18.04.54@2x.png`
- Intended implementation captures: `/Users/yush/Library/Application Support/CleanShot/media/media_5gYMWzGLMW/Screenshot petal2026-07-09 at 18.26.20@2x.png` and `/Users/yush/Library/Application Support/CleanShot/media/media_U5DstclIp5/Screenshot petal2026-07-09 at 18.26.26@2x.png`
- Viewport: 720 × 680 points
- State: Settings window, General and Recording pages, dark appearance

## Full-view comparison evidence

The Alcove references were available and show a compact two-column window, hidden title, a roughly 205-point sidebar, narrow detail canvas, continuous rounded setting cards, inset row content, subtle edge-to-edge separators, compact switches, and custom visual selectors.

The supplied Petal implementation captures were not present at their declared paths, and direct app capture timed out. A post-fix rendered comparison therefore could not be completed.

## Focused region comparison evidence

Source regions reviewed:

- Window title bar and sidebar/detail proportion
- Multi-row cards and separators
- Toggle geometry
- Segmented and popup controls
- Glass appearance selector

Post-fix implementation regions could not be captured for a same-state comparison.

## Comparison history

### Iteration 1 findings

- P1: The 920-point window and 720-point detail canvas were materially wider than the reference.
- P1: `Settings` appeared in the title/navigation chrome instead of using Alcove's hidden-title window.
- P1: The card builder did not wrap its children in a layout container, so padding, background, and separators were distributed across individual child views.
- P2: Default SwiftUI toggles and pickers did not match the compact, deliberate control geometry in the reference.
- P2: Appearance previews and page headers were oversized.

### Fixes made

- Reduced the window to 720 × 680 points and constrained detail content to a 500-point maximum.
- Hid the NSWindow title and removed the sidebar navigation title.
- Wrapped section content in one continuous card and moved padding ownership to each row.
- Replaced stock switches, segmented pickers, and popup pickers with reusable custom controls.
- Reduced header and appearance-preview scale and simplified row icon usage.

### Post-fix evidence

- `xcodebuild` succeeds for the macOS app.
- `git diff --check` succeeds.
- Visual evidence is unavailable because both supplied Petal captures are missing and the local app capture service timed out.

## Required fidelity surfaces

- Fonts and typography: System typography and hierarchy were adjusted toward the source; rendered verification is blocked.
- Spacing and layout rhythm: Window, detail width, row padding, section gaps, and radii were adjusted; rendered verification is blocked.
- Colors and visual tokens: Native semantic macOS colors remain in use; rendered verification is blocked.
- Image quality and asset fidelity: The supplied wallpaper asset remains used in the appearance selector; rendered verification is blocked.
- Copy and content: Existing Petal settings and behavior are preserved with shorter row copy.

## Remaining blocker

A same-state screenshot of the revised Petal Settings window is required for the final side-by-side comparison.

final result: blocked
