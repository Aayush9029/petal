import ApplicationServices
import Foundation

/// Reads the front tab's address through Accessibility, which Petal already has for pasting.
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
        guard let window = element(app, kAXFocusedWindowAttribute) else { return nil }
        if let document = value(window, kAXDocumentAttribute) as? String, let host = host(from: document) {
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
            if value(element, kAXRoleAttribute) as? String == "AXWebArea" {
                return value(element, kAXURLAttribute) as? URL
            }
            queue += (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        return nil
    }

    private static func host(from address: String) -> String? {
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme), let host = url.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
