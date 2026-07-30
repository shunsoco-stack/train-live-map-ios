import SwiftUI
import UIKit
@preconcurrency import UserNotifications

enum NativeNotificationState: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case unavailable

    var label: String {
        switch self {
        case .notDetermined: "未設定"
        case .denied: "通知はオフ"
        case .authorized: "通知はオン"
        case .provisional: "仮通知"
        case .unavailable: "利用できません"
        }
    }
}

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var state: NativeNotificationState = .notDetermined
    @Published private(set) var registrationError: String?
    @Published private(set) var pendingLineID: String?

    private var deviceToken: String?
    private var subscribedLineIDs = Set<String>()
    private var registrar: APNSDeviceRegistrar?

    var backendConfigured: Bool {
        registrar != nil
    }

    private override init() {
        super.init()
    }

    func configure(with configuration: AppConfiguration) async {
        UNUserNotificationCenter.current().delegate = self
        if let endpoint = configuration.apnsRegistrationURL {
            registrar = APNSDeviceRegistrar(endpoint: endpoint)
        }
        await refreshAuthorizationState()
    }

    func requestAuthorization() async {
        registrationError = nil
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationState()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            registrationError = "通知許可を確認できませんでした。\(error.localizedDescription)"
        }
    }

    func syncSubscriptions(lineIDs: Set<String>) async {
        subscribedLineIDs = lineIDs
        guard let registrar, let deviceToken else {
            return
        }
        do {
            try await registrar.register(
                deviceToken: deviceToken,
                lineIDs: lineIDs.sorted()
            )
            registrationError = nil
        } catch {
            registrationError = "通知対象をサーバーへ登録できませんでした。"
        }
    }

    func receive(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        registrationError = nil
        Task {
            await syncSubscriptions(lineIDs: subscribedLineIDs)
        }
    }

    func receiveRegistrationFailure(_ error: Error) {
        registrationError = "APNsへ端末を登録できませんでした。\(error.localizedDescription)"
    }

    func consumePendingLineID() -> String? {
        defer { pendingLineID = nil }
        return pendingLineID
    }

    private func refreshAuthorizationState() async {
        let settings = await UNUserNotificationCenter.current()
            .notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            state = .notDetermined
        case .denied:
            state = .denied
        case .authorized:
            state = .authorized
            UIApplication.shared.registerForRemoteNotifications()
        case .provisional, .ephemeral:
            state = .provisional
            UIApplication.shared.registerForRemoteNotifications()
        @unknown default:
            state = .unavailable
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let lineID = response.notification.request.content.userInfo["lineId"]
            as? String
        guard let lineID, !lineID.isEmpty else {
            return
        }
        await MainActor.run {
            pendingLineID = lineID
        }
    }
}

final class NotificationAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationManager.shared.receive(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.receiveRegistrationFailure(error)
        }
    }
}

private actor APNSDeviceRegistrar {
    private struct Payload: Encodable {
        let deviceToken: String
        let lineIds: [String]
        let platform = "ios"
        let bundleId = "com.shunsoco.trainlivemap"
    }

    private let endpoint: URL
    private let session: URLSession

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func register(deviceToken: String, lineIDs: [String]) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            Payload(deviceToken: deviceToken, lineIds: lineIDs)
        )
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw APIClientError.invalidResponse
        }
    }
}
