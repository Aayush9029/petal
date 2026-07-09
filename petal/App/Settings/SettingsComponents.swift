import Shared
import SwiftUI

struct SettingsPaneLayout<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    SettingsTabIcon(tab: tab, size: 34)
                    Text(tab.title)
                        .font(.title2.weight(.bold))
                }

                content()
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 40)
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

            content()
                .padding(14)
                .background(.quaternary.opacity(0.7), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.separator.opacity(0.65), lineWidth: 1)
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

            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 3)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var description: String?
    var symbol: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, description: description, symbol: symbol) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct SettingsCardDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, -14)
            .padding(.vertical, 9)
    }
}
