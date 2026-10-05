import Foundation

/// The files History shows for one recording.
public struct HistoryEntryContents: Equatable, Sendable {
    public var transcript: String
    /// `nil` when no cleanup changed the transcript.
    public var cleanup: String?
    /// `nil` when the recording is not on disk.
    public var audioURL: URL?

    public init(transcript: String = "", cleanup: String? = nil, audioURL: URL? = nil) {
        self.transcript = transcript
        self.cleanup = cleanup
        self.audioURL = audioURL
    }
}
