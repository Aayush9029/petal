import Testing
@testable import Shared
@testable import UI
@testable import AudioClient
@testable import PermissionsClient
@testable import PasteClient
@testable import KeyboardClient
@testable import FloatingCapsuleClient
@testable import AudioTrimClient
@testable import AudioSpeedClient
@testable import TranscriptionClient

@Test
func modulesCompile() {
    _ = ModelOption.defaultOption
    _ = TranscriptionMode.verbatim
    _ = DoubleTapModifierKey.fn
    _ = FloatingCapsuleView.self
    _ = AudioClient.self
    _ = PermissionsClient.self
    _ = PasteClient.self
    _ = KeyboardClient.self
    _ = FloatingCapsuleClient.self
    _ = AudioTrimClient.self
    _ = AudioSpeedClient.self
    _ = TranscriptionClient.self
}
