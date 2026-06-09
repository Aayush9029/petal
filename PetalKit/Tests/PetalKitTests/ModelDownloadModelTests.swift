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
        $0.downloadClient.isModelDownloaded = { _ in false }
        $0.downloadClient.downloadModel = { _, progress in
            progress(DownloadProgress(fractionCompleted: 0.4, status: "Downloading model files... 40%", speedText: "12.0 MB/s"))
            progress(DownloadProgress(fractionCompleted: 0.9, status: "Downloading model files... 90%", speedText: "11.0 MB/s"))
        }
    } operation: { @MainActor in
        let model = ModelDownloadModel(isPreviewMode: true)
        await model.downloadButtonTapped()

        expectNoDifference(model.state, .downloaded)
        expectNoDifference(model.lastError, nil)
    }
}

@Test
func modelHandlesPauseAndResumeAcrossRetries() async {
    let attempts = AttemptCounter()

    await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in false }
        $0.downloadClient.downloadModel = { _, progress in
            let attempt = await attempts.next()
            if attempt == 1 {
                throw DownloadClientFailure.paused
            }
            progress(DownloadProgress(fractionCompleted: 0.75, status: "Downloading model files... 75%", speedText: "9.0 MB/s"))
        }
    } operation: { @MainActor in
        let model = ModelDownloadModel(isPreviewMode: true)

        await model.downloadButtonTapped()
        #expect(model.state.is(\.paused))

        await model.resumeButtonTapped()
        expectNoDifference(model.state, .downloaded)
        #expect(await attempts.current() == 2)
    }
}

@Test
func modelPauseAndCancelButtonsMutateStateDeterministically() async {
    await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in false }
    } operation: {
        await MainActor.run {
            let model = ModelDownloadModel(isPreviewMode: true)
            model.state = .downloading(.init(fraction: 0.58, statusText: "Downloading model files..."))

            expectDifference(model.state) {
                model.pauseButtonTapped()
            } changes: {
                $0 = .paused(.init(fraction: 0.58, statusText: "Downloading model files..."))
            }

            expectDifference(model.state) {
                model.cancelButtonTapped()
            } changes: {
                $0 = .notDownloaded
            }
        }
    }
}

@Test
func modelTransitionsToFailedStateForTypedFailures() async {
    await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in false }
        $0.downloadClient.downloadModel = { _, _ in
            throw DownloadClientFailure.failed("network failure")
        }
    } operation: { @MainActor in
        let model = ModelDownloadModel(isPreviewMode: true)
        await model.downloadButtonTapped()

        expectNoDifference(model.state, .failed("network failure"))
        expectNoDifference(model.lastError, "network failure")
        #expect(!model.state.isActive)
    }
}

@Test
func selectedModelChangedRefreshesDownloadedState() async {
    await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in true }
    } operation: {
        await MainActor.run {
            let model = ModelDownloadModel(isPreviewMode: true)
            model.selectedModelChanged()

            expectNoDifference(model.state, .downloaded)
        }
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
