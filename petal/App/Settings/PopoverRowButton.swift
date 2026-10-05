import SwiftUI

struct PopoverRowButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.primary.opacity(isHovering ? 0.07 : 0), in: .rect(cornerRadius: 7))
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    PopoverRowButton(title: "Choose from Applications…", symbol: "folder") {}
        .frame(width: 300)
        .padding()
}
