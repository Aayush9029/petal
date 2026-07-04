import Foundation

/// High-level visual state of the menu bar icon, derived from the app's session
/// state. Drives which pixel animation (if any) the status item renders.
enum MenuBarIconState: Equatable {
    /// Static pixel-petal glyph.
    case idle
    /// Audio-reactive pixel pulse; `level` is the smoothed input level 0...1.
    case recording
    /// Marching pixel spinner shared by all processing stages + model downloads.
    case working
    /// Static pixel exclamation.
    case error

    /// Whether this state needs a per-frame animation timer.
    var isAnimated: Bool {
        switch self {
        case .recording, .working: return true
        case .idle, .error: return false
        }
    }
}
