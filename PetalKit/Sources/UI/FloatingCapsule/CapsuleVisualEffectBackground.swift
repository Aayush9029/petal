import AppKit
import SwiftUI

/// An `NSVisualEffectView`-backed translucent background for the floating
/// capsule, used as the Liquid Glass fallback on macOS < 26. Matches the
/// `.hudWindow` / `.behindWindow` material used elsewhere for floating chrome.
struct CapsuleVisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
