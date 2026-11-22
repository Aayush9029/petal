import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private let appInfo: AboutAppInfo
    var updatesModel: CheckForUpdatesModel?

    init(updatesModel: CheckForUpdatesModel? = nil) {
        appInfo = AboutAppInfo()
        self.updatesModel = updatesModel
    }

    var body: some View {
        VStack {
            Spacer()

            logoSection

            infoSection

            updateButton

            linksSection

            Spacer()
        }
        .frame(width: 280, height: 500 - 28)
        .background {
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }

    private var logoSection: some View {
        VStack(spacing: 2) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                    .padding()
            }

            Text("Petal")
                .font(.title.bold())

            Text("Version \(appInfo.version), \(appInfo.buildYear)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom)
    }

    private var infoSection: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing) {
                AboutInfoRow(label: "Build", value: appInfo.build)
                AboutInfoRow(label: "Github", value: "Aayush9029") {
                    openURL(URL(string: "https://github.com/Aayush9029")!)
                }
                AboutInfoRow(label: "Designed By", value: "Aayush") {
                    openURL(URL(string: "https://aayush.art")!)
                }
                AboutInfoRow(label: "Last Update", value: appInfo.lastUpdateChecked)
                AboutInfoRow(label: "Made in", value: "Toronto, CA")
            }
            .font(.subheadline)
            Spacer()
        }
    }

    private var updateButton: some View {
        Button("Check for Updates...") {
            updatesModel?.checkForUpdates()
        }
        .buttonStyle(.bordered)
        .disabled(!(updatesModel?.canCheckForUpdates ?? false))
        .padding()
    }

    private var linksSection: some View {
        VStack(spacing: 2) {
            Button("aayush.art") {
                openURL(URL(string: "https://aayush.art")!)
            }
            .underline()
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text("Copyright \u{00A9} Aayush Pokharel, \(appInfo.buildYear)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 56)
    }
}

private struct AboutInfoRow: View {
    let label: String
    let value: String
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(label)
            HStack {
                if let action {
                    Text(value)
                        .onTapGesture(perform: action)
                } else {
                    Text(value)
                }
                Spacer()
            }
            .foregroundStyle(.secondary)
            .frame(width: 80)
        }
    }
}

private struct AboutAppInfo {
    let version: String
    let build: String
    let buildYear: String
    let lastUpdateChecked: String

    init() {
        let bundle = Bundle.main
        version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        buildYear = Calendar.current.component(.year, from: Date()).description

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        lastUpdateChecked = formatter.string(from: Date())
    }
}
