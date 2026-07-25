import SwiftUI
import UI

struct MenuBarPopover: View {
    private static let waveformHeight: CGFloat = 68
    private static let transcriptListHeight: CGFloat = 152
    private static let cornerRadius: CGFloat = 14

    let viewModel: MenuBarContentViewModel
    var dismiss: () -> Void

    @State private var transcriptPendingDeletion: MenuBarContentViewModel.HistoryMenuItem?
    @State private var isAudioDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusCard
            permissionSection

            transcriptsSection

            Divider().padding(.horizontal, 4)

            actions
        }
        .padding(8)
        .frame(width: PopupPanelController.contentWidth)
        .background {
            VisualEffectBackground()
                .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            if isAudioDropTargeted {
                audioDropOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await viewModel.audioFilesDropped(urls) }
            return !urls.isEmpty
        } isTargeted: {
            isAudioDropTargeted = $0
        }
        .animation(.easeOut(duration: 0.16), value: isAudioDropTargeted)
        .alert("Delete Transcript?", isPresented: isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let transcriptPendingDeletion {
                    viewModel.deleteHistoryEntry(transcriptPendingDeletion.id)
                }
                transcriptPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { transcriptPendingDeletion = nil }
        } message: {
            Text("This permanently removes it from your history.")
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(spacing: 8) {
            // The recording and processing waveforms have a fixed intrinsic
            // width from their bar count; as an overlay they cannot widen the
            // card the way the idle view, which just fills, does not.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.waveformHeight)
                .overlay { waveform }
                .clipped()

            HStack(spacing: 6) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 6, height: 6)
                Text(viewModel.statusHeadline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .help(viewModel.statusHeadline)
        }
        .padding(10)
        .petalGlass(cornerRadius: Self.cornerRadius)
    }

    private var statusTint: Color {
        switch viewModel.iconState {
        case .recording: .red
        case .working: .orange
        case .error: .red
        case .idle: .green
        }
    }

    /// Idle draws Conway's Game of Life; the active states draw the pixel waveform.
    @ViewBuilder
    private var waveform: some View {
        switch viewModel.iconState {
        case .idle, .error:
            GameOfLifeView(tint: .accentColor)
        case .recording:
            LiveWaveform(
                level: viewModel.audioLevel,
                bars: 72,
                rows: 17,
                tint: .red,
                sampleInterval: .milliseconds(66)
            )
        case .working:
            ProcessingWaveform(bars: 72, rows: 17, tint: .accentColor)
        }
    }

    // MARK: - Permissions

    @ViewBuilder
    private var permissionSection: some View {
        if viewModel.shouldShowPermissionsSection {
            VStack(spacing: 6) {
                if viewModel.needsMicrophonePermission {
                    PermissionCalloutRow(title: "Allow Microphone Access", systemImage: "mic.fill") {
                        viewModel.requestMicrophonePermission()
                        dismiss()
                    }
                }
                if viewModel.needsAccessibilityPermission {
                    PermissionCalloutRow(title: "Turn On Accessibility", systemImage: "hand.raised.fill") {
                        viewModel.requestAccessibilityPermission()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Transcripts

    private var transcriptsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Transcripts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            transcriptList
                .frame(height: Self.transcriptListHeight)
        }
    }

    @ViewBuilder
    private var transcriptList: some View {
        if !viewModel.shouldShowHistoryMenu || viewModel.historyMenuItems.isEmpty {
            Text(emptyTranscriptsMessage)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(viewModel.historyMenuItems) { entry in
                        TranscriptRow(
                            entry: entry,
                            copy: { viewModel.copyHistoryEntry(entry.id) },
                            delete: { transcriptPendingDeletion = entry }
                        )
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var emptyTranscriptsMessage: String {
        viewModel.shouldShowHistoryMenu ? "No transcripts yet" : "History is turned off"
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if viewModel.isRecording {
            PopupMenuRow(title: "Stop Recording", systemImage: "stop.fill", isDestructive: true) {
                viewModel.stopRecording()
                dismiss()
            }
        } else {
            PopupMenuRow(title: "Start Recording", systemImage: "mic.fill") {
                viewModel.startRecording()
                dismiss()
            }
        }

        PopupMenuRow(title: "Petal Settings…", systemImage: "gearshape", shortcut: "⌘,") {
            viewModel.openSettings()
            dismiss()
        }
        PopupMenuRow(title: "About Petal", systemImage: "info.circle") {
            viewModel.showAbout()
            dismiss()
        }
        // Always present, merely disabled: inserting it once Sparkle finishes starting would change the panel's height under the pointer.
        PopupMenuRow(
            title: "Check for Updates…",
            systemImage: "arrow.triangle.2.circlepath",
            isEnabled: viewModel.canCheckForUpdates
        ) {
            viewModel.checkForUpdates()
            dismiss()
        }
        PopupMenuRow(title: "Quit Petal", systemImage: "power", shortcut: "⌘Q") {
            viewModel.quit()
        }
    }

    // MARK: - Drop target

    private var audioDropOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)

            Text("Drop to Transcribe")
                .font(.headline)

            Text("Petal copies the transcript when it's done.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        }
        .padding(4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop an audio file to transcribe it")
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { transcriptPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    transcriptPendingDeletion = nil
                }
            }
        )
    }
}
