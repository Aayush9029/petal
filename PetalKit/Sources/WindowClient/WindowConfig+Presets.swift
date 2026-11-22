import AppKit

extension WindowConfig {
    public static let about = WindowConfig(
        id: "PetalAboutWindow",
        title: "About Petal",
        style: .chromeless(showsCloseButton: true, floating: true, usesHUD: false),
        size: CGSize(width: 280, height: 500)
    )

    public static let settings = WindowConfig(
        id: "PetalSettingsWindow",
        title: "Petal Settings",
        style: .titled(minimumHeight: 540),
        size: CGSize(width: 749, height: 680)
    )

    public static let onboarding = WindowConfig(
        id: "PetalOnboardingWindow",
        title: "Petal Onboarding",
        style: .chromeless(showsCloseButton: false, floating: false, usesHUD: true),
        size: CGSize(width: 820, height: 512),
        animationBehavior: .utilityWindow
    )

    public static let miniDownload = WindowConfig(
        id: "PetalMiniDownloadWindow",
        title: "Downloading",
        style: .chromeless(showsCloseButton: false, floating: true, usesHUD: true),
        size: CGSize(width: 120, height: 120),
        animationBehavior: .utilityWindow,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]
    )
}
