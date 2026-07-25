import SwiftUI

struct TranscriptRow: View {
    private static let actionsWidth: CGFloat = 54
    private static let actionsScrimWidth: CGFloat = 106
    private static let iconButtonSize: CGFloat = 26

    let entry: MenuBarContentViewModel.HistoryMenuItem
    let copy: () -> Void
    let delete: () -> Void

    @State private var isHovering = false
    @State private var isHoveringCopy = false
    @State private var isHoveringDelete = false
    @State private var didCopy = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(entry.title)
                .font(.system(size: 13))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(.rect)
                .onTapGesture(perform: copyTapped)

            if actionsAreVisible {
                actionOverlay
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect(cornerRadius: 6))
        .animation(.snappy(duration: 0.15), value: actionsAreVisible)
        .onHover { isHovering = $0 }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }

    private func copyTapped() {
        copy()
        didCopy = true
    }

    private var actionsAreVisible: Bool {
        isHovering || didCopy
    }

    private var actionOverlay: some View {
        ZStack(alignment: .trailing) {
            Rectangle()
                .fill(.thinMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.45), location: 0.35),
                            .init(color: .white.opacity(0.9), location: 0.68),
                            .init(color: .white, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .allowsHitTesting(false)

            actionButtons
                .frame(width: Self.actionsWidth)
                .padding(.trailing, 6)
        }
        .frame(width: Self.actionsScrimWidth)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            Button(action: copyTapped) {
                Image(systemName: didCopy ? "checkmark" : (isHoveringCopy ? "doc.on.doc.fill" : "doc.on.doc"))
                    .contentTransition(.symbolEffect(.replace))
                    .font(.callout.weight(.semibold))
                    .frame(width: Self.iconButtonSize, height: Self.iconButtonSize)
                    .contentShape(.rect(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(didCopy ? Color.green : (isHoveringCopy ? .primary : .secondary))
            .help(didCopy ? "Copied" : "Copy Transcript")
            .onHover { isHoveringCopy = $0 }

            Button(action: delete) {
                Image(systemName: isHoveringDelete ? "trash.fill" : "trash")
                    .font(.callout.weight(.semibold))
                    .frame(width: Self.iconButtonSize, height: Self.iconButtonSize)
                    .contentShape(.rect(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isHoveringDelete ? Color.red : .secondary)
            .help("Delete Transcript")
            .onHover { isHoveringDelete = $0 }
        }
        .animation(.snappy(duration: 0.18), value: didCopy)
        .animation(.snappy(duration: 0.15), value: isHoveringCopy)
        .animation(.snappy(duration: 0.15), value: isHoveringDelete)
    }
}
