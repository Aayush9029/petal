import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Shared
import Testing
@testable import DownloadClient
@testable import ModelDownloadFeature

@Test
func modelCompletesDownloadAndTransitionsToDownloadedState() async {
    await withDependencies {
        $0.downloadClient.downloadModel = { _, progress in
            progress(.init(fraction: 0.4, statusText: "Downloading model files... 40%", speedText: "12.0 MB/s"))
            progress(.init(fraction: 0.9, statusText: "Downloading model files... 90%", speedText: "11.0 MB/s"))
        }
    } operation: { @MainActor in
        let model = ModelDownloadModel()
        model.$selectedModelID.withLock { $0 = ModelOption.defaultOption.rawValue }
        await model.downloadButtonTapped()

        expectNoDifference(model.state, .downloaded)
        expectNoDifference(model.lastError, nil)
    }
}

@Test
func modelHandlesPauseAndResumeAcrossRetries() async {
    let attempts = AttemptCounter()

    await withDependencies {
        $0.downloadClient.downloadModel = { _, progress in
            let attempt = await attempts.next()
            if attempt == 1 {
                throw DownloadClientFailure.paused
            }
            progress(.init(fraction: 0.75, statusText: "Downloading model files... 75%", speedText: "9.0 MB/s"))
        }
    } operation: { @MainActor in
        let model = ModelDownloadModel()

        await model.downloadButtonTapped()
        #expect(model.state.is(\.paused))

        await model.resumeButtonTapped()
        expectNoDifference(model.state, .downloaded)
        #expect(await attempts.current() == 2)
    }
}

@Test
func lateProgressAndCompletionFromACancelledDownloadCannotReplaceItsRetry() async {
    let first = AsyncGate()
    let retry = AsyncGate()
    let attempts = AttemptCounter()

    await withDependencies {
        $0.downloadClient.modelDirectoryURL = { _ in nil }
        $0.downloadClient.cancelDownload = {}
        $0.downloadClient.downloadModel = { _, progress in
            if await attempts.next() == 1 {
                await first.wait()
                progress(.init(fraction: 0.8, statusText: "Old transfer"))
                throw DownloadClientFailure.cancelled
            }
            await retry.wait()
        }
    } operation: { @MainActor in
        let model = ModelDownloadModel()
        model.$selectedModelID.withLock { $0 = ModelOption.defaultOption.rawValue }
        var completions: [ModelOption] = []
        model.onDownloadCompleted = { completions.append($0) }
        let cancelled = Task { await model.downloadModel(.parakeetUnified06B) }
        await first.waitUntilWaiting()
        model.cancelButtonTapped()
        let replacement = Task { await model.downloadModel(.nemotronUnified06B) }
        await retry.waitUntilWaiting()

        await first.open()
        await cancelled.value
        expectNoDifference(model.state, .preparing)
        #expect(model.downloadingModelOption == .nemotronUnified06B)

        await retry.open()
        await replacement.value
        expectNoDifference(completions, [.nemotronUnified06B])
        expectNoDifference(model.state, .notDownloaded)
    }
}

@Test
func modelTransitionsToFailedStateForTypedFailures() async {
    await withDependencies {
        $0.downloadClient.downloadModel = { _, _ in
            throw DownloadClientFailure.failed("network failure")
        }
    } operation: { @MainActor in
        let model = ModelDownloadModel()
        model.$selectedModelID.withLock { $0 = ModelOption.defaultOption.rawValue }
        await model.downloadButtonTapped()

        expectNoDifference(model.state, .failed("network failure"))
        expectNoDifference(model.lastError, "network failure")
        #expect(!model.state.isActive)
    }
}

@Test
func selectedModelChangedRefreshesDownloadedState() async {
    await withDependencies {
        $0.downloadClient.modelDirectoryURL = { _ in URL.temporaryDirectory }
    } operation: {
        await MainActor.run {
            let model = ModelDownloadModel()
            model.selectedModelChanged()

            expectNoDifference(model.state, .downloaded)
        }
    }
}

@Test
func deletingModelMarksOptionUnavailableUntilDeletionFinishes() async {
    let gate = AsyncGate()

    await withDependencies {
        $0.downloadClient.modelDirectoryURL = { _ in URL.temporaryDirectory }
        $0.downloadClient.deleteModel = { _ in
            await gate.wait()
        }
    } operation: { @MainActor in
        let model = ModelDownloadModel()
        model.$selectedModelID.withLock { $0 = ModelOption.whisperLargeV3Turbo.rawValue }
        model.state = .downloaded

        let deleteTask = Task {
            await model.deleteModel(.whisperLargeV3Turbo)
        }

        await gate.waitUntilWaiting()
        #expect(model.isDeletingModel(.whisperLargeV3Turbo))
        #expect(!model.isModelDownloaded(.whisperLargeV3Turbo))
        expectNoDifference(model.state, .notDownloaded)

        await gate.open()
        await deleteTask.value

        #expect(!model.isDeletingModel(.whisperLargeV3Turbo))
        expectNoDifference(model.lastError, nil)
    }
}

private actor AttemptCounter {
    private var value = 0

    func next() -> Int {
        value += 1
        return value
    }

    func current() -> Int {
        value
    }
}
