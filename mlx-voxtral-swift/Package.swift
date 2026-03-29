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
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.2"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
        .package(name: "mlx-swift-lm", path: "../mlx-swift-lm-local")
    ],
    targets: [
        .target(
            name: "VoxtralCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "Transformers", package: "swift-transformers"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm")
            ]
        ),
        .testTarget(
            name: "VoxtralCoreTests",
            dependencies: ["VoxtralCore"]
        )
    ]
)
