import CloudCleanupFeature
import Shared
import SwiftUI

struct CloudModelPickerList: View {
    let selection: CloudModel.ID
    let modelList: CloudCleanupModel.ModelList
    let search: (String) -> CloudModelSearchResults
    let onReload: () -> Void
    let onSelect: (CloudModel.ID) -> Void
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let results = search(query)
        VStack(spacing: 0) {
            searchField(results: results)
                .padding(10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    section("Suggested", models: results.suggested)
                    section(allModelsTitle(results.all.count), models: results.all)
                    if let customID = results.customID {
                        section("Custom")
                        CloudModelRow(
                            title: "Use “\(customID.rawValue)”",
                            subtitle: "Any model ID that the provider accepts",
                            isMonospaced: false,
                            symbol: "plus.circle",
                            isSelected: false
                        ) { onSelect(customID) }
                    }
                    status(results: results)
                }
                .padding(6)
            }
            .frame(height: 340)
        }
        .frame(width: 400)
        .onAppear { isSearchFocused = true }
    }

    private func allModelsTitle(_ count: Int) -> String {
        modelList.is(\.loaded) ? "All Models (\(count))" : "All Models"
    }

    private func searchField(results: CloudModelSearchResults) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search models or enter an ID", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    if let first = results.suggested.first?.id ?? results.all.first?.id ?? results.customID {
                        onSelect(first)
                    }
                }
            Button("Reload Models", systemImage: "arrow.clockwise", action: onReload)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(modelList.is(\.loading))
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func section(_ title: String, models: IdentifiedArrayOf<CloudModel>) -> some View {
        if !models.isEmpty {
            section(title)
            ForEach(models) { model in
                CloudModelRow(
                    title: model.title,
                    subtitle: [model.name == nil ? nil : model.id.rawValue, model.note].compactMap(\.self).joined(separator: " · "),
                    isSelected: model.id == selection
                ) { onSelect(model.id) }
            }
        }
    }

    @ViewBuilder
    private func status(results: CloudModelSearchResults) -> some View {
        switch modelList {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading models…")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(10)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(10)
        case .loaded:
            if results.isEmpty {
                Text("No models match.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
    }
}
