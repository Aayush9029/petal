import Dependencies
import Foundation
import FoundationModelClient
import KeyboardShortcuts
import ModelDownloadFeature
import Observation
import PermissionsClient
import Sauce
import Shared
import SwiftUI

@MainActor
@Observable
public final class OnboardingModel {
    public enum Page: Int, CaseIterable, Sendable {
        case welcome
        case model
        case shortcut
        case microphone
        case accessibility
        case appleIntelligence
        case historyRetention
        case download
    }

    // MARK: - Navigation

    public var currentPage: Page

    public var pageOrder: [Page] {
        var pages: [Page] = [
            .welcome,
            .shortcut,
            .microphone,
            .accessibility,
            .historyRetention,
            .model,
        ]
        if shouldShowAppleIntelligencePage {
            pages.append(.appleIntelligence)
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

    public func moveForward() {
        guard let nextPage else { return }
        currentPage = nextPage
        lastPageTransitionDate = Date()
        lastError = nil
        transientMessage = nil
    }

    public func moveBack() {
        guard let previousPage else { return }
        currentPage = previousPage
        lastPageTransitionDate = Date()
        lastError = nil
        transientMessage = nil
    }

    // MARK: - Page Container

    public var showBack: Bool {
        guard previousPage != nil else { return false }
        if currentPage == .download {
            let downloadState = modelDownloadViewModel.state
            if downloadState.isActive || downloadState.isPaused { return false }
        }
        return true
    }

    public var currentPrimaryTitle: String {
        switch currentPage {
        case .model:
            if shouldCompleteAfterModelSelection {
                return "Finish Setup"
            }
            return currentPage.primaryTitle
        case .accessibility:
            return accessibilityAuthorized ? "Continue" : "Enable Accessibility"
        case .microphone:
            return microphoneAuthorized ? "Continue" : "Enable Microphone"
        case .appleIntelligence:
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
        case .welcome, .historyRetention, .appleIntelligence: false
        case .model: selectedModelOption == nil
        case .shortcut: !hasConfiguredShortcut
        case .microphone: false
        case .accessibility: false
        case .download: modelDownloadViewModel.state.isActive
        }
    }

    public func primaryActionTapped() {
        if let last = lastPageTransitionDate, Date().timeIntervalSince(last) < 0.35 {
            return
        }

        switch currentPage {
        case .model:
            guard selectedModelOption != nil else { return }
            if nextPage != nil {
                moveForward()
            } else {
                completeSetup()
            }
        case .shortcut:
            guard hasConfiguredShortcut else { return }
            moveForward()
        case .download:
            if modelDownloadViewModel.state.isDownloaded {
                completeSetup()
            } else {
                Task { await downloadModel() }
            }
        case .microphone:
            if microphoneAuthorized {
                moveForward()
            } else {
                Task { await microphonePermissionButtonTapped() }
            }
        case .accessibility:
            if accessibilityAuthorized {
                moveForward()
            } else {
                accessibilityPermissionButtonTapped()
            }
        case .appleIntelligence:
            if let _ = nextPage {
                moveForward()
            } else {
                completeSetup()
            }
        default:
            moveForward()
        }
    }

    // MARK: - Model Download

    public let modelDownloadViewModel: ModelDownloadModel

    public var selectedModelID: String {
        get { modelDownloadViewModel.selectedModelID }
        set { modelDownloadViewModel.$selectedModelID.withLock { $0 = newValue } }
    }

    public var microphonePermissionState: MicrophonePermissionState = .notDetermined
    public var microphoneAuthorized = false
    public var accessibilityAuthorized = false
    @ObservationIgnored @Shared(.historyRetentionMode) public var historyRetentionMode: HistoryRetentionMode = .both
    @ObservationIgnored @Shared(.appleIntelligenceEnabled) public var appleIntelligenceEnabled = false
    @ObservationIgnored @Shared(.shortcutTriggerMode) var shortcutTriggerMode: ShortcutTriggerMode = .combo
    @ObservationIgnored @Shared(.doubleTapKey) var doubleTapKey: DoubleTapKey = .unconfigured
    @ObservationIgnored @Shared(.doubleTapInterval) var doubleTapInterval: Double = 0.4

    public var lastError: String?
    public var transientMessage: String?

    public var onCompleted: (@MainActor () -> Void)?
    public var onMinimize: (@MainActor () -> Void)?

    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.foundationModelClient) private var foundationModelClient
    @ObservationIgnored @Dependency(\.continuousClock) private var clock

    @ObservationIgnored @Shared(.hasCompletedSetup) private var hasCompletedSetup = false

    @ObservationIgnored private var permissionMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var lastPageTransitionDate: Date?
    @ObservationIgnored private let isPreviewMode: Bool

    public init(initialPage: Page = .welcome, downloadViewModel: ModelDownloadModel? = nil, isPreviewMode: Bool = false) {
        self.currentPage = initialPage
        self.isPreviewMode = isPreviewMode
        modelDownloadViewModel = downloadViewModel ?? ModelDownloadModel(isPreviewMode: isPreviewMode)

        if isPreviewMode {
            $historyRetentionMode.withLock { $0 = .both }
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            accessibilityAuthorized = true
            return
        }

        startPermissionMonitoring()
    }

    // MARK: - Computed

    public var selectedModelOption: ModelOption? {
        modelDownloadViewModel.selectedModelOption
    }

    private var shouldShowAppleIntelligencePage: Bool {
        guard foundationModelClient.isAvailable() else { return false }
        guard let selectedModelOption else { return false }
        if selectedModelOption.provider == .voxtralCore {
            return false
        }
        return !selectedModelOption.supportsSmartTranscription
    }

    private var shouldCompleteAfterModelSelection: Bool {
        guard selectedModelOption != nil else { return false }
        return nextPage == nil
    }

    public var hasConfiguredShortcut: Bool {
        KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil || doubleTapKey.isConfigured
    }

    public var unifiedShortcutBinding: Binding<RecordedShortcut> {
        Binding(
            get: { [weak self] in
                guard let self else { return .unconfigured }
                switch self.shortcutTriggerMode {
                case .combo:
                    guard let shortcut = KeyboardShortcuts.getShortcut(for: .pushToTalk) else {
                        return .unconfigured
                    }
                    var displayNames = [String]()
                    let mods = shortcut.modifiers
                    if mods.contains(.control) { displayNames.append("\u{2303}") }
                    if mods.contains(.option) { displayNames.append("\u{2325}") }
                    if mods.contains(.command) { displayNames.append("\u{2318}") }
                    let keyChar = shortcut.keyToCharacter()?.capitalized ?? "Key \(shortcut.carbonKeyCode)"
                    displayNames.append(keyChar)
                    return .combo(
                        keyCode: shortcut.carbonKeyCode,
                        carbonModifiers: shortcut.carbonModifiers,
                        displayNames: displayNames
                    )
                case .doubleTap:
                    guard self.doubleTapKey.isConfigured else { return .unconfigured }
                    return .singleKey(
                        keyCode: self.doubleTapKey.keyCode,
                        isModifier: self.doubleTapKey.isModifier,
                        displayName: self.doubleTapKey.displayName
                    )
                }
            },
            set: { [weak self] newValue in
                guard let self else { return }
                switch newValue {
                case .unconfigured:
                    KeyboardShortcuts.setShortcut(nil, for: .pushToTalk)
                    self.$doubleTapKey.withLock { $0 = .unconfigured }

                case let .singleKey(keyCode, isModifier, _):
                    self.$shortcutTriggerMode.withLock { $0 = .doubleTap }
                    self.$doubleTapKey.withLock { $0 = DoubleTapKey(keyCode: keyCode, isModifier: isModifier) }
                    self.$doubleTapInterval.withLock { $0 = 0.4 }
                    KeyboardShortcuts.setShortcut(nil, for: .pushToTalk)

                case let .combo(keyCode, carbonModifiers, _):
                    self.$shortcutTriggerMode.withLock { $0 = .combo }
                    KeyboardShortcuts.setShortcut(
                        .init(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers),
                        for: .pushToTalk
                    )
                    self.$doubleTapKey.withLock { $0 = .unconfigured }
                }
            }
        )
    }

    // MARK: - Actions

    public func windowAppeared() {
        if isPreviewMode { return }
        refreshPermissionStatus()
    }

    public func selectedModelChanged() {
        modelDownloadViewModel.selectedModelChanged()
        transientMessage = nil
        lastError = nil
    }

    public func microphonePermissionButtonTapped() async {
        if isPreviewMode {
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            lastError = nil
            return
        }

        let granted = await permissionsClient.requestMicrophonePermission()
        await refreshPermissionStatusAsync()

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

    public func accessibilityPermissionButtonTapped() {
        if isPreviewMode {
            accessibilityAuthorized = true
            transientMessage = nil
            return
        }

        Task {
            await ensureAccessibilityPermission()
        }
    }

    public func downloadModel() async {
        await modelDownloadViewModel.downloadModel()
        transientMessage = modelDownloadViewModel.transientMessage
        lastError = modelDownloadViewModel.lastError
    }

    public func minimizeToMiniWindow() {
        onMinimize?()
    }

    public func completeSetup() {
        $hasCompletedSetup.withLock { $0 = true }
        permissionMonitorTask?.cancel()
        onCompleted?()
    }

    // MARK: - Private

    private func ensureAccessibilityPermission() async {
        if isPreviewMode {
            accessibilityAuthorized = true
            transientMessage = nil
            lastError = nil
            return
        }

        await permissionsClient.promptForAccessibilityPermission()
        await refreshPermissionStatusAsync()

        if accessibilityAuthorized {
            lastError = nil
            transientMessage = nil
            return
        }

        await permissionsClient.openAccessibilityPrivacySettings()
        lastError = "Accessibility access is required to continue."
        transientMessage = "Turn on Accessibility in System Settings, then return to Petal."
    }

    private func refreshPermissionStatus() {
        if isPreviewMode { return }
        Task { await refreshPermissionStatusAsync() }
    }

    private func refreshPermissionStatusAsync() async {
        if isPreviewMode { return }
        microphonePermissionState = await permissionsClient.microphonePermissionState()
        microphoneAuthorized = microphonePermissionState == .authorized
        accessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
    }

    private func startPermissionMonitoring() {
        permissionMonitorTask?.cancel()
        permissionMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshPermissionStatusAsync()
                try? await self.clock.sleep(for: .seconds(1))
            }
        }
    }

    deinit {
        permissionMonitorTask?.cancel()
    }
}

// MARK: - Page Metadata

extension OnboardingModel.Page {
    public var primaryTitle: String {
        switch self {
        case .welcome, .model, .shortcut, .microphone, .accessibility, .appleIntelligence, .historyRetention: "Continue"
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

// MARK: - Preview Support

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
