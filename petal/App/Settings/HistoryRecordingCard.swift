import Shared
import SwiftUI

struct HistoryRecordingCard: View {
    let entry: TranscriptHistoryEntry
    let transcript: String
    let audioURL: URL?
    let isFailed: Bool
    let isReprocessing: Bool
    let playback: HistoryPlaybackModel
    let onCopy: () -> Void
    let onReprocess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: isFailed ? "exclamationmark.circle.fill" : "waveform")
                    .foregroundStyle(isFailed ? .orange : Color.accentColor)

                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.caption.weight(.semibold))

                Text(durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(transcript.isEmpty)
                .help("Copy transcript")

                Button(action: onReprocess) {
                    if isReprocessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(audioURL == nil || isReprocessing)
                .help("Transcribe this recording again")
            }
            .buttonStyle(.borderless)

            Text(displayTranscript)
                .font(.subheadline)
                .foregroundStyle(transcript.isEmpty ? .secondary : .primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .task {
            if let audioURL {
                await playback.loadWaveform(for: entry.id, audioURL: audioURL)
            }
        }
    }

    private var displayTranscript: String {
        if !transcript.isEmpty {
            return transcript
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
