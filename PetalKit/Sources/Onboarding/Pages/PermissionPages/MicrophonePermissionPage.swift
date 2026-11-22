import Assets
import SwiftUI
import UI

struct MicrophonePermissionPage: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        PermissionPage(
            title: "Microphone Access",
            subtitle: "To record and transcribe your voice, Petal needs microphone access.",
            icon: .microphone,
            isAuthorized: model.microphoneAuthorized
        )
    }
}

#Preview("Microphone - Pending") {
    OnboardingView(model: .makePreview(page: .microphone) { model in
        model.microphonePermissionState = .notDetermined
    })
}

#Preview("Microphone - Enabled") {
    OnboardingView(model: .makePreview(page: .microphone))
}
