import AppKit
import SwiftUI
import UI

public struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        OnboardingPageContainer(
            showBack: model.showBack,
            backAction: model.moveBack,
            primaryTitle: model.currentPrimaryTitle,
            primaryDisabled: model.primaryDisabled,
            primaryAction: model.primaryActionTapped,
            primaryActionDelay: model.currentPage.primaryActionDelay
        ) {
            Group {
                switch model.currentPage {
                case .welcome:
                    WelcomePage()
                        .xSpacing(.center)

                case .model:
                    ModelSelectionPage(model: model)
                        

                case .shortcut:
                    ShortcutPage(model: model)

                case .microphone:
                    MicrophonePermissionPage(model: model)

                case .accessibility:
                    AccessibilityPermissionPage(model: model)

                case .cleanup:
                    CleanupPage(model: model)

                case .historyRetention:
                    HistoryRetentionPage(model: model)
                        .xSpacing(.topLeading)

                case .download:
                    DownloadPage(model: model)
                        .xSpacing(.topLeading)
                }
            }
            .transition(.scale)
            .animation(.easeIn, value: model.currentPage)
        }
        .frame(width: 820, height: 512)
        .onChange(of: model.selectedModelID) { _, _ in
            model.selectedModelChanged()
        }
        .onAppear {
            model.windowAppeared()
            DispatchQueue.main.async {
                ensureOnboardingWindowsAreVisible()
            }
        }
    }

    private func ensureOnboardingWindowsAreVisible() {
        let onboardingTitles = Set(["Petal Onboarding", "Petal Settings"])

        for window in NSApp.windows where onboardingTitles.contains(window.title) {
            guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
                window.center()
                continue
            }

            var origin = window.frame.origin
            let maxX = screenFrame.maxX - window.frame.width
            let maxY = screenFrame.maxY - window.frame.height

            if origin.x < screenFrame.minX || origin.x > maxX || origin.y < screenFrame.minY || origin.y > maxY {
                origin = NSPoint(
                    x: screenFrame.midX - (window.frame.width / 2),
                    y: screenFrame.midY - (window.frame.height / 2)
                )
                window.setFrameOrigin(origin)
            }
        }
    }
}

// MARK: - Previews

#Preview("Welcome") {
    OnboardingView(model: .makePreview(page: .welcome))
}

#Preview("Model Selection") {
    OnboardingView(model: .makePreview(page: .model))
}

#Preview("Shortcut") {
    OnboardingView(model: .makePreview(page: .shortcut))
}

#Preview("Microphone") {
    OnboardingView(model: .makePreview(page: .microphone))
}

#Preview("Accessibility") {
    OnboardingView(model: .makePreview(page: .accessibility))
}

#Preview("Cleanup") {
    OnboardingView(model: .makePreview(page: .cleanup))
}

#Preview("History Retention") {
    OnboardingView(model: .makePreview(page: .historyRetention))
}

#Preview("Download") {
    OnboardingView(model: .makePreview(page: .download))
}
