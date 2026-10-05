import RouterFeature
import Shared

struct RouterFlowNode: Identifiable, Equatable {
    let id: RouterModel.Selection
    /// `nil` for the fallback node.
    let trigger: CleanupRoute.Trigger?
    let style: RouterModel.Style
}
