import Shared
import SwiftUI
import UI

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
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct RecordingOptionTile: View {
    let title: String
    let description: String
    let symbol: DottedStatusGlyph.Kind
    let isOn: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DottedStatusGlyph(
                    kind: symbol,
                    tint: isOn ? Color.accentColor : .secondary
                )
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(isOn ? 0.12 : 0.06), in: .rect(cornerRadius: 8))

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
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                Color.primary.opacity(isHovering ? 0.055 : (isOn ? 0.025 : 0))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
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
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(tint, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsPanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            SettingsPanel(content: content)
        }
    }
}

struct SettingsControlRow<Control: View>: View {
    let title: String
    var description: String?
    var symbol: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
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
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        SettingsControlRow(title: title, description: description, symbol: symbol) {
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
