import AppKit

extension WindowConfig {
    public static let about = WindowConfig(
        id: "PetalAboutWindow",
        title: "About Petal",
        style: .chromeless(.init(
            hidesCloseButton: false,
            hidesMiniaturizeButton: true,
            hidesZoomButton: true,
            isFloating: true
        )),
        size: CGSize(width: 280, height: 500)
    )

    public static let settings = WindowConfig(
        id: "PetalSettingsWindow",
        title: "Petal Settings",
        style: .titled(.init(
            showsCloseButton: true,
            toolbarStyle: .unified
        )),
        size: CGSize(width: 920, height: 720)
    )

    public static let onboarding = WindowConfig(
        id: "PetalOnboardingWindow",
        title: "Petal Onboarding",
        style: .chromeless(.init(
            hidesCloseButton: true,
            hidesMiniaturizeButton: true,
            hidesZoomButton: true,
            isFloating: false,
            visualEffect: VisualEffectConfig(material: .hudWindow, blendingMode: .behindWindow)
        )),
        size: CGSize(width: 820, height: 512),
        animationBehavior: .utilityWindow
    )

    public static let miniDownload = WindowConfig(
        id: "PetalMiniDownloadWindow",
        title: "Downloading",
        style: .chromeless(.init(
            hidesCloseButton: true,
            hidesMiniaturizeButton: true,
            hidesZoomButton: true,
            isFloating: true,
            visualEffect: VisualEffectConfig(material: .hudWindow, blendingMode: .behindWindow)
        )),
        size: CGSize(width: 120, height: 120),
        animationBehavior: .utilityWindow,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]
    )
}
