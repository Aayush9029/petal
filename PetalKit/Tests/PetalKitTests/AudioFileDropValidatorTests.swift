import Foundation
import Shared
import Testing

@Suite("Audio file drop validation")
struct AudioFileDropValidatorTests {
    @Test
    func acceptsSingleSupportedAudioFile() {
        let url = URL(fileURLWithPath: "/tmp/message.m4a")

        #expect(AudioFileDropValidator.validate([url]) == .accepted(url))
    }

    @Test
    func rejectsMultipleFiles() {
        let first = URL(fileURLWithPath: "/tmp/one.wav")
        let second = URL(fileURLWithPath: "/tmp/two.wav")

        #expect(AudioFileDropValidator.validate([first, second]) == .rejected(.multipleFiles))
    }

    @Test
    func rejectsUnsupportedFiles() {
        let url = URL(fileURLWithPath: "/tmp/notes.txt")

        #expect(AudioFileDropValidator.validate([url]) == .rejected(.unsupportedFile))
    }
}
