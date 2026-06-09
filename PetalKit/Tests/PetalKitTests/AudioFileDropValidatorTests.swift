import CustomDump
import Foundation
import Shared
import Testing

@Suite("Audio file drop validation")
struct AudioFileDropValidatorTests {
    @Test
    func acceptsSingleSupportedAudioFile() {
        let url = URL(fileURLWithPath: "/tmp/message.m4a")

        expectNoDifference(AudioFileDropValidator.validate([url]), .accepted(url))
    }

    @Test
    func rejectsMultipleFiles() {
        let first = URL(fileURLWithPath: "/tmp/one.wav")
        let second = URL(fileURLWithPath: "/tmp/two.wav")

        let result = AudioFileDropValidator.validate([first, second])
        expectNoDifference(result.rejected, .multipleFiles)
    }

    @Test
    func rejectsUnsupportedFiles() {
        let url = URL(fileURLWithPath: "/tmp/notes.txt")

        let result = AudioFileDropValidator.validate([url])
        expectNoDifference(result.rejected, .unsupportedFile)
    }
}
