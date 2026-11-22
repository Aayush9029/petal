import SwiftUI
import UI

struct WelcomePage: View {
    @State private var isAnimating = false
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 24) {
            Image.appIcon
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .shadow(radius: 12)
                .font(.system(size: 74))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .slideIn(active: isAnimating, delay: 0.25)

            VStack(spacing: 10) {
                Text("Welcome to Petal")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Your voice, transcribed privately on your Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .slideIn(active: isAnimating, delay: 0.5)
        }
        .onAppear {
            isAnimating = true
        }
        .task { await model.welcomeAppeared() }
    }
}

#Preview("Welcome") {
    OnboardingView(model: .makePreview(page: .welcome))
}
