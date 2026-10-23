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
            .frame(width: SettingsLayout.contentWidth, alignment: .leading)
            .padding(.horizontal, SettingsLayout.contentPadding)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SettingsBackdrop() }
    }
}

struct RecordingOptionTile: View {
    private static var cornerRadius: CGFloat { 14 }

    let title: String
    let description: String
    let symbol: String
    let artwork: Image
    let isOn: Bool
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                artwork
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                    .overlay {
                        Image(systemName: symbol)
                            .symbolVariant(.fill)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                    }
                    .clipShape(.rect(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
                .padding(.horizontal, 3)
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isHovering, !isOn {
                    cardShape.fill(.primary.opacity(0.05))
                }
            }
            .settingsSelection(isOn, in: cardShape)
            .overlay {
                cardShape.strokeBorder(borderColor, lineWidth: isOn ? 2 : 1)
            }
            .settingsGlass(in: cardShape)
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    private var borderColor: Color {
        if isOn { return .primary }
        if contrast == .increased { return .primary.opacity(0.55) }
        return .primary.opacity(isHovering ? 0.2 : 0.07)
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
