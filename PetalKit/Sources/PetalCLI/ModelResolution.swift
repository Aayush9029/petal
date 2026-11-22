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
    public static func resolve(
        requestedID: String?,
        selectedModelID: String,
        fileTranscriptionModelID: String,
        available: [ModelOption] = ModelOption.allCases,
        isDownloaded: (ModelOption) -> Bool
    ) throws -> ModelOption {
        if let requestedID {
            guard let option = available.first(where: { $0.rawValue == requestedID }) else {
                throw ModelResolutionError.unknownModel(requestedID, available: available.map(\.rawValue))
            }
            guard isDownloaded(option) else { throw ModelResolutionError.notDownloaded(option) }
            return option
        }

        let dictationModel = available.first { $0.rawValue == selectedModelID }
        let selected = ModelOption.fileOverride(
            id: fileTranscriptionModelID, dictationModel: dictationModel,
            available: available, isReady: isDownloaded
        ) ?? dictationModel ?? .defaultOption
        guard isDownloaded(selected) else { throw ModelResolutionError.notDownloaded(selected) }
        return selected
    }
}
