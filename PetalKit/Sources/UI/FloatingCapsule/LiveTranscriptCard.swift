import SwiftUI

struct LiveTranscriptCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live transcription")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .lineLimit(3)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 384, height: 112, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live transcription")
        .accessibilityValue(text)
    }
}
