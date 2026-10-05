import SwiftUI

public extension Gradient {
    static let intelligence = Gradient(stops: [
        Gradient.Stop(color: Color(red: 1, green: 0.67, blue: 0.31), location: 0.00),
        Gradient.Stop(color: Color(red: 1, green: 0.44, blue: 0.11), location: 0.15),
        Gradient.Stop(color: Color(red: 1, green: 0.34, blue: 0.29), location: 0.30),
        Gradient.Stop(color: Color(red: 0.98, green: 0.15, blue: 0.48), location: 0.45),
        Gradient.Stop(color: Color(red: 0.84, green: 0.29, blue: 0.82), location: 0.60),
        Gradient.Stop(color: Color(red: 0.63, green: 0.52, blue: 0.9), location: 0.75),
        Gradient.Stop(color: Color(red: 0.27, green: 0.71, blue: 1), location: 0.90),
        Gradient.Stop(color: Color(red: 0.27, green: 0.94, blue: 1), location: 1.00),
    ])
}

struct IntelligenceGradient: View {
    init() {}

    static let gradient = LinearGradient(gradient: .intelligence, startPoint: .leading, endPoint: .trailing)

    var body: some View {
        Rectangle()
            .fill(Self.gradient)
    }
}

struct IntelligenceGradientModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .opacity(0.01)
            .overlay(
                IntelligenceGradient()
                    .mask(content)
            )
    }
}

public extension View {
    func intelligenceGradient() -> some View {
        modifier(IntelligenceGradientModifier())
    }
}

// MARK: - Animated Progress Bar

public struct AnimatedIntelligenceBar: View {
    let progress: Double

    @State private var pulse = false

    public init(progress: Double) {
        self.progress = progress
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)

                Capsule()
                    .fill(IntelligenceGradient.gradient)
                    .frame(width: geo.size.width * min(progress, 1.0))
                    .blur(radius: 5)
                    .opacity(pulse ? 0.6 : 0.4)
                    .scaleEffect(pulse ? 1.02 : 1.0)

                Capsule()
                    .fill(IntelligenceGradient.gradient)
                    .frame(width: geo.size.width * min(progress, 1.0))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview("Static Gradient") {
    VStack(spacing: 20) {
        IntelligenceGradient()
            .frame(height: 8)
            .clipShape(.capsule)

        Text("Intelligence")
            .font(.largeTitle.bold())
            .intelligenceGradient()
    }
    .padding()
}

#Preview("Animated Bar") {
    VStack(spacing: 20) {
        AnimatedIntelligenceBar(progress: 0.6)
            .frame(height: 8)

        AnimatedIntelligenceBar(progress: 0.3)
            .frame(height: 8)

        AnimatedIntelligenceBar(progress: 0.9)
            .frame(height: 8)
    }
    .padding()
    .frame(width: 300)
}
