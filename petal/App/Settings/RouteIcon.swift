import Shared
import SwiftUI

/// `nil` is the fallback route for every other app.
struct RouteIcon: View {
    let trigger: CleanupRoute.Trigger?
    var size: CGFloat = 26

    var body: some View {
        switch trigger {
        case let .app(app)?:
            Image(nsImage: MacAppIconCache.icon(for: app.bundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        case .website?:
            symbol("globe", fill: .teal)
        case nil:
            symbol("square.grid.2x2.fill", fill: .gray)
        }
    }

    private func symbol(_ name: String, fill: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size * 0.86, height: size * 0.86)
            .background(fill.gradient, in: .rect(cornerRadius: size * 0.24))
            .frame(width: size, height: size)
    }
}

#Preview {
    HStack {
        RouteIcon(trigger: .app(MacApp(bundleID: "com.apple.mail", name: "Mail")))
        RouteIcon(trigger: .website("github.com"))
        RouteIcon(trigger: nil)
    }
    .padding()
}
