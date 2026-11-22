import AppFeature
import Foundation
import Testing

@Test(arguments: [
    ("petal://start", PetalDeepLinkCommand.start),
    ("petal://stop", .stop),
    ("petal://toggle", .toggle),
    ("petal://setup", .setup),
    ("petal://settings", .settings),
    ("petal://check-for-updates", .checkForUpdates),
    ("PETAL:///CHECK_FOR_UPDATES", .checkForUpdates),
])
func opensPetalCommand(url: String, command: PetalDeepLinkCommand) throws {
    #expect(PetalDeepLinkCommand.parse(try #require(URL(string: url))) == command)
}

@Test(arguments: ["https://start", "petal://unknown"])
func ignoresUnrecognizedCommand(url: String) throws {
    #expect(PetalDeepLinkCommand.parse(try #require(URL(string: url))) == nil)
}
