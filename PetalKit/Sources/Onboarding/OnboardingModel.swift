import Dependencies
import Foundation
import FoundationModelClient
import KeyboardShortcuts
import ModelDownloadFeature
import Observation
import PermissionsClient
import Shared
import SoundClient

@MainActor
@Observable
public final class OnboardingModel {
    public enum Page: Int, CaseIterable, Sendable {
        case welcome
        case model
        case shortcut
        case microphone
        case accessibility
        case cleanup
        case historyRetention
        case download
    }

    public var currentPage: Page {
        didSet {
            lastPageTransitionDate = now
            lastError = nil
        }
    }

    public var pageOrder: [Page] {
        var pages: [Page] = [
            .welcome,
            .shortcut,
            .microphone,
            .accessibility,
            .historyRetention,
            .model,
        ]
        if shouldShowCleanupPage {
            pages.append(.cleanup)
        }
        if selectedModelOption?.requiresDownload ?? true {
            pages.append(.download)
        }
        return pages
    }

    public var nextPage: Page? {
        guard let currentIndex = pageOrder.firstIndex(of: currentPage),
              pageOrder.indices.contains(currentIndex + 1)
        else { return nil }
        return pageOrder[currentIndex + 1]
    }

    public var previousPage: Page? {
        guard let currentIndex = pageOrder.firstIndex(of: currentPage),
              pageOrder.indices.contains(currentIndex - 1)
        else { return nil }
        return pageOrder[currentIndex - 1]
    }

    public func moveBack() {
        guard let previousPage else { return }
        currentPage = previousPage
    }

    public var showBack: Bool {
        guard previousPage != nil else { return false }
        if currentPage == .download {
            let downloadState = modelDownloadViewModel.state
            if downloadState.isActive || downloadState.isPaused { return false }
        }
        if currentPage == .cleanup, cleanupDownload.state.isActive { return false }
        return true
    }

    public var currentPrimaryTitle: String {
        switch currentPage {
        case .model:
            if selectedModelOption != nil && nextPage == nil {
                return "Finish Setup"
            }
            return currentPage.primaryTitle
        case .accessibility:
            return accessibilityAuthorized ? "Continue" : "Enable Accessibility"
        case .microphone:
            return microphoneAuthorized ? "Continue" : "Enable Microphone"
        case .cleanup:
            if pendingCleanupDownload {
                return cleanupDownload.state.isActive ? "Downloading..." : "Download \(cleanupModel.displayName)"
            }
            return nextPage == nil ? "Finish Setup" : "Continue"
        case .download:
            if modelDownloadViewModel.state.isActive { return "Downloading..." }
            if modelDownloadViewModel.state.isDownloaded { return "Finish Setup" }
            return currentPage.primaryTitle
        default:
            return currentPage.primaryTitle
        }
    }

    public var primaryDisabled: Bool {
        switch currentPage {
        case .welcome, .historyRetention: false
        case .cleanup: cleanupDownload.state.isActive
        case .model: selectedModelOption == nil
        case .shortcut: !shortcut.isConfigured
        case .microphone: false
        case .accessibility: false
        case .download: modelDownloadViewModel.state.isActive
        }
    }

    public func primaryActionTapped() async {
        if let last = lastPageTransitionDate, now.timeIntervalSince(last) < 0.35 {
            return
        }

        guard !primaryDisabled else { return }
        switch currentPage {
        case .download where !modelDownloadViewModel.state.isDownloaded:
            await modelDownloadViewModel.downloadButtonTapped()
        case .microphone where !microphoneAuthorized:
            await microphonePermissionButtonTapped()
        case .accessibility where !accessibilityAuthorized:
            await ensureAccessibilityPermission()
        case .cleanup where pendingCleanupDownload:
            await cleanupDownload.downloadButtonTapped()
        default:
            if let nextPage {
                currentPage = nextPage
            } else {
                completeSetup()
            }
        }
    }

    public let modelDownloadViewModel: ModelDownloadModel
    public let cleanupDownload: LocalCleanupDownloadModel

    public var selectedModelID: String {
        get { modelDownloadViewModel.selectedModelID }
        set { modelDownloadViewModel.$selectedModelID.withLock { $0 = newValue } }
    }

    public var microphonePermissionState: MicrophonePermissionState = .notDetermined
    public var microphoneAuthorized: Bool { microphonePermissionState == .authorized }
    public var accessibilityAuthorized = false
    @ObservationIgnored @Shared(.historyRetentionMode) public var historyRetentionMode: HistoryRetentionMode
    @ObservationIgnored @Shared(.cleanupModel) public var cleanupModel: CleanupModel
    public var lastError: String?

