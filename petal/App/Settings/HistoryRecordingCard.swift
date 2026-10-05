import Shared
import SwiftUI
import UI

struct HistoryRecordingCard: View {
    let entry: TranscriptHistoryEntry
    let text: HistoryEntryText
    let audioURL: URL?
    let isFailed: Bool
    let isReprocessing: Bool
    let canCleanUp: Bool
    let playback: HistoryPlaybackModel
    let onCopy: (String) -> Void
    let onTranscribeAgain: () -> Void
    let onTranscribeAndCleanUp: () -> Void
    let onDelete: () -> Void
    @State private var isShowingCopyConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                modelIcon

                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.caption.weight(.semibold))

                Text(durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if let app = entry.app {
                    appLabel(app)
                }

                Spacer()

                Button {
                    onCopy(text.output)
                    withAnimation(.snappy(duration: 0.18)) {
                        isShowingCopyConfirmation = true
                    }
                } label: {
                    Image(systemName: isShowingCopyConfirmation ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(isShowingCopyConfirmation ? .green : .primary)
                }
                .disabled(text.output.isEmpty)
                .help(text.cleanup == nil ? "Copy transcript" : "Copy cleaned-up text")

                reprocessMenu
            }
            .buttonStyle(.borderless)

            if let cleanup = text.cleanup {
                VStack(spacing: 0) {
                    HistoryTextBlock(title: "Cleaned Up", text: cleanup, isCleanup: true) { onCopy(cleanup) }
                    SettingsCardDivider()
                    HistoryTextBlock(title: "Transcript", text: text.transcript) { onCopy(text.transcript) }
                }
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
            } else {
                Text(displayTranscript)
                    .font(.subheadline)
                    .foregroundStyle(text.transcript.isEmpty ? .secondary : .primary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let audioURL {
                HStack(spacing: 10) {
                    Button {
                        playback.playButtonTapped(entryID: entry.id, audioURL: audioURL)
                    } label: {
                        Image(systemName: playback.isPlaying(entry.id) ? "pause.fill" : "play.fill")
                            .font(.caption.weight(.bold))
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.08), in: .circle)
                    }
                    .buttonStyle(.plain)

                    HistoryWaveformView(
                        samples: playback.waveforms[entry.id, default: []],
                        progress: playback.progress(for: entry.id),
                        onScrub: { playback.scrub(entryID: entry.id, audioURL: audioURL, to: $0) },
                        onPlay: { playback.playButtonTapped(entryID: entry.id, audioURL: audioURL) }
                    )
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    playback.activeEntryID == entry.id
                        ? Color.accentColor.opacity(0.7)
                        : Color(nsColor: .separatorColor).opacity(0.7),
                    lineWidth: playback.activeEntryID == entry.id ? 1.5 : 1
                )
        }
        .contentShape(.rect(cornerRadius: 14))
        .contextMenu {
            if let cleanup = text.cleanup {
                Button("Copy Cleaned-Up Text", systemImage: "sparkles") { onCopy(cleanup) }
            }
            Button("Copy Transcript", systemImage: "doc.on.doc") { onCopy(text.transcript) }
                .disabled(text.transcript.isEmpty)
            Divider()
            Button("Delete from History", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .task {
            if let audioURL {
                await playback.loadWaveform(for: entry.id, audioURL: audioURL)
            }
        }
        .task(id: isShowingCopyConfirmation) {
            guard isShowingCopyConfirmation else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                isShowingCopyConfirmation = false
            }
        }
    }

    @ViewBuilder
    private var reprocessMenu: some View {
        if isReprocessing {
            ProgressView()
                .controlSize(.small)
        } else {
            Menu {
                Button("Transcribe Again", systemImage: "arrow.clockwise", action: onTranscribeAgain)
                Button("Transcribe and Clean Up", systemImage: "sparkles", action: onTranscribeAndCleanUp)
                    .disabled(!canCleanUp)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(audioURL == nil)
            .help(canCleanUp ? "Transcribe this recording again" : "Transcribe this recording again. Turn on text cleanup in Intelligence to clean it up too.")
        }
    }

    private func appLabel(_ app: FocusedApp) -> some View {
        HStack(spacing: 4) {
            RouteIcon(trigger: .app(app.app), size: 14)
            Text(app.website ?? app.app.name)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(app.website.map { "\(app.app.name) · \($0)" } ?? app.app.name)
    }

    private var modelIcon: some View {
        ModelOption.from(modelID: entry.modelID).provider.icon
            .resizable()
            .scaledToFill()
            .frame(width: 22, height: 22)
            .clipShape(.rect(cornerRadius: 6))
            .overlay(alignment: .bottomTrailing) {
                if isFailed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .background(.background, in: .circle)
                        .offset(x: 3, y: 3)
                }
            }
            .help(ModelOption.from(modelID: entry.modelID).displayName)
    }

    private var displayTranscript: String {
        if !text.transcript.isEmpty {
            return text.transcript
        }
        return isFailed ? "Transcription failed — the recording was saved." : "No speech was detected."
    }

    private var durationText: String {
        let total = max(0, Int(entry.audioDurationSeconds.rounded()))
        if total < 60 {
            return "\(total)s"
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
