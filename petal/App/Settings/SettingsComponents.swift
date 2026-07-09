import Shared
import SwiftUI

struct SettingsPaneLayout<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    SettingsTabIcon(tab: tab, size: 28)
                    Text(tab.title)
                        .font(.title3.weight(.semibold))
                }

                content()
            }
            .frame(maxWidth: 500, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsSectionGroup<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 14)

            VStack(spacing: 0) {
                content()
            }
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
                }
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
