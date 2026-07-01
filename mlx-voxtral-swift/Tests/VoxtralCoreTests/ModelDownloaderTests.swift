import Foundation
import XCTest
@testable import VoxtralCore

final class ModelDownloaderTests: XCTestCase {
    func testVerifyShardedModelRejectsAria2Sidecars() throws {
        let modelDir = try makeModelFixture(
            weightMap: [
                "model.layers.0.weight": "model-00001-of-00002.safetensors",
                "model.layers.1.weight": "model-00002-of-00002.safetensors",
            ],
            files: [
                "model-00001-of-00002.safetensors",
                "model-00001-of-00002.safetensors.aria2",
                "model-00002-of-00002.safetensors",
            ]
        )
        defer { try? FileManager.default.removeItem(at: modelDir) }

        let verification = ModelDownloader.verifyShardedModel(at: modelDir)

        XCTAssertFalse(verification.complete)
        XCTAssertEqual(
            verification.missing,
            ["model-00001-of-00002.safetensors (incomplete aria2 download)"]
        )
    }

    func testVerifySingleFileModelRejectsAria2Sidecars() throws {
        let modelDir = try makeModelFixture(
            weightMap: nil,
            files: [
                "model.safetensors",
                "model.safetensors.aria2",
            ]
        )
        defer { try? FileManager.default.removeItem(at: modelDir) }

        let verification = ModelDownloader.verifyShardedModel(at: modelDir)

        XCTAssertFalse(verification.complete)
        XCTAssertEqual(
            verification.missing,
            ["model.safetensors (incomplete aria2 download)"]
        )
    }
}

private func makeModelFixture(
    weightMap: [String: String]?,
    files: [String]
) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    try "{}".write(to: tempDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

    if let weightMap {
        let index: [String: Any] = ["weight_map": weightMap]
        let data = try JSONSerialization.data(withJSONObject: index, options: [.prettyPrinted])
        try data.write(to: tempDir.appendingPathComponent("model.safetensors.index.json"))
    }

    for file in files {
        try Data([0x00]).write(to: tempDir.appendingPathComponent(file))
    }

    return tempDir
}
