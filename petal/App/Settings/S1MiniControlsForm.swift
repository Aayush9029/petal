import Shared
import SwiftUI

struct S1MiniControlsForm: View {
    let controls: S1MiniControls
    let onStylingChange: (S1MiniStyling) -> Void
    let onStructureChange: (S1MiniStructure) -> Void
    let onContextChange: (S1MiniContext) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Style")
                    .font(.body.weight(.medium))
                SettingsSegmentedPicker(
                    values: S1MiniStyling.allCases,
                    selection: controls.styling,
                    title: \.displayName,
                    onSelect: onStylingChange
                )
                S1MiniStylePreview(input: S1MiniStyling.exampleInput, output: controls.styling.example)
            }
            .padding(16)

            SettingsCardDivider()

            SettingsControlRow(
                title: "Structure",
                description: "Lists need three or more items."
            ) {
                SettingsSegmentedPicker(
                    values: S1MiniStructure.allCases,
                    selection: controls.structure,
                    title: \.displayName,
                    onSelect: onStructureChange
                )
                .frame(width: 205)
            }

            SettingsCardDivider()

            SettingsControlRow(
                title: "Format",
                description: "Email adds a greeting line and a sign-off."
            ) {
                SettingsSegmentedPicker(
                    values: S1MiniContext.allCases,
                    selection: controls.context,
                    title: \.displayName,
                    onSelect: onContextChange
                )
                .frame(width: 205)
            }
        }
    }
}

#Preview {
    S1MiniControlsForm(
        controls: S1MiniControls(),
        onStylingChange: { print($0) },
        onStructureChange: { print($0) },
        onContextChange: { print($0) }
    )
    .frame(width: 500)
}
