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
            .font(.caption.weight(.semibold))
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
                PopoverRow(icon: "stop.fill", title: "Stop Recording", tint: .red) {
                    viewModel.stopRecording()
                    dismiss()
                }
            } else {
                PopoverRow(icon: "record.circle", title: "Start Recording", tint: .accentColor) {
                    viewModel.startRecording()
                    dismiss()
                }
            }
            PopoverRow(icon: "gearshape", title: "Settings", shortcut: "⌘,") {
                viewModel.openSettings()
                dismiss()
            }
            PopoverRow(icon: "info.circle", title: "About Petal") {
                viewModel.showAbout()
                dismiss()
            }
            if viewModel.showsCheckForUpdates {
                PopoverRow(icon: "arrow.triangle.2.circlepath", title: "Check for Updates…") {
                    viewModel.checkForUpdates()
                    dismiss()
                }
                .disabled(!viewModel.canCheckForUpdates)
            }
            PopoverRow(icon: "power", title: "Quit Petal", shortcut: "⌘Q") {
                viewModel.quit()
            }
        }
    }
}

// MARK: - Rows

private struct TranscriptRow: View {
    var entry: MenuBarContentViewModel.HistoryMenuItem
    var copy: () -> Void
    var delete: () -> Void

    @State private var hovering = false
    @State private var didCopy = false
    @State private var resetCopyIconTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 2) {
                Button(action: copyButtonTapped) {
                    ZStack {
                        Image(systemName: "doc.on.doc")
                            .scaleEffect(didCopy ? 0.65 : 1)
                            .opacity(didCopy ? 0 : 1)
                        Image(systemName: "checkmark")
                            .scaleEffect(didCopy ? 1 : 0.65)
                            .opacity(didCopy ? 1 : 0)
                    }
                    .font(.caption)
                    .frame(width: 22, height: 22)
                    .animation(.snappy(duration: 0.2), value: didCopy)
                }
                .buttonStyle(.plain)
                .foregroundStyle(didCopy ? .green : .secondary)
                .help(didCopy ? "Copied" : "Copy transcript")

                Button(action: delete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Delete transcript")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onDisappear {
            resetCopyIconTask?.cancel()
        }
    }

    private func copyButtonTapped() {
        copy()
        didCopy = true
        resetCopyIconTask?.cancel()
        resetCopyIconTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}

/// A full-width hover-highlighted action row.
private struct PopoverRow: View {
    var icon: String? = nil
    var title: String
    var subtitle: String? = nil
    var shortcut: String? = nil
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
                        .font(.subheadline)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
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
