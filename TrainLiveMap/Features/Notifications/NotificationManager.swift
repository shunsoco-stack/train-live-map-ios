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
    static let shared = NotificationManager(
        secureStore: KeychainSecureStringStore()
    )

    @Published private(set) var state: NativeNotificationState = .notDetermined
    @Published private(set) var registrationError: String?
    @Published private(set) var pendingLineID: String?

    private var deviceToken: String?
    private var preferences = NotificationPreferences()
    private var isSynchronizing = false
    private var synchronizationRequested = false
    private var installationSecret: String?
    private var subscribedLineIDs = Set<String>()
    private var registrar: APNSDeviceRegistrar?
    private let secureStore: any SecureStringStoring
    private var isConfigured = false

    var backendConfigured: Bool {
        registrar != nil
    }

    init(secureStore: any SecureStringStoring) {
        self.secureStore = secureStore
        super.init()
    }

    func configure(with configuration: AppConfiguration) async {
        UNUserNotificationCenter.current().delegate = self
        let endpoint = AppConfiguration.validatedNativeAPNSEndpoint(
            configuration.apnsRegistrationURL
        )
        registrar = endpoint.flatMap { APNSDeviceRegistrar(endpoint: $0) }
        isConfigured = true

        if configuration.apnsRegistrationURL != nil, registrar == nil {
            registrationError = "HTTPSのAPNs専用端末登録先だけを利用できます。"
        }

        if registrar != nil {
            do {
                if let stored = try secureStore.string(forKey: SecureStorageKey.apnsInstallationSecret) {
                    installationSecret = stored
                } else {
                    let secret = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                        + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                    try secureStore.set(secret, forKey: SecureStorageKey.apnsInstallationSecret)
                    installationSecret = secret
                }
                deviceToken = try secureStore.string(
                    forKey: SecureStorageKey.apnsDeviceToken
                )
            } catch {
                deviceToken = nil
                registrationError = "通知端末IDをKeychainから読み取れませんでした。"
            }
        } else {
            deviceToken = nil
        }
        await refreshAuthorizationState()
    }

    func requestAuthorization() async {
        registrationError = nil
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationState()
            if state.allowsRemoteNotifications {
                await syncSubscriptions(lineIDs: subscribedLineIDs)
            }
        } catch {
            registrationError = "通知許可を確認できませんでした。\(error.localizedDescription)"
        }
    }

    func syncSubscriptions(lineIDs: Set<String>, settings: NotificationPreferences? = nil) async {
        if let settings { preferences = settings }
        subscribedLineIDs = lineIDs
        synchronizationRequested = true
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        while synchronizationRequested {
            synchronizationRequested = false
            await synchronizeCurrentSubscription()
        }
    }

    private func synchronizeCurrentSubscription() async {
        let lineIDs = subscribedLineIDs
        let settings = preferences
        guard isConfigured, let registrar else { return }
        if lineIDs.isEmpty || !settings.enabled {
            await removeServerRegistration(
                using: registrar,
                failureMessage: "通知登録をサーバーから削除できませんでした。"
            )
            return
        }

        guard state.allowsRemoteNotifications else {
            return
        }
        guard let deviceToken else {
            UIApplication.shared.registerForRemoteNotifications()
            return
        }

        guard let installationSecret else {
            registrationError = "通知設定を安全に保存できませんでした。"
            return
        }
        do {
            try await registrar.register(
                deviceToken: deviceToken,
                lineIDs: lineIDs.sorted(),
                installationSecret: installationSecret,
                preferences: settings
            )
            registrationError = nil
        } catch {
            registrationError = "通知対象をサーバーへ登録できませんでした。"
        }
    }

    func receive(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        Task {
            await installAndSynchronize(deviceToken: token)
        }
    }

    func receiveRegistrationFailure(_ error: Error) {
        registrationError = "APNsへ端末を登録できませんでした。\(error.localizedDescription)"
    }

    func consumePendingLineID() -> String? {
        defer { pendingLineID = nil }
        return pendingLineID
    }

    func refreshAfterBecomingActive(lineIDs: Set<String>) async {
        guard isConfigured else {
            return
        }
        subscribedLineIDs = lineIDs
        await refreshAuthorizationState()
        if state.allowsRemoteNotifications {
            await syncSubscriptions(lineIDs: lineIDs)
        }
    }

    func unregisterFromServer() async {
        subscribedLineIDs = []
        UIApplication.shared.unregisterForRemoteNotifications()
        guard let registrar else {
            if deviceToken != nil {
                registrationError = "APNs端末登録先が未設定のため、サーバーの通知登録を削除できません。"
            }
            return
        }
        await removeServerRegistration(
            using: registrar,
            failureMessage: "通知登録をサーバーから削除できませんでした。後でもう一度お試しください。"
        )
    }

    private func refreshAuthorizationState() async {
        let settings = await UNUserNotificationCenter.current()
            .notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            state = .notDetermined
            await removeRegistrationAfterPermissionLoss()
        case .denied:
            state = .denied
            await removeRegistrationAfterPermissionLoss()
        case .authorized:
            state = .authorized
            if registrar != nil, !subscribedLineIDs.isEmpty {
                UIApplication.shared.registerForRemoteNotifications()
            }
        case .provisional, .ephemeral:
            state = .provisional
            if registrar != nil, !subscribedLineIDs.isEmpty {
                UIApplication.shared.registerForRemoteNotifications()
            }
        @unknown default:
            state = .unavailable
            await removeRegistrationAfterPermissionLoss()
        }
    }

    private func installAndSynchronize(deviceToken newToken: String) async {
        guard isConfigured, let registrar else {
            deviceToken = nil
            return
        }

        let previousToken = deviceToken
        if let previousToken, previousToken != newToken {
            do {
                try await registrar.unregister(deviceToken: previousToken, installationSecret: installationSecret ?? "")
            } catch {
                registrationError = "古い通知端末IDをサーバーから削除できませんでした。"
                return
            }
        }

        do {
            try secureStore.set(
                newToken,
                forKey: SecureStorageKey.apnsDeviceToken
            )
            deviceToken = newToken
            registrationError = nil
        } catch {
            deviceToken = previousToken
            registrationError = "通知端末IDをKeychainへ安全に保存できませんでした。"
            return
        }

        await syncSubscriptions(lineIDs: subscribedLineIDs)
    }

    private func removeRegistrationAfterPermissionLoss() async {
        UIApplication.shared.unregisterForRemoteNotifications()
        guard let registrar else {
            return
        }
        await removeServerRegistration(
            using: registrar,
            failureMessage: "通知許可の解除をサーバーへ反映できませんでした。"
        )
    }

    private func removeServerRegistration(
        using registrar: APNSDeviceRegistrar,
        failureMessage: String
    ) async {
        UIApplication.shared.unregisterForRemoteNotifications()
        guard let deviceToken else {
            return
        }

        do {
            try await registrar.unregister(deviceToken: deviceToken, installationSecret: installationSecret ?? "")
        } catch {
            registrationError = failureMessage
            return
        }

        self.deviceToken = nil
        do {
            try secureStore.removeValue(forKey: SecureStorageKey.apnsDeviceToken)
            registrationError = nil
        } catch {
            registrationError = "サーバーの通知登録は削除しましたが、端末内の通知IDを削除できませんでした。"
        }
    }
}

