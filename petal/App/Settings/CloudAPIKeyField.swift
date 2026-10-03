import CloudCleanupFeature
import Shared
import SwiftUI

struct CloudAPIKeyField: View {
    let provider: CloudProvider
    @Binding var apiKey: String
    let verification: CloudCleanupModel.Verification
    let hasSavedKey: Bool
    let isUnsaved: Bool
    let onVerify: () -> Void
    let onRemove: () -> Void
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(provider.requiresAPIKey ? "API Key" : "API Key (Optional)")
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                status
            }

            HStack(spacing: 8) {
                SettingsTextField(placeholder: provider.apiKeyPlaceholder, text: $apiKey, isSecure: !isRevealed, trailingInset: 28)
                    .overlay(alignment: .trailing) {
                        Button(isRevealed ? "Hide Key" : "Show Key", systemImage: isRevealed ? "eye.slash" : "eye") {
                            isRevealed.toggle()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 9)
                    }
                    .onSubmit(onVerify)

                if verification.is(\.verifying) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 58)
                } else if hasSavedKey && !isUnsaved {
                    SettingsActionButton(title: "Remove", tint: .red, action: onRemove)
                } else {
                    SettingsActionButton(title: "Verify", action: onVerify)
                        .disabled(!canVerify)
                        .opacity(canVerify ? 1 : 0.45)
                }
            }

            footer
        }
        .padding(16)
        .animation(.easeOut(duration: 0.15), value: verification)
    }

    private var canVerify: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !provider.requiresAPIKey
    }

    @ViewBuilder
    private var status: some View {
        switch verification {
        case .failed:
            Label("Not Verified", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .idle where isUnsaved:
            Label("Not Saved", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .idle, .verifying, .verified:
            EmptyView()
        }
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            if case let .failed(message) = verification {
                Text(message)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !hasSavedKey, let url = provider.apiKeyURL {
                Text("Petal sends your text only to \(provider.displayName). [Get a key](\(url.absoluteString))")
                    .foregroundStyle(.secondary)
            } else if !hasSavedKey {
                Text("Verify to load the models on your server.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    @Previewable @State var key = "sk-proj-1234"
    VStack(spacing: 0) {
        CloudAPIKeyField(provider: .openAI, apiKey: $key, verification: .verified, hasSavedKey: true, isUnsaved: false, onVerify: {}, onRemove: {})
        CloudAPIKeyField(provider: .anthropic, apiKey: .constant(""), verification: .idle, hasSavedKey: false, isUnsaved: false, onVerify: {}, onRemove: {})
        CloudAPIKeyField(
            provider: .openRouter,
            apiKey: $key,
            verification: .failed("Incorrect API key provided. (HTTP 401)"),
            hasSavedKey: false,
            isUnsaved: true,
            onVerify: {},
            onRemove: {}
        )
    }
    .labelStyle(.titleAndIcon)
    .font(.caption)
    .frame(width: 500)
}
