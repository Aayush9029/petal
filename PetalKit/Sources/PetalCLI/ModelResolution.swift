import Foundation
import Shared

public enum ModelResolutionError: Error, Equatable, LocalizedError {
    case unknownModel(String, available: [String])
    case notDownloaded(ModelOption)

    public var errorDescription: String? {
        switch self {
        case let .unknownModel(id, available):
            return "Unknown model '\(id)'. Models: \(available.joined(separator: ", "))."
        case let .notDownloaded(option):
            return "\(option.displayName) (\(option.rawValue)) is not downloaded. Download it in Petal Settings, or run 'petal models'."
        }
    }
}

public enum ModelResolution {
    /// Without `--model`, the CLI uses the model that Petal uses for dropped audio files: the file model if it is ready, else the dictation model.
    public static func resolve(
        requestedID: String?,
        selectedModelID: String,
        fileTranscriptionModelID: String,
        available: [ModelOption] = ModelOption.allCases,
        isDownloaded: (ModelOption) -> Bool
    ) throws -> ModelOption {
        func isReady(_ option: ModelOption) -> Bool {
            !option.requiresDownload || isDownloaded(option)
        }

        if let requestedID {
            guard let option = available.first(where: { $0.rawValue == requestedID }) else {
                throw ModelResolutionError.unknownModel(requestedID, available: available.map(\.rawValue))
            }
            guard isReady(option) else { throw ModelResolutionError.notDownloaded(option) }
            return option
        }

        if let fileModel = available.first(where: { $0.rawValue == fileTranscriptionModelID }), isReady(fileModel) {
            return fileModel
        }
        let selected = available.first { $0.rawValue == selectedModelID } ?? .defaultOption
        guard isReady(selected) else { throw ModelResolutionError.notDownloaded(selected) }
        return selected
    }
}
