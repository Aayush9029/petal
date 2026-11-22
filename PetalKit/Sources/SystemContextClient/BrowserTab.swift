import ApplicationServices
import Foundation

enum BrowserTab {
    static let bundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary",
        "company.thebrowser.Browser", "company.thebrowser.dia", "com.microsoft.edgemac", "com.brave.Browser",
        "org.mozilla.firefox", "com.kagi.kagimacOS", "com.vivaldi.Vivaldi", "app.zen-browser.zen", "com.operasoftware.Opera",
    ]

    private static let maxVisitedElements = 400

    static func host(processIdentifier: pid_t) -> String? {
        let app = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let window = app.element(for: kAXFocusedWindowAttribute) else { return nil }
        if let document = window.value(for: kAXDocumentAttribute) as? String, let host = host(from: document) {
            return host
        }
        return webAreaURL(in: window).flatMap { host(from: $0.absoluteString) }
    }

    private static func webAreaURL(in root: AXUIElement) -> URL? {
        var queue = [root]
        var visited = 0
        while !queue.isEmpty, visited < maxVisitedElements {
            let element = queue.removeFirst()
            visited += 1
            if element.value(for: kAXRoleAttribute) as? String == "AXWebArea" {
                return element.value(for: kAXURLAttribute) as? URL
            }
            queue += (element.value(for: kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        return nil
    }

    private static func host(from address: String) -> String? {
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme), let host = url.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
