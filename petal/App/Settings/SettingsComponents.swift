import Shared
import SwiftUI

struct SettingsPaneLayout<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .frame(maxWidth: 500, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SettingsDetailBackground().ignoresSafeArea() }
    }
}

struct RecordingOptionTile: View {
    let title: String
    let description: String
    let symbol: String
    var tint = Color.accentColor
    let isOn: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SettingsIconTile(symbol: symbol, fill: tint, size: 30, isActive: isOn)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? tint : Color.secondary.opacity(0.45))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background {
                Rectangle()
                    .fill(Color.primary.opacity(isHovering ? 0.055 : 0))
                    .padding(.vertical, 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(description)
    }
}

struct SettingsActionButton: View {
    let title: String
    var tint = Color.accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 2)
        }
        .settingsGlassButtonStyle(prominent: true)
        .tint(tint)
        .controlSize(.small)
    }
}

struct SettingsPanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        SettingsSection(title: title) {
            SettingsPanel(content: content)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            content()
        }
    }
}

struct SettingsControlRow<Control: View>: View {
    let title: String
    var description: String?
    var symbol: String?
    var tint = Color.gray
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                SettingsIconTile(symbol: symbol, fill: tint, size: 26)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 48)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var description: String?
    var symbol: String?
    var tint = Color.gray
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        SettingsControlRow(title: title, description: description, symbol: symbol, tint: tint) {
            SettingsSwitch(isOn: isOn, onChange: onChange)
        }
    }
}

struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.65))
            .frame(height: 1)
    }
}
