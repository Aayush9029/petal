import Testing

/// These suites share one history folder per test process, and a retention change deletes its subfolders, so they run one at a time.
@Suite(.serialized)
struct HistoryFolderSuite {}
