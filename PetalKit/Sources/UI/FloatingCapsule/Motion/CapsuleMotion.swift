import Observation

/// Holds the capsule timeline by reference. Several change handlers can run in
/// one update; each one mutates this shared timeline in place, so no handler
/// can write back an older copy and drop another handler's event.
@MainActor
@Observable
final class CapsuleMotion {
    var timeline = CapsuleTimeline()
    var isSettled = true
    /// The microphone level, smoothed so the highlight sways instead of flickering.
    var level = CapsuleSpring(0, omega: 4)
}
