import SwiftUI

private struct Shimmer: ViewModifier {
    @State private var isInitialState = true
    @Environment(\.layoutDirection) private var layoutDirection
    private let min: CGFloat = -0.3
    private let max: CGFloat = 1.3

    var startPoint: UnitPoint {
        if layoutDirection == .rightToLeft {
            isInitialState ? UnitPoint(x: max, y: min) : UnitPoint(x: 0, y: 1)
        } else {
            isInitialState ? UnitPoint(x: min, y: min) : UnitPoint(x: 1, y: 1)
        }
    }

    var endPoint: UnitPoint {
        if layoutDirection == .rightToLeft {
            isInitialState ? UnitPoint(x: 1, y: 0) : UnitPoint(x: min, y: max)
        } else {
            isInitialState ? UnitPoint(x: 0, y: 0) : UnitPoint(x: max, y: max)
        }
    }

    func body(content: Content) -> some View {
        content
            .mask {
                LinearGradient(
                    colors: [.black.opacity(0.3), .black, .black.opacity(0.3)],
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            }
            .animation(.linear(duration: 1.5).delay(0.25).repeatForever(autoreverses: false), value: isInitialState)
            .onAppear {
                DispatchQueue.main.async { isInitialState = false }
            }
    }
}

public extension View {
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

#Preview {
    Text("Shimmering")
        .shimmering()
}
