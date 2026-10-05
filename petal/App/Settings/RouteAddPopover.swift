import Shared
import SwiftUI

/// Picks the app or website for a new route. Typing filters open apps; an address offers a website route.
struct RouteAddPopover: View {
    let query: String
    let apps: [MacApp]
    let website: String?
    let onQueryChange: (String) -> Void
    let onApp: (MacApp) -> Void
    let onWebsite: () -> Void
    let onSubmit: () -> Void
    let onChooseApplication: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(12)

            if let website {
                websiteRow(website)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }

            Divider()

            appGrid
                .frame(maxHeight: 236)

            Divider()

            PopoverRowButton(title: "Choose from Applications…", symbol: "folder", action: onChooseApplication)
                .padding(6)
        }
        .frame(width: 328)
        .onAppear { isSearchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search apps or type a website", text: Binding(get: { query }, set: onQueryChange))
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private func websiteRow(_ domain: String) -> some View {
        Button(action: onWebsite) {
            HStack(spacing: 10) {
                RouteIcon(trigger: .website(domain), size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(domain)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("Any browser tab on this website")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                KeyCapsLabel(keys: ["↩"])
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 9))
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var appGrid: some View {
        if apps.isEmpty {
            Text(query.isEmpty ? "Every open app already has a route." : "No open app matches. Type an address, like github.com.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 20)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Open Apps")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                        ForEach(apps) { app in
                            RouteAddAppTile(app: app) { onApp(app) }
                        }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.automatic)
        }
    }
}

#Preview {
    RouteAddPopover(
        query: "github.com",
        apps: [
            MacApp(bundleID: "com.apple.mail", name: "Mail"),
            MacApp(bundleID: "com.apple.Terminal", name: "Terminal"),
            MacApp(bundleID: "com.apple.Safari", name: "Safari"),
            MacApp(bundleID: "com.apple.Notes", name: "Notes"),
            MacApp(bundleID: "com.apple.MobileSMS", name: "Messages"),
        ],
        website: "github.com",
        onQueryChange: { _ in },
        onApp: { _ in },
        onWebsite: {},
        onSubmit: {},
        onChooseApplication: {}
    )
}
