// swift-tools-version: 6.2

import PackageDescription

extension Target.Dependency {
    static let assets: Self = "Assets"
    static let shared: Self = "Shared"
    static let models: Self = "PetalModels"
    static let ui: Self = "UI"
    static let modelDownloadFeature: Self = "ModelDownloadFeature"
    static let mlxClient: Self = "MLXClient"
    static let audioTrimClient: Self = "AudioTrimClient"
    static let audioSpeedClient: Self = "AudioSpeedClient"
    static let permissionsClient: Self = "PermissionsClient"
    static let downloadClient: Self = "DownloadClient"
    static let historyClient: Self = "HistoryClient"
    static let windowClient: Self = "WindowClient"
    static let foundationModelClient: Self = "FoundationModelClient"
    static let soundClient: Self = "SoundClient"
    static let doubleTapClient: Self = "DoubleTapClient"
    static let logClient: Self = "LogClient"
    static let playbackDuckingClient: Self = "PlaybackDuckingClient"

    static let dependencies: Self = .product(name: "Dependencies", package: "swift-dependencies")
    static let dependenciesMacros: Self = .product(name: "DependenciesMacros", package: "swift-dependencies")
    static let dependenciesTestSupport: Self = .product(name: "DependenciesTestSupport", package: "swift-dependencies")
    static let customDump: Self = .product(name: "CustomDump", package: "swift-custom-dump")
    static let sharing: Self = .product(name: "Sharing", package: "swift-sharing")
    static let identifiedCollections: Self = .product(name: "IdentifiedCollections", package: "swift-identified-collections")
    static let casePaths: Self = .product(name: "CasePaths", package: "swift-case-paths")
    static let keyboardShortcuts: Self = .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
    static let sauce: Self = .product(name: "Sauce", package: "Sauce")
    static let fluidAudio: Self = .product(name: "FluidAudio", package: "FluidAudio")
    static let voxtralCore: Self = .product(name: "VoxtralCore", package: "MLXVoxtralSwift")
    static let mlxAudioCore: Self = .product(name: "MLXAudioCore", package: "mlx-audio-swift")
    static let mlxAudioSTT: Self = .product(name: "MLXAudioSTT", package: "mlx-audio-swift")
    static let whisperKit: Self = .product(name: "WhisperKit", package: "argmax-oss-swift")
    static let onnxRuntime: Self = .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")
}

let package = Package(
    name: "PetalKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "Assets", targets: ["Assets"]),
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "PetalModels", targets: ["PetalModels"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "ModelDownloadFeature", targets: ["ModelDownloadFeature"]),
        .library(name: "Onboarding", targets: ["Onboarding"]),
        .library(name: "AudioClient", targets: ["AudioClient"]),
        .library(name: "PermissionsClient", targets: ["PermissionsClient"]),
        .library(name: "PasteClient", targets: ["PasteClient"]),
        .library(name: "KeyboardClient", targets: ["KeyboardClient"]),
        .library(name: "FloatingCapsuleClient", targets: ["FloatingCapsuleClient"]),
        .library(name: "MLXClient", targets: ["MLXClient"]),
        .library(name: "AudioTrimClient", targets: ["AudioTrimClient"]),
        .library(name: "AudioSpeedClient", targets: ["AudioSpeedClient"]),
        .library(name: "TranscriptionClient", targets: ["TranscriptionClient"]),
        .library(name: "DownloadClient", targets: ["DownloadClient"]),
        .library(name: "HistoryClient", targets: ["HistoryClient"]),
        .library(name: "SoundClient", targets: ["SoundClient"]),
        .library(name: "LogClient", targets: ["LogClient"]),
        .library(name: "PlaybackDuckingClient", targets: ["PlaybackDuckingClient"]),
        .library(name: "WindowClient", targets: ["WindowClient"]),
        .library(name: "DoubleTapClient", targets: ["DoubleTapClient"]),
        .library(name: "FoundationModelClient", targets: ["FoundationModelClient"]),
    ],
    dependencies: [
        // altic-dev's FluidAudio fork (pinned to an exact revision) for Granite/Cohere CoreML ASR,
        // the extra Parakeet variants (TDT v2, TDT-CTC 110M), and RNN-T decoder output caching.
        .package(url: "https://github.com/altic-dev/FluidAudio.git", revision: "72625bbccf9f6c797a540a1f1cb66a4cb60753eb"),
        .package(name: "MLXVoxtralSwift", path: "../mlx-voxtral-swift"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.14.1"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.6.1"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.9.1"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.8.0"),
        .package(name: "KeyboardShortcuts", path: "KeyboardShortcuts"),
        .package(url: "https://github.com/Clipy/Sauce.git", from: "2.5.1"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.1.3"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.0.0"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.24.2"),
    ],
    targets: [
        .target(
            name: "Assets",
            resources: [.process("Resources")]
        ),
        .target(
            name: "Shared",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .sharing,
                .identifiedCollections,
                .keyboardShortcuts,
                .casePaths,
            ]
        ),
        .target(
            name: "PetalModels",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "UI",
            dependencies: [
                .assets,
                .shared,
            ]
        ),
        .target(
            name: "ModelDownloadFeature",
            dependencies: [
                .shared,
                .downloadClient,
            ]
        ),
        .target(
            name: "Onboarding",
            dependencies: [
                .assets,
                .shared,
                .models,
                .ui,
                .modelDownloadFeature,
                .permissionsClient,
                .foundationModelClient,
                .keyboardShortcuts,
                .sauce,
                .soundClient,
            ]
        ),

        // MARK: - Clients

        .target(
            name: "AudioClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "PermissionsClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "PasteClient",
            dependencies: [
                .shared,
                .sauce,
            ]
        ),
        .target(
            name: "KeyboardClient",
            dependencies: [
                .shared,
                .sauce,
            ]
        ),
        .target(
            name: "FloatingCapsuleClient",
            dependencies: [
                .shared,
                .ui,
            ]
        ),
        .target(
            name: "MLXClient",
            dependencies: [
                .shared,
                .logClient,
                .voxtralCore,
                .mlxAudioCore,
                .mlxAudioSTT,
                .fluidAudio,
                .whisperKit,
                .onnxRuntime,
            ]
        ),
        .target(
            name: "AudioTrimClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "AudioSpeedClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "FoundationModelClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "TranscriptionClient",
            dependencies: [
                .shared,
                .logClient,
                .audioTrimClient,
                .audioSpeedClient,
                .mlxClient,
            ]
        ),
        .target(
            name: "DownloadClient",
            dependencies: [
                .shared,
                .mlxClient,
            ]
        ),
        .target(
            name: "HistoryClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "SoundClient",
            dependencies: [
                .assets,
                .shared,
            ]
        ),
        .target(
            name: "LogClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "PlaybackDuckingClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
            ]
        ),
        .target(
            name: "DoubleTapClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "WindowClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .casePaths,
            ]
        ),
        .testTarget(
            name: "PetalKitTests",
            dependencies: [
                .dependenciesTestSupport,
                .customDump,
                .shared,
                .models,
                .ui,
                .modelDownloadFeature,
                .permissionsClient,
                "Onboarding",
                "AudioClient",
                "PasteClient",
                "KeyboardClient",
                "FloatingCapsuleClient",
                "AudioTrimClient",
                "AudioSpeedClient",
                "MLXClient",
                "TranscriptionClient",
                "FoundationModelClient",
                "DownloadClient",
                "HistoryClient",
                "SoundClient",
                "LogClient",
                "PlaybackDuckingClient",
                "DoubleTapClient",
            ]
        ),
    ]
)
