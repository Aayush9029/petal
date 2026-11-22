import AppFeature
import HistoryClient
import Shared
import SwiftUI

struct HistoryPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var searchText = ""
    @State private var playback = HistoryPlaybackModel()

    var body: some View {
        let readyCleanupModels = viewModel.readyCleanupModels
        let days = viewModel.history.historyDays(matching: searchText)
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if !viewModel.history.hasLoadedHistory {
                    Color.clear
                } else if days.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                            ForEach(days) { day in
                                Section {
                                    ForEach(day.entries) { entry in
                                        HistoryRecordingCard(
                                            entry: entry,
                                            contents: viewModel.history.contents(for: entry),
                                            isReprocessing: viewModel.reprocessingHistoryEntryID == entry.id,
                                            canCleanUp: readyCleanupModels.contains(viewModel.historyCleanupModel(for: entry)),
                                            playback: playback,
                                            onCopy: { viewModel.copyButtonTapped($0) },
                                            onTranscribeAgain: {
                                                Task { await viewModel.reprocessHistoryEntry(entry, cleansUp: false) }
                                            },
                                            onTranscribeAndCleanUp: {
                                                Task { await viewModel.reprocessHistoryEntry(entry, cleansUp: true) }
                                            },
                                            onDelete: {
                                                playback.historyEntryDeleted(entry.id)
                                                viewModel.deleteHistoryEntry(entry)
                                            }
                                        )
                                    }
                                } header: {
                                    HistoryDayHeader(title: dayTitle(day), count: day.entries.count)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .safeAreaPadding(.bottom, 96)
                }
            }
            .frame(width: SettingsLayout.contentWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, SettingsLayout.contentPadding)

            HistorySearchField(text: $searchText)
                .frame(maxWidth: 360)
                .padding(.horizontal, 26)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SettingsBackdrop() }
        .task {
            await viewModel.history.historyTask()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            HistoryEmptyState()
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func dayTitle(_ day: TranscriptHistoryDay) -> String {
        guard let date = day.entries.first?.timestamp else { return day.day }
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
