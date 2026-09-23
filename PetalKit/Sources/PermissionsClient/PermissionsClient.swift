@preconcurrency import ApplicationServices
import AppKit
import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import ServiceManagement

public enum MicrophonePermissionState: Sendable {
    case notDetermined
    case denied
    case authorized
}

@DependencyClient
public struct PermissionsClient: Sendable {
    public var microphonePermissionState: @Sendable () async -> MicrophonePermissionState = { .notDetermined }
    public var requestMicrophonePermission: @Sendable () async -> Bool = { false }
    public var hasAccessibilityPermission: @Sendable () async -> Bool = { false }
    public var promptForAccessibilityPermission: @Sendable () async -> Void = {}
    public var openMicrophonePrivacySettings: @Sendable () async -> Void = {}
    public var openAccessibilityPrivacySettings: @Sendable () async -> Void = {}
    public var openGuidedAccessibilityPrivacySettings: @Sendable () async -> Void = {}
    public var launchAtLoginState: @Sendable () async -> LaunchAtLoginState = { .disabled }
    public var setLaunchAtLogin: @Sendable (Bool) async throws -> LaunchAtLoginState
    public var openLoginItemsSettings: @Sendable () async -> Void = {}
}

public enum LaunchAtLoginState: Sendable {
    case disabled
    case enabled
    /// macOS registered the login item, but the user must allow it in System Settings.
    case requiresApproval
}

extension PermissionsClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            microphonePermissionState: {
                await MainActor.run { microphonePermissionStateLive() }
            },
            requestMicrophonePermission: {
                await requestMicrophonePermissionLive()
            },
            hasAccessibilityPermission: {
                await MainActor.run { AXIsProcessTrusted() }
            },
            promptForAccessibilityPermission: {
                if await MainActor.run(body: { !AXIsProcessTrusted() }) {
                    await resetAccessibilityEntryLive()
                }
                await MainActor.run { promptForAccessibilityPermissionLive() }
            },
            openMicrophonePrivacySettings: {
                await MainActor.run { openMicrophonePrivacySettingsLive() }
            },
            openAccessibilityPrivacySettings: {
                await MainActor.run { openAccessibilityPrivacySettingsLive() }
            },
            openGuidedAccessibilityPrivacySettings: {
                await MainActor.run { AccessibilitySettingsGuide.shared.present() }
            },
            launchAtLoginState: {
                LaunchAtLoginState(SMAppService.mainApp.status)
            },
            setLaunchAtLogin: { enabled in
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }
                return LaunchAtLoginState(SMAppService.mainApp.status)
            },
            openLoginItemsSettings: {
                SMAppService.openSystemSettingsLoginItems()
            }
        )
    }
}

extension PermissionsClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            microphonePermissionState: { .authorized },
            requestMicrophonePermission: { true },
            hasAccessibilityPermission: { true },
            promptForAccessibilityPermission: {},
            openMicrophonePrivacySettings: {},
            openAccessibilityPrivacySettings: {},
            openGuidedAccessibilityPrivacySettings: {},
            launchAtLoginState: { .disabled },
            setLaunchAtLogin: { $0 ? .enabled : .disabled },
            openLoginItemsSettings: {}
        )
    }
}

private extension LaunchAtLoginState {
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        default: self = .disabled
        }
    }
}

public extension DependencyValues {
    var permissionsClient: PermissionsClient {
        get { self[PermissionsClient.self] }
        set { self[PermissionsClient.self] = newValue }
    }
}

@MainActor
private func microphonePermissionStateLive() -> MicrophonePermissionState {
    let captureState = microphonePermissionStateFromCaptureDevice()

    if #available(macOS 14.0, *) {
        let audioApplicationState: MicrophonePermissionState
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            audioApplicationState = .authorized
        case .undetermined:
            audioApplicationState = .notDetermined
        case .denied:
            audioApplicationState = .denied
        @unknown default:
            audioApplicationState = .denied
        }

        if captureState == .authorized || audioApplicationState == .authorized {
            return .authorized
        }

        if captureState == .notDetermined || audioApplicationState == .notDetermined {
            return .notDetermined
        }

        return .denied
    }

    return captureState
}

private func requestMicrophonePermissionLive() async -> Bool {
    if await MainActor.run(body: { microphonePermissionStateLive() == .authorized }) {
        return true
    }

    if #available(macOS 14.0, *) {
        let appPermissionGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { isGranted in
                continuation.resume(returning: isGranted)
            }
        }

        if appPermissionGranted {
            return true
        }
    }

    if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
        return true
    }

    let capturePermissionGranted = await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { isGranted in
            continuation.resume(returning: isGranted)
        }
    }

    if capturePermissionGranted {
        return true
    }

    return await MainActor.run(body: { microphonePermissionStateLive() == .authorized })
}

/// A signing identity change leaves a stale Accessibility entry. System Settings shows it as on, but
/// `AXIsProcessTrusted()` stays false for the new signature, and turning it off and on again does not help.
/// Removing Petal's own entry lets the next prompt add one for the current signature.
private func resetAccessibilityEntryLive() async {
    guard let bundleID = Bundle.main.bundleIdentifier else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
    process.arguments = ["reset", "Accessibility", bundleID]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        process.terminationHandler = { _ in continuation.resume() }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            continuation.resume()
        }
    }
}

@MainActor
private func promptForAccessibilityPermissionLive() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
}

@MainActor
private func openMicrophonePrivacySettingsLive() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
        return
    }

    NSWorkspace.shared.open(url)
}

@MainActor
private func openAccessibilityPrivacySettingsLive() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
        return
    }

    NSWorkspace.shared.open(url)
}

@MainActor
private func microphonePermissionStateFromCaptureDevice() -> MicrophonePermissionState {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .notDetermined:
        return .notDetermined
    case .restricted, .denied:
        return .denied
    case .authorized:
        return .authorized
    @unknown default:
        return .denied
    }
}
