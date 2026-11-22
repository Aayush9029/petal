import Foundation

public struct HistoryEntryContents: Equatable, Sendable {
    public var transcript: String
    /// `nil` when no cleanup changed the transcript.
    public var cleanup: String?
    public var audioURL: URL?

    public init(transcript: String = "", cleanup: String? = nil, audioURL: URL? = nil) {
        self.transcript = transcript
        self.cleanup = cleanup
        self.audioURL = audioURL
    }
}
