// swift-tools-version: 6.4

import PackageDescription

extension Target.Dependency {
    static let assets: Self = "Assets"
    static let shared: Self = "Shared"
    static let ui: Self = "UI"
    static let modelDownloadFeature: Self = "ModelDownloadFeature"
    static let mlxClient: Self = "MLXClient"
    static let permissionsClient: Self = "PermissionsClient"
    static let downloadClient: Self = "DownloadClient"
    static let historyClient: Self = "HistoryClient"
    static let windowClient: Self = "WindowClient"
    static let foundationModelClient: Self = "FoundationModelClient"
    static let soundClient: Self = "SoundClient"
    static let doubleTapClient: Self = "DoubleTapClient"
    static let logClient: Self = "LogClient"
    static let playbackDuckingClient: Self = "PlaybackDuckingClient"
    static let localCleanupClient: Self = "LocalCleanupClient"
    static let keychainClient: Self = "KeychainClient"
    static let cloudCleanupClient: Self = "CloudCleanupClient"
    static let systemContextClient: Self = "SystemContextClient"
    static let applicationsClient: Self = "ApplicationsClient"
    static let cloudCleanupFeature: Self = "CloudCleanupFeature"

    static let dependencies: Self = .product(name: "Dependencies", package: "swift-dependencies")
    static let dependenciesMacros: Self = .product(name: "DependenciesMacros", package: "swift-dependencies")
    static let dependenciesTestSupport: Self = .product(name: "DependenciesTestSupport", package: "swift-dependencies")
    static let customDump: Self = .product(name: "CustomDump", package: "swift-custom-dump")
    static let sharing: Self = .product(name: "Sharing", package: "swift-sharing")
    static let identifiedCollections: Self = .product(name: "IdentifiedCollections", package: "swift-identified-collections")
    static let tagged: Self = .product(name: "Tagged", package: "swift-tagged")
    static let debugSnapshots: Self = .product(name: "DebugSnapshots", package: "swift-debug-snapshots")
    static let casePaths: Self = .product(name: "CasePaths", package: "swift-case-paths")
    static let keyboardShortcuts: Self = .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
    static let sauce: Self = .product(name: "Sauce", package: "Sauce")
    static let fluidAudio: Self = .product(name: "FluidAudio", package: "FluidAudio")
    static let voxtralCore: Self = .product(name: "VoxtralCore", package: "MLXVoxtralSwift")
    static let mlxAudioCore: Self = .product(name: "MLXAudioCore", package: "mlx-audio-swift")
    static let mlxAudioSTT: Self = .product(name: "MLXAudioSTT", package: "mlx-audio-swift")
    static let whisperKit: Self = .product(name: "WhisperKit", package: "argmax-oss-swift")
    static let mlx: Self = .product(name: "MLX", package: "mlx-swift")
    static let mlxLLM: Self = .product(name: "MLXLLM", package: "mlx-swift-lm")
    static let mlxLMCommon: Self = .product(name: "MLXLMCommon", package: "mlx-swift-lm")
    static let tokenizers: Self = .product(name: "Tokenizers", package: "swift-transformers")
}