private extension NativeNotificationState {
    var allowsRemoteNotifications: Bool {
        self == .authorized || self == .provisional
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

actor APNSDeviceRegistrar {
    private struct Payload: Encodable {
        let deviceToken: String
        let lineIds: [String]?
        let platform = "ios"
        let bundleId = Bundle.main.bundleIdentifier ?? "com.shunsoco.trainlivemap"
        let environment = Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String ?? "development"
        let installationSecret: String
        let preferences: NotificationPreferences?
    }

    private let endpoint: URL
    private let session: URLSession

    init?(endpoint: URL, session: URLSession? = nil) {
        guard let endpoint = AppConfiguration.validatedNativeAPNSEndpoint(endpoint) else {
            return nil
        }
        self.endpoint = endpoint
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = true
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(
                configuration: configuration,
                delegate: APNSNoRedirectSessionDelegate(),
                delegateQueue: nil
            )
        }
    }

    func register(deviceToken: String, lineIDs: [String], installationSecret: String, preferences: NotificationPreferences) async throws {
        guard deviceToken.range(of: "^[a-f0-9]{64,200}$", options: .regularExpression) != nil,
              deviceToken.count.isMultiple(of: 2),
              installationSecret.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw APNSDeviceRegistrarError.invalidResponse
        }
        _ = try LineFilterQuery.queryItems(for: Set(lineIDs))
        try await send(
            method: "POST",
            payload: Payload(deviceToken: deviceToken, lineIds: lineIDs, installationSecret: installationSecret, preferences: preferences)
        )
    }

    func unregister(deviceToken: String, installationSecret: String) async throws {
        try await send(
            method: "DELETE",
            payload: Payload(deviceToken: deviceToken, lineIds: nil, installationSecret: installationSecret, preferences: nil)
        )
    }

    private func send(method: String, payload: Payload) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TrainLiveMap-iOS/1.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              AppConfiguration.validatedNativeAPNSEndpoint(response.url) != nil else {
            throw APNSDeviceRegistrarError.invalidResponse
        }
        let successful = (200..<300).contains(response.statusCode)
            || (method == "DELETE" && [404, 410].contains(response.statusCode))
        guard successful else {
            throw APNSDeviceRegistrarError.httpStatus(response.statusCode)
        }
    }
}

private enum APNSDeviceRegistrarError: Error {
    case invalidResponse
    case httpStatus(Int)
}

private final class APNSNoRedirectSessionDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
