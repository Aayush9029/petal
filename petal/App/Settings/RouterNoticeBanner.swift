import SwiftUI

struct RouterNoticeBanner: View {
    let notice: RouterNotice
    let onOpenIntelligence: () -> Void

    var body: some View {
        SettingsPanel {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                SettingsActionButton(title: buttonTitle, action: onOpenIntelligence)
            }
            .padding(14)
        }
    }

    private var message: String {
        switch notice {
        case .cleanupOff: "Text cleanup is off, so Petal pastes every dictation as you said it."
        case .petalW1: "Petal W1 uses its own style. Routes set to As Said still skip cleanup."
        case .smartTranscription: "Smart transcription applies its own instructions, so routes do not run."
        }
    }

    private var buttonTitle: String {
        notice == .cleanupOff ? "Turn On" : "Change"
    }
}

#Preview {
    VStack {
        RouterNoticeBanner(notice: .cleanupOff) {}
        RouterNoticeBanner(notice: .petalW1) {}
        RouterNoticeBanner(notice: .smartTranscription) {}
    }
    .frame(width: 470)
    .padding()
}
