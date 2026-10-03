import Foundation

struct CloudRuntimeContext: Sendable {
    var now: @Sendable () -> Date
    var timeZone: TimeZone
    var locale: Locale
    var appName: @Sendable () async -> String?
    var windowTitle: @Sendable () async -> String?
    var userName: @Sendable () -> String
    var clipboardText: @Sendable () async -> String?
    var selectedText: @Sendable () async -> String?
    var screenshot: @Sendable () async -> Data?

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        appName: @escaping @Sendable () async -> String? = { nil },
        windowTitle: @escaping @Sendable () async -> String? = { nil },
        userName: @escaping @Sendable () -> String = { "" },
        clipboardText: @escaping @Sendable () async -> String? = { nil },
        selectedText: @escaping @Sendable () async -> String? = { nil },
        screenshot: @escaping @Sendable () async -> Data? = { nil }
    ) {
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
        self.appName = appName
        self.windowTitle = windowTitle
        self.userName = userName
        self.clipboardText = clipboardText
        self.selectedText = selectedText
        self.screenshot = screenshot
    }
}
