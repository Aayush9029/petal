import SwiftUI

struct HistoryDayHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(count, format: .number)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 18)
                .background(Color.primary.opacity(0.08), in: .capsule)
                .accessibilityHidden(true)
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(height: 28)
        .settingsGlass(in: .capsule)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    HistoryDayHeader(title: "Today", count: 12)
        .padding()
}
