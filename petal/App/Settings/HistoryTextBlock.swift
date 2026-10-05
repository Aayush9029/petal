import SwiftUI

/// One labeled text in a history card, with its own copy button.
struct HistoryTextBlock: View {
    let title: String
    let text: String
    var isCleanup = false
    let onCopy: () -> Void
    @State private var isShowingCopyConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                label
                Spacer()
                Button {
                    onCopy()
                    withAnimation(.snappy(duration: 0.18)) {
                        isShowingCopyConfirmation = true
                    }
                } label: {
                    Image(systemName: isShowingCopyConfirmation ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(isShowingCopyConfirmation ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Copy \(title.lowercased())")
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(isCleanup ? .primary : .secondary)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .task(id: isShowingCopyConfirmation) {
            guard isShowingCopyConfirmation else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                isShowingCopyConfirmation = false
            }
        }
    }

    private var label: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

#Preview {
    VStack(spacing: 0) {
        HistoryTextBlock(title: "Cleaned Up", text: "So, can you send the report to Sam by Thursday?", isCleanup: true) {}
        Divider()
        HistoryTextBlock(title: "Transcript", text: "um so can you like send the the report to sam by friday no wait thursday") {}
    }
    .frame(width: 440)
    .padding()
}
