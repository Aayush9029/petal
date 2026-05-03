import Foundation
import UniformTypeIdentifiers

public enum AudioFileDropValidationResult: Equatable, Sendable {
    case accepted(URL)
    case rejected(AudioFileDropValidationError)
}

public enum AudioFileDropValidationError: Equatable, Sendable {
    case noFile
    case multipleFiles
    case unsupportedFile
    case directory
}

public enum AudioFileDropValidator {
    private static let supportedExtensions: Set<String> = [
        "aac",
        "aif",
        "aiff",
        "caf",
        "flac",
        "m4a",
        "mp3",
        "mp4",
        "wav",
    ]

    public static func validate(_ urls: [URL]) -> AudioFileDropValidationResult {
        guard !urls.isEmpty else { return .rejected(.noFile) }
        guard urls.count == 1 else { return .rejected(.multipleFiles) }

        let url = urls[0]
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return .rejected(.directory)
        }

        let pathExtension = url.pathExtension.lowercased()
        guard supportedExtensions.contains(pathExtension) || conformsToAudioType(pathExtension) else {
            return .rejected(.unsupportedFile)
        }

        return .accepted(url)
    }

    private static func conformsToAudioType(_ pathExtension: String) -> Bool {
        guard let type = UTType(filenameExtension: pathExtension) else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .mpeg4Audio)
    }
}
