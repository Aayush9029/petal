import CloudCleanupFeature
import Shared
import SwiftUI

struct CloudModelPicker: View {
    let selection: CloudModel
    let modelList: CloudCleanupModel.ModelList
    let search: (String) -> CloudModelSearchResults
    let onOpen: () async -> Void
    let onReload: () async -> Void
    let onSelect: (CloudModel.ID) -> Void
    @State private var isPresented = false

    var body: some View {
        SettingsControlRow(title: "Model", description: description) {
            Button {
                isPresented = true
            } label: {
                HStack(spacing: 7) {
                    Text(selection.rawTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 11)
                .frame(maxWidth: 230, minHeight: 30)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                CloudModelPickerList(
                    selection: selection.id,
                    modelList: modelList,
                    search: search,
                    onReload: { Task { await onReload() } },
                    onSelect: { id in
                        onSelect(id)
                        isPresented = false
                    }
                )
                .task { await onOpen() }
            }
        }
    }

    private var description: String {
        [selection.name == nil ? nil : selection.id.rawValue, selection.note].compactMap(\.self).joined(separator: " · ")
    }
}

private extension CloudModel {
    var rawTitle: String {
        id.rawValue.isEmpty ? "Choose a Model" : title
    }
}
