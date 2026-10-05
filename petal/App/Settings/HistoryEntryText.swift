/// The two texts History shows for a recording. `cleanup` is `nil` when no cleanup changed the transcript.
nonisolated struct HistoryEntryText: Equatable, Sendable {
    var transcript = ""
    var cleanup: String?

    var output: String {
        cleanup ?? transcript
    }
}
