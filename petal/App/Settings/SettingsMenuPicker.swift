import SwiftUI

struct SettingsMenuPicker<Value: Hashable>: View {
    let values: [Value]
    let selection: Value
    let title: (Value) -> String
    let onSelect: (Value) -> Void

    var body: some View {
        Menu {
            ForEach(values, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    if value == selection {
                        Label(title(value), systemImage: "checkmark")
                    } else {
                        Text(title(value))
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Text(title(selection))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .contentShape(.rect)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .contentShape(.rect)
        .fixedSize()
    }
}
