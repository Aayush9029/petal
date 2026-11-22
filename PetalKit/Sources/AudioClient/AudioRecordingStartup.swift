import Shared

enum PreparedCaptureStartFailure: Error {
    case unavailable
}

enum AudioRecordingStartup {
    static func start(
        streaming: Bool,
        attempt: (AudioSampleProducer?) throws -> Void
    ) throws -> AudioSampleStream? {
        func run() throws -> AudioSampleStream? {
            let producer = streaming ? AudioSampleProducer() : nil
            do {
                try attempt(producer)
                return producer?.stream
            } catch {
                producer?.finish(throwing: error)
                throw error
            }
        }

        do {
            return try run()
        } catch is PreparedCaptureStartFailure {
            return try run()
        }
    }
}
