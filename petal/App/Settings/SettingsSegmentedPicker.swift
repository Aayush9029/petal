import SwiftUI

struct SettingsSegmentedPicker<Value: Hashable>: View {
    let values: [Value]
    let selection: Value
    let title: (Value) -> String
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(values, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Text(title(value))
                        .font(.caption.weight(selection == value ? .semibold : .medium))
                        .foregroundStyle(selection == value ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.2), value: selection)
    }
}
