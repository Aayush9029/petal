import RouterFeature
import Shared

struct RouterFlowNode: Identifiable, Equatable {
    let id: RouterModel.Selection
    let trigger: CleanupRoute.Trigger?
    let style: RouterModel.Style
}
