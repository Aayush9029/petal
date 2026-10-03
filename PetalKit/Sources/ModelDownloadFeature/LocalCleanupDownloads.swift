import Observation
import Shared

/// One download model per on-device cleanup model, shared by onboarding and Settings.
@MainActor
@Observable
public final class LocalCleanupDownloads {
    public let petalW1 = LocalCleanupDownloadModel(model: .petalW1)

    public init() {}

    public subscript(model: CleanupModel) -> LocalCleanupDownloadModel? {
        switch model {
        case .petalW1: petalW1
        case .off, .appleIntelligence, .cloud: nil
        }
    }

    public var isAnyActive: Bool {
        petalW1.state.isActive
    }

    public func task() {
        petalW1.task()
    }
}
