import SwiftUI

struct SettingsSwitch: View {
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(isOn ? 0.48 : 0.25))

                Circle()
                    .fill(.white)
                    .padding(2.5)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
            }
            .frame(width: 44, height: 24)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2, extraBounce: 0.08), value: isOn)
        .accessibilityLabel(isOn ? "On" : "Off")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

#Preview {
    HStack {
        SettingsSwitch(isOn: false) { _ in }
        SettingsSwitch(isOn: true) { _ in }
    }
    .padding()
}
