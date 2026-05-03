import Dependencies
import DependenciesMacros
import Foundation
import MLXClient
import Shared

public struct DownloadProgress: Sendable, Equatable {
    public var fractionCompleted: Double
    public var status: String
    public var speedText: String?

    public init(fractionCompleted: Double, status: String, speedText: String?) {
        self.fractionCompleted = fractionCompleted
        self.status = status
        self.speedText = speedText
    }
}

public enum DownloadClientFailure: LocalizedError, Sendable, Equatable {
    case paused
    case cancelled
    case aria2BinaryMissing
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .paused:
            return "Download paused"
        case .cancelled:
            return "Download cancelled"
        case .aria2BinaryMissing:
            return "aria2c binary is missing from the app bundle or system PATH."
        case let .failed(message):
            return message
        }
    }
}

@DependencyClient
public struct DownloadClient: Sendable {
    public var isModelDownloaded: @Sendable (ModelOption) -> Bool = { _ in false }
    public var downloadModel: @Sendable (ModelOption, @escaping @Sendable (DownloadProgress) -> Void) async throws -> Void
    public var pauseDownload: @Sendable () -> Void = {}
    public var cancelDownload: @Sendable () -> Void = {}
    public var modelDirectoryURL: @Sendable (ModelOption) -> URL? = { _ in nil }
    public var deleteModel: @Sendable (ModelOption) async throws -> Void
}

extension DownloadClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            isModelDownloaded: { option in
                if !option.requiresDownload {
                    return true
                }
                @Dependency(\.mlxClient) var mlxClient
                guard let info = option.mlxModelInfo else { return false }
                return mlxClient.isModelDownloaded(info)
            },
            downloadModel: { option, progress in
                if !option.requiresDownload {
                    progress(
                        DownloadProgress(
                            fractionCompleted: 1,
                            status: "No download required for this model.",
                            speedText: nil
                        )
                    )
                    return
                }

                @Dependency(\.mlxClient) var mlxClient
                guard let info = option.mlxModelInfo else {
                    throw DownloadClientFailure.failed("Selected model does not support downloads.")
                }
                do {
                    try await mlxClient.downloadModel(info, { fractionCompleted, status in
                        progress(
                            DownloadProgress(
                                fractionCompleted: min(max(fractionCompleted, 0), 1),
                                status: status,
                                speedText: speedText(from: status)
                            )
                        )
                    })
                } catch {
                    throw DownloadClientFailure(error)
                }
            },
            pauseDownload: {
                @Dependency(\.mlxClient) var mlxClient
                mlxClient.pauseDownload()
            },
            cancelDownload: {
                @Dependency(\.mlxClient) var mlxClient
                mlxClient.cancelDownload()
            },
            modelDirectoryURL: { option in
                if !option.requiresDownload {
                    return nil
                }
                @Dependency(\.mlxClient) var mlxClient
                guard let info = option.mlxModelInfo else { return nil }
                return mlxClient.modelDirectoryURL(info)
            },
            deleteModel: { option in
                if !option.requiresDownload {
                    return
                }
                @Dependency(\.mlxClient) var mlxClient
                guard let info = option.mlxModelInfo else { return }
                try await mlxClient.deleteModel(info)
            }
        )
    }
}

extension DownloadClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            isModelDownloaded: { _ in false },
            downloadModel: { _, _ in },
            pauseDownload: {},
            cancelDownload: {},
            modelDirectoryURL: { _ in nil },
            deleteModel: { _ in }
        )
    }
}

public extension DependencyValues {
    var downloadClient: DownloadClient {
        get { self[DownloadClient.self] }
        set { self[DownloadClient.self] = newValue }
    }
}

private func speedText(from status: String) -> String? {
    guard let openingParen = status.lastIndex(of: "("), let closingParen = status.lastIndex(of: ")") else {
        return nil
    }
    guard openingParen < closingParen else { return nil }
    let candidate = status[status.index(after: openingParen)..<closingParen]
    let speed = String(candidate)
    return speed.hasSuffix("/s") ? speed : nil
}

private extension DownloadClientFailure {
    init(_ error: any Error) {
        if let failure = error as? DownloadClientFailure {
            self = failure
            return
        }

        if let mlxFailure = error as? MLXDownloadError {
            switch mlxFailure {
            case .paused:
                self = .paused
            case .cancelled:
                self = .cancelled
            case .aria2BinaryMissing:
                self = .aria2BinaryMissing
            case let .failed(message):
                self = .failed(message)
            }
            return
        }

        self = .failed(error.localizedDescription)
    }
}

private extension ModelOption {
    var mlxModelInfo: MLXModelInfo? {
        guard requiresDownload else { return nil }
        let descriptor = descriptor
        return MLXModelInfo(
            id: descriptor.id,
            repoId: descriptor.repoID,
            name: descriptor.name,
            summary: descriptor.summary,
            size: descriptor.size,
            quantization: descriptor.quantization,
            parameters: descriptor.parameters,
            backend: mlxBackend,
            recommended: descriptor.recommended
        )
    }

    var mlxBackend: MLXModelBackend {
        switch self {
        case .appleSpeech:
            // Apple Speech is handled outside MLX download/runtime paths.
            return .fluidAudio
        case .mini3b, .mini3b8bit:
            return .voxtral
        case .qwen3ASR06B4bit, .parakeetTDT06BV3:
            return .fluidAudio
        case .whisperLargeV3Turbo, .whisperTiny:
            return .whisperKit
        }
    }
}