    public var onCompleted: (@MainActor () -> Void)?
    public var onMinimize: (@MainActor () -> Void)?

    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.foundationModelClient) private var foundationModelClient
    @ObservationIgnored @Dependency(\.continuousClock) private var clock

    @ObservationIgnored @Shared(.hasCompletedSetup) private var hasCompletedSetup

    @ObservationIgnored @Dependency(\.soundClient) private var soundClient
    @ObservationIgnored @Dependency(\.recordingShortcut) private var recordingShortcut
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored private var lastPageTransitionDate: Date?
    @ObservationIgnored private let isPreviewMode: Bool

    public init(
        initialPage: Page = .welcome,
        downloadViewModel: ModelDownloadModel? = nil,
        cleanupDownload: LocalCleanupDownloadModel = LocalCleanupDownloadModel(),
        isPreviewMode: Bool = false
    ) {
        self.currentPage = initialPage
        self.isPreviewMode = isPreviewMode
        modelDownloadViewModel = downloadViewModel ?? ModelDownloadModel()
        self.cleanupDownload = cleanupDownload

        if isPreviewMode {
            $historyRetentionMode.withLock { $0 = .both }
            microphonePermissionState = .authorized
            accessibilityAuthorized = true
        }
    }

    public var selectedModelOption: ModelOption? {
        modelDownloadViewModel.selectedModelOption
    }

    private var shouldShowCleanupPage: Bool {
        guard let selectedModelOption else { return false }
        return selectedModelOption.provider != .voxtralCore
    }

    public var cleanupModels: [CleanupModel] {
        CleanupModel.allCases.filter { $0 != .cloud && ($0 != .appleIntelligence || foundationModelClient.isAvailable()) }
    }

    private var pendingCleanupDownload: Bool {
        cleanupModel.isLocal && !cleanupDownload.state.isDownloaded
    }

    public var shortcut: RecordedShortcut {
        get {
            access(keyPath: \.shortcut)
            return recordingShortcut.current()
        }
        set { withMutation(keyPath: \.shortcut) { recordingShortcut.record(newValue) } }
    }

    func welcomeAppeared() async {
        await soundClient.play(.welcome)
    }

    public func monitorPermissions() async {
        guard !isPreviewMode else { return }
        while !Task.isCancelled {
            await refreshPermissionStatus()
            do {
                try await clock.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    public func cleanupModelTapped(_ model: CleanupModel) {
        $cleanupModel.withLock { $0 = model }
    }

    public func selectedModelChanged() {
        modelDownloadViewModel.selectedModelChanged()
        lastError = nil
    }

    public func microphonePermissionButtonTapped() async {
        if isPreviewMode {
            microphonePermissionState = .authorized
            lastError = nil
            return
        }

        let granted = await permissionsClient.requestMicrophonePermission()
        await refreshPermissionStatus()

        if granted || microphoneAuthorized {
            lastError = nil
            return
        }

        if microphonePermissionState == .denied {
            await permissionsClient.openMicrophonePrivacySettings()
            lastError = "Turn on microphone access in System Settings, then return to Petal."
            return
        }

        lastError = "Microphone access is required to record audio."
    }

    public func minimizeToMiniWindow() {
        onMinimize?()
    }

    public func completeSetup() {
        $hasCompletedSetup.withLock { $0 = true }
        onCompleted?()
    }

    private func ensureAccessibilityPermission() async {
        if isPreviewMode {
            accessibilityAuthorized = true
            lastError = nil
            return
        }

        await permissionsClient.promptForAccessibilityPermission()
        await refreshPermissionStatus()

        if accessibilityAuthorized {
            lastError = nil
            return
        }

        await permissionsClient.openGuidedAccessibilityPrivacySettings()
        lastError = "Accessibility access is required to continue."
    }

    private func refreshPermissionStatus() async {
        microphonePermissionState = await permissionsClient.microphonePermissionState()
        accessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
    }
}

extension OnboardingModel.Page {
    public var primaryTitle: String {
        switch self {
        case .welcome, .model, .shortcut, .microphone, .accessibility, .cleanup, .historyRetention: "Continue"
        case .download: "Download Model"
        }
    }

    public var primaryActionDelay: CGFloat {
        switch self {
        case .welcome: 1.5
        default: 0.1
        }
    }
}

extension OnboardingModel {
    public static func makePreview(
        page: Page = .welcome,
        configure: (OnboardingModel) -> Void = { _ in }
    ) -> OnboardingModel {
        let model = OnboardingModel(initialPage: page, isPreviewMode: true)
        configure(model)
        return model
    }
}
