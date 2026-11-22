import AudioClient
import CustomDump
import DependenciesTestSupport
import DownloadClient
import FloatingCapsuleClient
import Foundation
import HistoryClient
import LogClient
import PermissionsClient
import Shared
import SoundClient
import Synchronization
import SystemContextClient
import Testing
import TranscriptionClient
@testable import AppFeature

@MainActor
@Suite(.dependencies, .timeLimit(.minutes(1)))
struct AppFeatureRecordingTests {
    @Test
    func `releasing a held shortcut during the permission prompt still transcribes the intended model once`() async {
        let permission = AsyncGate()
        let now = Mutex(Date(timeIntervalSince1970: 0))
        let capturedModels = Mutex<[ModelOption]>([])
        let starts = Mutex(0)
        let capture = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let model = makeModel {
            $0.date = DateGenerator { now.withLock { $0 } }
            $0.continuousClock = ImmediateClock()
            $0.permissionsClient.requestMicrophonePermission = {
                await permission.wait()
                return true
            }
            $0.audioClient.startRecording = { _ in starts.withLock { $0 += 1 } }
            $0.audioClient.isRecording = { true }
            $0.audioClient.stopRecording = { capture }
            $0.systemContextClient.focusedApp = { nil }
            $0.transcriptionClient.audioDurationSeconds = { _ in 1 }
            $0.transcriptionClient.transcribe = { _, option, _ in
                capturedModels.withLock { $0.append(option) }
                return ""
            }
            $0.historyClient.persistArtifacts = { _ in nil }
            $0.historyClient.appendEntry = { $0.currentDays }
        }

        let pressing = Task { await model.pushToTalkKeyDown() }
        await permission.waitUntilWaiting()
        await model.handleDeepLink(.start)
        model.selectedModelID = ModelOption.whisperLargeV3Turbo.rawValue
        now.withLock { $0.addTimeInterval(2) }
        await model.pushToTalkKeyUp()
        await permission.open()
        await pressing.value

        #expect(starts.withLock { $0 } == 1)
        expectNoDifference(capturedModels.withLock { $0 }, [.defaultOption])
        expectNoDifference(model.selectedModelOption, .whisperLargeV3Turbo)
        expectNoDifference(model.sessionState, .idle)
    }

    @Test
    func `a late partial transcript from the previous recording cannot replace the active one`() async throws {
        typealias PartialTranscript = @Sendable (String) async -> Void
        let callbacks = AsyncStream<PartialTranscript>.makeStream()
        defer { callbacks.continuation.finish() }
        let displayed = Mutex<[String]>([])
        let model = makeModel {
            $0.transcriptionClient.transcribeStream = { _, _, update in
                callbacks.continuation.yield(update)
                return ""
            }
            $0.floatingCapsuleClient.updateLiveTranscript = { text in displayed.withLock { $0.append(text) } }
        }
        model.modelDownloadViewModel.$selectedModelID.withLock { $0 = ModelOption.parakeetUnified06B.rawValue }
        var iterator = callbacks.stream.makeAsyncIterator()
        await model.pushToTalkKeyDown()
        let previous = try #require(await iterator.next())
        await model.handleDeepLink(.stop)

        await model.pushToTalkKeyDown()
        let current = try #require(await iterator.next())
        await current("current words")
        await previous("stale words")

        expectNoDifference(displayed.withLock { $0 }, ["current words"])
        await model.handleDeepLink(.stop)
    }

    @Test
    func `a deep link timeout is visible while the audio device is still rolling back`() async {
        let clock = TestClock()
        let capture = AsyncGate()
        let rollback = AsyncGate()
        let starts = Mutex(0)
        let model = makeModel {
            $0.continuousClock = clock
            $0.transcriptionClient.prepareModelIfNeeded = { _ in }
            $0.audioClient.startRecording = { _ in
                let attempt = starts.withLock {
                    $0 += 1
                    return $0
                }
                if attempt == 1 { await capture.wait() }
            }
            $0.audioClient.cancelRecording = { await rollback.wait() }
        }

        let start = Task { await model.handleDeepLink(.start) }
        await capture.waitUntilWaiting()
        await clock.advance(by: .seconds(12))
        await rollback.waitUntilWaiting()
        expectNoDifference(model.sessionState, .error("Timed out after 12s waiting for audio capture to start."))
        await model.handleDeepLink(.start)
        #expect(starts.withLock { $0 } == 1)

        start.cancel()
        await capture.open()
        await rollback.open()
        await start.value
        expectNoDifference(model.sessionState, .idle)
    }

    private func makeModel(_ configure: (inout DependencyValues) -> Void) -> AppModel {
        withDependencies {
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.logClient.debug = { _, _ in }
            $0.soundClient.play = { _ in }
            $0.downloadClient.modelDirectoryURL = { _ in FileManager.default.temporaryDirectory }
            configure(&$0)
        } operation: {
            let model = AppModel()
            model.$hasCompletedSetup.withLock { $0 = true }
            return model
        }
    }
}