let package = Package(
    name: "PetalKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "Assets", targets: ["Assets"]),
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "ModelDownloadFeature", targets: ["ModelDownloadFeature"]),
        .library(name: "Onboarding", targets: ["Onboarding"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "AudioClient", targets: ["AudioClient"]),
        .library(name: "PermissionsClient", targets: ["PermissionsClient"]),
        .library(name: "PasteClient", targets: ["PasteClient"]),
        .library(name: "KeyboardClient", targets: ["KeyboardClient"]),
        .library(name: "FloatingCapsuleClient", targets: ["FloatingCapsuleClient"]),
        .library(name: "MLXClient", targets: ["MLXClient"]),
        .library(name: "TranscriptionClient", targets: ["TranscriptionClient"]),
        .library(name: "DownloadClient", targets: ["DownloadClient"]),
        .library(name: "HistoryClient", targets: ["HistoryClient"]),
        .library(name: "SoundClient", targets: ["SoundClient"]),
        .library(name: "LogClient", targets: ["LogClient"]),
        .library(name: "PlaybackDuckingClient", targets: ["PlaybackDuckingClient"]),
        .library(name: "WindowClient", targets: ["WindowClient"]),
        .library(name: "DoubleTapClient", targets: ["DoubleTapClient"]),
        .library(name: "FoundationModelClient", targets: ["FoundationModelClient"]),
        .library(name: "LocalCleanupClient", targets: ["LocalCleanupClient"]),
        .library(name: "KeychainClient", targets: ["KeychainClient"]),
        .library(name: "CloudCleanupClient", targets: ["CloudCleanupClient"]),
        .library(name: "SystemContextClient", targets: ["SystemContextClient"]),
        .library(name: "CloudCleanupFeature", targets: ["CloudCleanupFeature"]),
        .library(name: "ApplicationsClient", targets: ["ApplicationsClient"]),
        .library(name: "RouterFeature", targets: ["RouterFeature"]),
        .library(name: "PetalCLI", targets: ["PetalCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.4"),
        .package(name: "MLXVoxtralSwift", path: "../mlx-voxtral-swift"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.2"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.7.3"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.10.1"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-debug-snapshots", from: "0.5.3"),
        .package(name: "KeyboardShortcuts", path: "KeyboardShortcuts"),
        .package(url: "https://github.com/Clipy/Sauce.git", from: "2.5.2"),
        .package(url: "https://github.com/Neywa-Labs/mlx-audio-swift.git", from: "0.2.1"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.1.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.33.0")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.33.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.4.0"),
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
                .tagged,
                .keyboardShortcuts,
                .casePaths,
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
                .localCleanupClient,
            ]
        ),
        .target(
            name: "CloudCleanupFeature",
            dependencies: [
                .shared,
                .keychainClient,
                .cloudCleanupClient,
                .permissionsClient,
                .debugSnapshots,
            ]
        ),
        .target(
            name: "RouterFeature",
            dependencies: [
                .shared,
                .applicationsClient,
                .cloudCleanupClient,
                .cloudCleanupFeature,
                .foundationModelClient,
                .debugSnapshots,
            ]
        ),
        .target(
            name: "AppFeature",
            dependencies: [
                .shared, .ui, .modelDownloadFeature, .permissionsClient, .historyClient,
                .windowClient, .foundationModelClient, .soundClient, .doubleTapClient,
                .logClient, .playbackDuckingClient, .localCleanupClient, .cloudCleanupClient,
                .systemContextClient, .cloudCleanupFeature, .keyboardShortcuts,
                "Onboarding", "RouterFeature", "AudioClient", "PasteClient", "KeyboardClient",
                "FloatingCapsuleClient", "TranscriptionClient",
            ]
        ),
        .target(
            name: "Onboarding",
            dependencies: [
                .assets,
                .shared,
                .ui,
                .modelDownloadFeature,
                .permissionsClient,
                .foundationModelClient,
                .keyboardShortcuts,
                .soundClient,
            ]
        ),

        .target(
            name: "AudioClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "PermissionsClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
            ]
        ),
        .target(
            name: "PasteClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .sauce,
            ]
        ),
        .target(
            name: "KeyboardClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
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
                .downloadClient,
                .mlx,
                .mlxAudioCore,
                .mlxAudioSTT,
                .fluidAudio,
                .whisperKit,
            ]
        ),
        .target(
            name: "FoundationModelClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
            ]
        ),
        .target(
            name: "LocalCleanupClient",
            dependencies: [
                .shared,
                .logClient,
                .downloadClient,
                .voxtralCore,
                .mlx,
                .mlxLLM,
                .mlxLMCommon,
                .tokenizers,
            ]
        ),
        .target(
            name: "KeychainClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .tagged,
            ]
        ),
        .target(
            name: "CloudCleanupClient",
            dependencies: [
                .shared,
                .systemContextClient,
            ]
        ),
        .target(
            name: "SystemContextClient",
            dependencies: [
                .shared,
                .logClient,
            ]
        ),
        .target(
            name: "ApplicationsClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "TranscriptionClient",
            dependencies: [
                .shared,
                .logClient,
                .mlxClient,
            ]
        ),
        .target(
            name: "DownloadClient",
            dependencies: [
                .shared,
                .fluidAudio,
                .voxtralCore,
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
                .dependencies,
                .dependenciesMacros,
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
            ]
        ),
        .target(
            name: "PetalCLI",
            dependencies: [
                .dependencies,
                .sharing,
                .shared,
                .downloadClient,
                "TranscriptionClient",
            ]
        ),
        .testTarget(
            name: "PetalKitTests",
            dependencies: [
                .dependenciesTestSupport,
                .customDump,
                .shared,
                .ui,
                .modelDownloadFeature,
                .permissionsClient,
                "AudioClient",
                "PasteClient",
                "KeyboardClient",
                "FloatingCapsuleClient",
                "MLXClient",
                "TranscriptionClient",
                "LocalCleanupClient",
                "KeychainClient",
                "CloudCleanupClient",
                "CloudCleanupFeature",
                "ApplicationsClient",
                "RouterFeature",
                "DownloadClient",
                "HistoryClient",
                "LogClient",
                "PlaybackDuckingClient",
                "PetalCLI",
                "AppFeature",
            ]
        ),
    ]
)
