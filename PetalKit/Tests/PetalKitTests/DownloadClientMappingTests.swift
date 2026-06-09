import CustomDump
import Dependencies
import Foundation
import Shared
import Testing
@testable import DownloadClient
@testable import MLXClient

@Test
func downloadClientNormalizesProgressAndExtractsSpeedText() async throws {
    let updates = ProgressRecorder()

    try await withDependencies {
        $0.mlxClient.downloadModel = { _, progress in
            progress(1.4, "Downloading model files... 52% (18.2 MB/s)")
            progress(-0.3, "Downloading model files... 0%")
        }
    } operation: {
        try await DownloadClient.liveValue.downloadModel(.defaultOption) { update in
            updates.record(update)
        }
    }

    let snapshot = updates.snapshot()
    expectNoDifference(
        snapshot,
        [
            DownloadProgress(
                fractionCompleted: 1,
                status: "Downloading model files... 52% (18.2 MB/s)",
                speedText: "18.2 MB/s"
            ),
            DownloadProgress(
                fractionCompleted: 0,
                status: "Downloading model files... 0%",
                speedText: nil
            ),
        ]
    )
}

@Test
func downloadClientMapsMLXDownloadErrorsToTypedFailures() async {
    await assertMappedFailure(from: .paused, expected: .paused)
    await assertMappedFailure(from: .cancelled, expected: .cancelled)
    await assertMappedFailure(from: .aria2BinaryMissing, expected: .aria2BinaryMissing)
    await assertMappedFailure(from: .failed("network down"), expected: .failed("network down"))
}

@Test
func downloadClientMapsUnexpectedErrorsToFailedCase() async {
    struct FixtureError: LocalizedError {
        var errorDescription: String? { "fixture failure" }
    }

    do {
        try await withDependencies {
            $0.mlxClient.downloadModel = { _, _ in
                throw FixtureError()
            }
        } operation: {
            try await DownloadClient.liveValue.downloadModel(.defaultOption) { _ in }
        }
        Issue.record("Expected a failure but download succeeded.")
    } catch let error as DownloadClientFailure {
        switch error {
        case let .failed(message):
            #expect(message == "fixture failure")
        default:
            Issue.record("Expected .failed for unknown errors, got \(error.localizedDescription).")
        }
    } catch {
        Issue.record("Expected DownloadClientFailure, got \(error.localizedDescription).")
    }
}

@Test
func downloadClientSkipsMLXForNoDownloadModels() async throws {
    let updates = ProgressRecorder()
    let callRecorder = CallRecorder()

    try await withDependencies {
        $0.mlxClient.downloadModel = { _, _ in
            await callRecorder.recordCall()
        }
    } operation: {
        try await DownloadClient.liveValue.downloadModel(.appleSpeech) { update in
            updates.record(update)
        }
    }

    let snapshot = updates.snapshot()
    #expect(await callRecorder.callCount() == 0)
    expectNoDifference(
        snapshot,
        [
            DownloadProgress(
                fractionCompleted: 1,
                status: "No download required for this model.",
                speedText: nil
            )
        ]
    )
}

@Test
func noDownloadModelIsAlwaysReportedAsDownloaded() {
    let downloaded = withDependencies {
        $0.mlxClient.isModelDownloaded = { _ in false }
    } operation: {
        DownloadClient.liveValue.isModelDownloaded(.appleSpeech)
    }

    #expect(downloaded)
}

private func assertMappedFailure(from source: MLXDownloadError, expected: DownloadClientFailure) async {
    do {
        try await withDependencies {
            $0.mlxClient.downloadModel = { _, _ in
                throw source
            }
        } operation: {
            try await DownloadClient.liveValue.downloadModel(.defaultOption) { _ in }
        }
        Issue.record("Expected \(expected.localizedDescription), but download succeeded.")
    } catch let error as DownloadClientFailure {
        #expect(error == expected)
    } catch {
        Issue.record("Expected DownloadClientFailure, got \(error.localizedDescription).")
    }
}

private actor CallRecorder {
    private var calls = 0

    func recordCall() {
        calls += 1
    }

    func callCount() -> Int {
        calls
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [DownloadProgress] = []

    func record(_ value: DownloadProgress) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [DownloadProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
