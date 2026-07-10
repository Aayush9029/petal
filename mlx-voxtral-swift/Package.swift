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
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
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
