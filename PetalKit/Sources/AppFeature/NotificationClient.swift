import Dependencies
import DependenciesMacros
import Foundation
import UserNotifications

@DependencyClient
struct NotificationClient: Sendable {
    var post: @Sendable (_ body: String) async -> Void
}

extension NotificationClient: DependencyKey {
    static let liveValue = Self(post: { body in
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = "Petal"
        content.body = body
        @Dependency(\.uuid) var uuid
        try? await center.add(UNNotificationRequest(identifier: uuid().uuidString, content: content, trigger: nil))
    })
    static let testValue = Self()
}

extension DependencyValues {
    var notificationClient: NotificationClient {
        get { self[NotificationClient.self] }
        set { self[NotificationClient.self] = newValue }
    }
}
