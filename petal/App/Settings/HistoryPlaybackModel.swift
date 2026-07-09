import AVFAudio
import CoreGraphics
import Observation

@MainActor
@Observable
final class HistoryPlaybackModel {
    private(set) var activeEntryID: UUID?
    private(set) var isPlaying = false
    private(set) var progress = 0.0
    private(set) var waveforms: [UUID: [CGFloat]] = [:]

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var loadingWaveforms = Set<UUID>()

    func loadWaveform(for entryID: UUID, audioURL: URL) async {
        guard waveforms[entryID] == nil, !loadingWaveforms.contains(entryID) else { return }
        loadingWaveforms.insert(entryID)
        let samples = await HistoryWaveformSampler.samples(from: audioURL)
        waveforms[entryID] = samples
        loadingWaveforms.remove(entryID)
    }

    func playButtonTapped(entryID: UUID, audioURL: URL) {
        if activeEntryID == entryID, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                progressTask?.cancel()
            } else {
                player.play()
                isPlaying = true
                startProgressUpdates()
            }
            return
        }

        startPlayback(entryID: entryID, audioURL: audioURL)
    }

    func scrub(entryID: UUID, audioURL: URL, to fraction: Double) {
        if activeEntryID != entryID {
            startPlayback(entryID: entryID, audioURL: audioURL)
        }
        guard let player else { return }
        player.currentTime = max(0, min(1, fraction)) * player.duration
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
    }

    func progress(for entryID: UUID) -> Double {
        activeEntryID == entryID ? progress : 0
    }

    func isPlaying(_ entryID: UUID) -> Bool {
        activeEntryID == entryID && isPlaying
    }

    private func startPlayback(entryID: UUID, audioURL: URL) {
        progressTask?.cancel()
        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.prepareToPlay()
            player.play()
            self.player = player
            activeEntryID = entryID
            isPlaying = true
            progress = 0
            startProgressUpdates()
        } catch {
            player = nil
            activeEntryID = nil
            isPlaying = false
            progress = 0
        }
    }

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
                if !player.isPlaying {
                    self.isPlaying = false
                    if self.progress >= 0.995 {
                        self.progress = 0
                        player.currentTime = 0
                    }
                    return
                }
                try? await clock.sleep(for: .milliseconds(50))
            }
        }
    }

    deinit {
        progressTask?.cancel()
    }
}
