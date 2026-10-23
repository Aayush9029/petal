import SwiftUI

struct SettingsSwitch: View {
    let isOn: Bool
    let onChange: (Bool) -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn && isEnabled ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.25)))
                    .overlay {
                        if contrast == .increased {
                            Capsule().strokeBorder(.primary.opacity(0.6), lineWidth: 1)
                        }
                    }

                Circle()
                    .fill(.white)
                    .padding(2.5)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
            }
            .frame(width: 40, height: 22)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2, extraBounce: 0.08), value: isOn)
        .accessibilityRepresentation {
            Toggle(isOn: Binding(get: { isOn }, set: onChange)) { EmptyView() }
        }
    }
}

#Preview {
    HStack {
        SettingsSwitch(isOn: false) { _ in }
        SettingsSwitch(isOn: true) { _ in }
    }
    .padding()
}
