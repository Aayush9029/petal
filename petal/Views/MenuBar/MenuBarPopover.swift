import SwiftUI
import UI

/// The custom menu-bar popover — a compact panel with the pixel waveform on top
/// (idle / recording / processing animation), recent transcripts, and actions.
struct MenuBarPopover: View {
    private static let recentTranscriptsMaxHeight: CGFloat = 188

    let viewModel: MenuBarContentViewModel
    var dismiss: () -> Void

    @State private var transcriptPendingDeletion: MenuBarContentViewModel.HistoryMenuItem?

    private var isRecording: Bool { viewModel.isRecording }

    private var waveformTint: Color {
        isRecording ? .red : .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            waveformCard
            permissionSection
            messageBanner

            Divider().padding(.vertical, 6)

            transcriptsSection

            Divider().padding(.vertical, 6)

            actions
        }
        .padding(12)
        .frame(width: 312)
        .alert("Delete transcript?", isPresented: deleteConfirmationIsPresented) {
            Button("Delete", role: .destructive) {
                if let entry = transcriptPendingDeletion {
                    viewModel.deleteHistoryEntry(entry.id)
                }
                transcriptPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                transcriptPendingDeletion = nil
            }
        } message: {
            Text("This removes the transcript from recent history.")
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { transcriptPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    transcriptPendingDeletion = nil
                }
            }
        )
    }

    // MARK: - Waveform

    private var waveformCard: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary.opacity(0.5))
            // Idle → Conway's Game of Life easter egg; active → the pixel EQ.
            switch viewModel.iconState {
            case .idle, .error:
                GameOfLifeView(tint: .accentColor)
                    .padding(4)
            case .recording:
                PixelWaveform(.recording(level: viewModel.audioLevel), bars: 46, maxHalf: 5, tint: .red)
            case .working:
                PixelWaveform(.processing, bars: 46, maxHalf: 5, tint: waveformTint)
            }
        }
        .frame(height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Permissions

    @ViewBuilder
    private var permissionSection: some View {
        if viewModel.shouldShowPermissionsSection {
            VStack(spacing: 6) {
                if viewModel.needsMicrophonePermission {
                    CalloutButton(icon: "mic.fill", title: "Allow microphone access") {
                        viewModel.requestMicrophonePermission()
                        dismiss()
                    }
                }
                if viewModel.needsAccessibilityPermission {
                    CalloutButton(icon: "hand.raised.fill", title: "Turn on Accessibility") {
                        viewModel.requestAccessibilityPermission()
                        dismiss()
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var messageBanner: some View {
        if let message = viewModel.statusErrorMessage ?? viewModel.transientMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    // MARK: - Transcripts

    @ViewBuilder
    private var transcriptsSection: some View {
        Text("Recent Transcripts")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)

        if !viewModel.shouldShowHistoryMenu || viewModel.historyMenuItems.isEmpty {
            Text("No transcripts yet")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        } else {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(viewModel.historyMenuItems) { entry in
                        TranscriptRow(
                            entry: entry,
                            copy: {
                                viewModel.copyHistoryEntry(entry.id)
                            },
                            delete: {
                                transcriptPendingDeletion = entry
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: Self.recentTranscriptsMaxHeight)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 1) {
            if isRecording {
                PopoverRow(title: "Stop Recording", tint: .red) {
                    viewModel.stopRecording()
                    dismiss()
                }
            } else {
                PopoverRow(title: "Start Recording", tint: .accentColor) {
                    viewModel.startRecording()
                    dismiss()
                }
            }
            PopoverRow(title: "Settings", shortcut: "⌘,") {
                viewModel.openSettings()
                dismiss()
            }
            PopoverRow(title: "About Petal") {
                viewModel.showAbout()
                dismiss()
            }
            if viewModel.showsCheckForUpdates {
                PopoverRow(title: "Check for Updates…") {
                    viewModel.checkForUpdates()
                    dismiss()
                }
                .disabled(!viewModel.canCheckForUpdates)
            }
            PopoverRow(title: "Quit Petal", shortcut: "⌘Q") {
                viewModel.quit()
            }
        }
    }
}

// MARK: - Rows

private struct TranscriptRow: View {
    private static let actionsWidth: CGFloat = 54
    private static let actionsScrimWidth: CGFloat = 106
    private static let iconButtonSize: CGFloat = 26

    var entry: MenuBarContentViewModel.HistoryMenuItem
    var copy: () -> Void
    var delete: () -> Void

    @State private var hovering = false
    @State private var copyIconHovering = false
    @State private var deleteIconHovering = false
    @State private var didCopy = false
    @State private var resetCopyIconTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(entry.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: copyButtonTapped)

            if actionsAreVisible {
                actionOverlay
                    .transition(
                        .opacity.combined(with: .move(edge: .trailing))
                    )
            }
        }
        .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.15), value: actionsAreVisible)
        .onHover { hovering = $0 }
        .onDisappear {
            resetCopyIconTask?.cancel()
            copyIconHovering = false
            deleteIconHovering = false
        }
    }

    private func copyButtonTapped() {
        copy()
        didCopy = true
        resetCopyIconTask?.cancel()
        resetCopyIconTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }

    private var actionsAreVisible: Bool {
        hovering || didCopy
    }

    private var copyIconName: String {
        copyIconHovering ? "doc.on.doc.fill" : "doc.on.doc"
    }

    private var copyIconColor: Color {
        if didCopy {
            return .green
        }
        return copyIconHovering ? .primary : .secondary
    }

    private var deleteIconName: String {
        deleteIconHovering ? "trash.fill" : "trash"
    }

    private var deleteIconColor: Color {
        deleteIconHovering ? .red : .secondary
    }

    private var actionOverlay: some View {
        ZStack(alignment: .trailing) {
            Rectangle()
                .fill(.thinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.primary.opacity(0.04),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
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
                .blur(radius: 0.8)
                .allowsHitTesting(false)

            actionButtons
                .frame(width: Self.actionsWidth)
                .padding(.trailing, 6)
                .allowsHitTesting(actionsAreVisible)
        }
        .frame(width: Self.actionsScrimWidth)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            Button(action: copyButtonTapped) {
                ZStack {
                    Image(systemName: copyIconName)
                        .scaleEffect(didCopy ? 0.65 : 1)
                        .opacity(didCopy ? 0 : 1)
                    Image(systemName: "checkmark")
                        .scaleEffect(didCopy ? 1 : 0.65)
                        .opacity(didCopy ? 1 : 0)
                }
                .font(.callout.weight(.semibold))
                .frame(width: Self.iconButtonSize, height: Self.iconButtonSize)
                .animation(.snappy(duration: 0.2), value: didCopy)
                .animation(.snappy(duration: 0.15), value: copyIconHovering)
            }
            .buttonStyle(.plain)
            .foregroundStyle(copyIconColor)
            .help(didCopy ? "Copied" : "Copy transcript")
            .onHover { copyIconHovering = $0 }

            Button(action: delete) {
                Image(systemName: deleteIconName)
                    .font(.callout.weight(.semibold))
                    .frame(width: Self.iconButtonSize, height: Self.iconButtonSize)
                    .animation(.snappy(duration: 0.15), value: deleteIconHovering)
            }
            .buttonStyle(.plain)
            .foregroundStyle(deleteIconColor)
            .help("Delete transcript")
            .onHover { deleteIconHovering = $0 }
        }
    }
}

/// A full-width hover-highlighted action row.
private struct PopoverRow: View {
    var icon: String? = nil
    var title: String
    var subtitle: String? = nil
    var shortcut: String? = nil
    var titleFont: Font = .headline.weight(.regular)
    var tint: Color = .primary
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(tint)
                        .frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A prominent blue call-to-action (used for permission prompts).
private struct CalloutButton: View {
    var icon: String
    var title: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color(red: 0.0, green: 0.33, blue: 0.82) : Color.blue, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
