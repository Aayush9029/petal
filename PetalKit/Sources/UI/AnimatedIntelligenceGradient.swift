import SwiftUI

struct AnimatedIntelligenceGradientModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(0.01)
            .overlay {
                GeometryReader { geometry in
                    IntelligenceGradient()
                        .frame(width: geometry.size.width * 2.5)
                        .offset(x: -geometry.size.width * 1.5 * phase)
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
    }
}

public extension View {
    /// Fills the view's shape with the Apple Intelligence gradient and slowly sweeps it.
    func animatedIntelligenceGradient() -> some View {
        modifier(AnimatedIntelligenceGradientModifier())
    }
}

#Preview {
    Text("I'm going to be late. There's a cute dog outside.")
        .font(.title3)
        .animatedIntelligenceGradient()
        .padding()
        .frame(width: 420)
        .background(.black)
}
