import Testing
@testable import PetalCLI
@testable import Shared

@Suite
struct PetalCLIParsingTests {
    @Test
    func appLaunchArgumentsDoNotStartTheCLI() {
        #expect(!CLICommand.isInvocation([]))
        #expect(!CLICommand.isInvocation(["-NSDocumentRevisionsDebugMode", "YES"]))
        #expect(CLICommand.isInvocation(["transcribe", "a.wav"]))
        #expect(CLICommand.isInvocation(["--version"]))
    }

    @Test
    func transcribeParsesFlagsInAnyOrder() throws {
        let command = try CLICommand.parse(["transcribe", "-o", "out.txt", "memo.m4a", "--model=whisper-large-v3-turbo", "--json"])
        #expect(command == .transcribe(TranscribeOptions(
            input: .file("memo.m4a"),
            modelID: "whisper-large-v3-turbo",
            outputPath: "out.txt",
            json: true
        )))
    }

    @Test
    func dashReadsStandardInputAndDoubleDashEndsOptions() throws {
        #expect(try CLICommand.parse(["transcribe", "-"]) == .transcribe(TranscribeOptions(input: .standardInput)))
        #expect(try CLICommand.parse(["transcribe", "--", "-odd.wav"]) == .transcribe(TranscribeOptions(input: .file("-odd.wav"))))
    }

    @Test
    func transcribeRejectsBadUsage() {
        #expect(throws: CLIUsageError.self) { try CLICommand.parse(["transcribe"]) }
        #expect(throws: CLIUsageError.self) { try CLICommand.parse(["transcribe", "a.wav", "b.wav"]) }
        #expect(throws: CLIUsageError.self) { try CLICommand.parse(["transcribe", "a.wav", "--model"]) }
        #expect(throws: CLIUsageError.self) { try CLICommand.parse(["transcribe", "a.wav", "--fast"]) }
        #expect(throws: CLIUsageError.self) { try CLICommand.parse(["models", "--all"]) }
    }
}

@Suite
struct PetalCLIModelResolutionTests {
    let available: [ModelOption] = [.parakeetTDTCTC110M, .qwen3ASR17B8bit, .whisperLargeV3Turbo]

    @Test
    func readyFileModelWinsOverDictationModel() throws {
        let model = try ModelResolution.resolve(
            requestedID: nil,
            selectedModelID: ModelOption.parakeetTDTCTC110M.rawValue,
            fileTranscriptionModelID: ModelOption.whisperLargeV3Turbo.rawValue,
            available: available,
            isDownloaded: { _ in true }
        )
        #expect(model == .whisperLargeV3Turbo)
    }

    @Test
    func missingFileModelFallsBackToDictationModel() throws {
        let model = try ModelResolution.resolve(
            requestedID: nil,
            selectedModelID: ModelOption.qwen3ASR17B8bit.rawValue,
            fileTranscriptionModelID: ModelOption.whisperLargeV3Turbo.rawValue,
            available: available,
            isDownloaded: { $0 == .qwen3ASR17B8bit }
        )
        #expect(model == .qwen3ASR17B8bit)
    }

    @Test
    func requestedModelMustExistAndBeDownloaded() {
        #expect(throws: ModelResolutionError.self) {
            try ModelResolution.resolve(
                requestedID: "nope", selectedModelID: "", fileTranscriptionModelID: "",
                available: available, isDownloaded: { _ in true }
            )
        }
        #expect(throws: ModelResolutionError.notDownloaded(.whisperLargeV3Turbo)) {
            try ModelResolution.resolve(
                requestedID: ModelOption.whisperLargeV3Turbo.rawValue, selectedModelID: "", fileTranscriptionModelID: "",
                available: available, isDownloaded: { _ in false }
            )
        }
    }
}
