import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenCapture {
    enum Failure: Error {
        case noDisplay
        case encodingFailed
    }

    static let maxPixelLength: CGFloat = 1568
    static let jpegQuality: CGFloat = 0.7

    static func frontmostDisplayJPEG() async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let frontmostID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        guard let display = display(in: content, frontmostID: frontmostID) else { throw Failure.noDisplay }
        let petal = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: petal, exceptingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration(for: filter))
        return try jpeg(image)
    }

    static func display(in content: SCShareableContent, frontmostID: pid_t?) -> SCDisplay? {
        let window = content.windows.first { $0.owningApplication?.processID == frontmostID && $0.windowLayer == 0 }
        if let window, let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) }) {
            return display
        }
        return content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
    }

    static func configuration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let scale = CGFloat(filter.pointPixelScale)
        let width = filter.contentRect.width * scale
        let height = filter.contentRect.height * scale
        let factor = min(1, maxPixelLength / max(width, height))
        let configuration = SCStreamConfiguration()
        configuration.width = Int((width * factor).rounded())
        configuration.height = Int((height * factor).rounded())
        return configuration
    }

    static func jpeg(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return data as Data
    }
}
