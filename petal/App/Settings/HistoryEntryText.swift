/// The two texts History shows for a recording. `cleanup` is `nil` when no cleanup changed the transcript.
struct HistoryEntryText: Equatable {
    var transcript = ""
    var cleanup: String?

    var output: String {
        cleanup ?? transcript
    }
}
