// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MLXVoxtralSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VoxtralCore",
            targets: ["VoxtralCore"]
        )
    ],
    dependencies: [
        // Both stay on the versions that PetalKit resolves.
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.33.0")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "6e3fe5d5648826c4e979b55df422462cc8e88a9b"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.4"),
    ],
    targets: [
        .target(
            name: "VoxtralCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),

                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers")
            ]
        ),
        .testTarget(
            name: "VoxtralCoreTests",
            dependencies: ["VoxtralCore"]
        )
    ]
)
