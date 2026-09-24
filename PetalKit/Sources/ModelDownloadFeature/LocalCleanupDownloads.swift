import Observation
import Shared

/// One download model per on-device cleanup model, shared by onboarding and Settings.
@MainActor
@Observable
public final class LocalCleanupDownloads {
    public let s1Mini = LocalCleanupDownloadModel(model: .s1Mini)
    public let petalW1 = LocalCleanupDownloadModel(model: .petalW1)

    public init() {}

    public subscript(model: CleanupModel) -> LocalCleanupDownloadModel? {
        switch model {
        case .s1Mini: s1Mini
        case .petalW1: petalW1
        case .off, .appleIntelligence: nil
        }
    }

    public var isAnyActive: Bool {
        s1Mini.state.isActive || petalW1.state.isActive
    }

    public func task() {
        s1Mini.task()
        petalW1.task()
    }
}
