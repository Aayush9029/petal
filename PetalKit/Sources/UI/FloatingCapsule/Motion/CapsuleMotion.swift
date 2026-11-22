import Observation

// Multiple observation handlers can update the same timeline in a single frame.
@MainActor
@Observable
final class CapsuleMotion {
    var timeline = CapsuleTimeline()
    var isSettled = true
    var level = CapsuleSpring(0, omega: 4)
}
