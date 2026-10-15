import Foundation

/// A single snapshot of the route requested for a recording.
struct AudioCaptureConfiguration: Sendable {
    let inputDeviceID: String
    let defaultInputUID: String?
    let streaming: Bool

    var usesSystemDefault: Bool { inputDeviceID == AudioInputDevice.systemDefaultID }

    func canReuse(
        for requested: Self,
        captureDeviceID: String?,
        captureDeviceIsConnected: Bool = true
    ) -> Bool {
        guard inputDeviceID == requested.inputDeviceID, streaming == requested.streaming else { return false }
        if usesSystemDefault {
            guard let defaultInputUID, defaultInputUID == requested.defaultInputUID else { return false }
        }
        if let captureDeviceID {
            return captureDeviceIsConnected && (usesSystemDefault || captureDeviceID == inputDeviceID)
        }
        return usesSystemDefault && !streaming
    }
}
