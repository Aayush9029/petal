import Foundation
import Testing
@testable import PermissionsClient

@Suite("Accessibility guide application")
struct AccessibilityGuideApplicationTests {
    @Test("Finds the launched app bundle from its executable")
    func findsApplicationBundleURL() async {
        let bundleURL = await AccessibilityGuideApplication.applicationBundleURL(
            executableURL: URL(filePath: "/tmp/Build/Products/Debug/petal.app/Contents/MacOS/petal"),
            fallbackURL: URL(filePath: "/tmp/fallback")
        )

        #expect(bundleURL.path == "/tmp/Build/Products/Debug/petal.app")
    }

    @Test("Falls back when the executable is not inside an app bundle")
    func fallsBackOutsideApplicationBundle() async {
        let fallbackURL = URL(filePath: "/tmp/PetalTests.xctest")
        let bundleURL = await AccessibilityGuideApplication.applicationBundleURL(
            executableURL: URL(filePath: "/tmp/PetalTests.xctest/Contents/MacOS/PetalTests"),
            fallbackURL: fallbackURL
        )

        #expect(bundleURL.path == fallbackURL.path)
    }
}
