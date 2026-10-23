import Observation

/// Holds the capsule timeline by reference. Several change handlers can run in
/// one update; each one mutates this shared timeline in place, so no handler
/// can write back an older copy and drop another handler's event.
@MainActor
@Observable
final class CapsuleMotion {
    var timeline = CapsuleTimeline()
    var isSettled = true
}
