/// The app that receives a dictation. `website` is the host of the front tab when that app is a browser.
public struct FocusedApp: Codable, Hashable, Sendable {
    public var app: MacApp
    public var website: String?

    public init(app: MacApp, website: String? = nil) {
        self.app = app
        self.website = website
    }
}
