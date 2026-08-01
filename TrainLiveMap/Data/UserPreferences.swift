import Foundation

@MainActor
final class UserPreferences: ObservableObject {
    private enum Key {
        static let visibleLineIDs = "train-live-map.visible-line-ids"
        static let favoriteLineIDs = "train-live-map.favorite-line-ids"
        static let notificationLineIDs = "train-live-map.notification-line-ids"
        static let favoritesOnly = "train-live-map.favorites-only"
        static let visibilityInitialized = "train-live-map.visibility-initialized"
        static let legacyReporterID = "train-live-map.community-reporter-id"
        static let communitySubmissionDates = "train-live-map.community-submission-dates"
        static let communityRetryNotBefore =
            "train-live-map.community-retry-not-before"
    }

    private static let reporterIDPattern = #"^[A-Za-z0-9_-]{12,100}$"#

    @Published private(set) var visibleLineIDs: Set<String>
    @Published private(set) var favoriteLineIDs: Set<String>
    @Published private(set) var notificationLineIDs: Set<String>
    @Published private(set) var favoritesOnly: Bool
    let reporterID: String
    let reporterIDIsSecurelyStored: Bool

    private let defaults: UserDefaults
    private var visibilityInitialized: Bool
    private var communitySubmissionDates: [String: TimeInterval]

    init(
        defaults: UserDefaults = .standard,
        secureStore: any SecureStringStoring = KeychainSecureStringStore()
    ) {
        self.defaults = defaults
        visibleLineIDs = Set(defaults.stringArray(forKey: Key.visibleLineIDs) ?? [])
        favoriteLineIDs = Set(defaults.stringArray(forKey: Key.favoriteLineIDs) ?? [])
        notificationLineIDs = Set(
            defaults.stringArray(forKey: Key.notificationLineIDs) ?? []
        )
        favoritesOnly = defaults.bool(forKey: Key.favoritesOnly)
        visibilityInitialized = defaults.bool(forKey: Key.visibilityInitialized)
        let reporterIdentity = Self.loadOrCreateReporterID(
            defaults: defaults,
            secureStore: secureStore
        )
        reporterID = reporterIdentity.value
        reporterIDIsSecurelyStored = reporterIdentity.isSecurelyStored
        communitySubmissionDates = defaults.dictionary(
            forKey: Key.communitySubmissionDates
        ) as? [String: TimeInterval] ?? [:]
    }

    private static func loadOrCreateReporterID(
        defaults: UserDefaults,
        secureStore: any SecureStringStoring
    ) -> ReporterIdentity {
        if let stored = try? secureStore.string(
            forKey: SecureStorageKey.communityReporterID
        ), isValidReporterID(stored) {
            defaults.removeObject(forKey: Key.legacyReporterID)
            return ReporterIdentity(value: stored, isSecurelyStored: true)
        }

        let legacy = defaults.string(forKey: Key.legacyReporterID)
        let candidate = legacy.flatMap { value in
            isValidReporterID(value) ? value : nil
        } ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")

        do {
            try secureStore.set(
                candidate,
                forKey: SecureStorageKey.communityReporterID
            )
            defaults.removeObject(forKey: Key.legacyReporterID)
            return ReporterIdentity(value: candidate, isSecurelyStored: true)
        } catch {
            // Keep a valid legacy ID until a later launch can complete migration.
            return ReporterIdentity(value: candidate, isSecurelyStored: false)
        }
    }

    private static func isValidReporterID(_ value: String) -> Bool {
        value.range(
            of: reporterIDPattern,
            options: .regularExpression
        ) != nil
    }

    private struct ReporterIdentity {
        let value: String
        let isSecurelyStored: Bool
    }

    var effectiveVisibleLineIDs: Set<String> {
        favoritesOnly
            ? visibleLineIDs.intersection(favoriteLineIDs)
            : visibleLineIDs
    }

    func reconcile(with options: [RailwayFilterOption]) {
        let selectableOptions = options.filter(\.isSelectable)
        let knownIDs = Set(selectableOptions.map(\.id))

        favoriteLineIDs.formIntersection(knownIDs)
        notificationLineIDs.formIntersection(knownIDs)
        if visibilityInitialized {
            visibleLineIDs.formIntersection(knownIDs)
        } else {
            visibleLineIDs = RailwaySelectionLogic.defaultVisibleIDs(
                from: selectableOptions
            )
            visibilityInitialized = true
            defaults.set(true, forKey: Key.visibilityInitialized)
        }
        persist()
    }

    func setVisibleLineIDs(_ ids: Set<String>) {
        visibleLineIDs = ids
        visibilityInitialized = true
        defaults.set(true, forKey: Key.visibilityInitialized)
        persist()
    }

    func toggleVisibility(for id: String) {
        if visibleLineIDs.contains(id) {
            visibleLineIDs.remove(id)
        } else {
            visibleLineIDs.insert(id)
        }
        visibilityInitialized = true
        defaults.set(true, forKey: Key.visibilityInitialized)
        persist()
    }

    func toggleFavorite(for id: String) {
        if favoriteLineIDs.contains(id) {
            favoriteLineIDs.remove(id)
        } else {
            favoriteLineIDs.insert(id)
        }
        persist()
    }

    func toggleNotification(for id: String) {
        if notificationLineIDs.contains(id) {
            notificationLineIDs.remove(id)
        } else {
            notificationLineIDs.insert(id)
        }
        persist()
    }

    func addFavoritesToNotifications() {
        notificationLineIDs.formUnion(favoriteLineIDs)
        persist()
    }

    func clearNotificationLineIDs() {
        guard !notificationLineIDs.isEmpty else {
            return
        }
        notificationLineIDs.removeAll()
        persist()
    }

    func setFavoritesOnly(_ value: Bool) {
        favoritesOnly = value
        persist()
    }

    func showAll(_ options: [RailwayFilterOption]) {
        setVisibleLineIDs(Set(options.filter(\.isSelectable).map(\.id)))
    }

    func hideAll() {
        setVisibleLineIDs([])
    }

    func showOnly(lineID: String) {
        visibleLineIDs = [lineID]
        favoritesOnly = false
        visibilityInitialized = true
        defaults.set(true, forKey: Key.visibilityInitialized)
        persist()
    }

    func remainingCommunityCooldown(
        lineID: String,
        cooldownSeconds: Int,
        now: Date = .now
    ) -> Int {
        guard let timestamp = communitySubmissionDates[lineID] else {
            return 0
        }
        let remaining = TimeInterval(cooldownSeconds)
            - now.timeIntervalSince1970
            + timestamp
        return max(0, Int(ceil(remaining)))
    }

    func recordCommunitySubmission(lineID: String, at date: Date = .now) {
        communitySubmissionDates[lineID] = date.timeIntervalSince1970
        defaults.set(
            communitySubmissionDates,
            forKey: Key.communitySubmissionDates
        )
    }

    func remainingCommunityRetry(now: Date = .now) -> Int {
        guard let timestamp = defaults.object(
            forKey: Key.communityRetryNotBefore
        ) as? NSNumber else {
            return 0
        }
        let remaining = timestamp.doubleValue - now.timeIntervalSince1970
        guard remaining > 0 else {
            defaults.removeObject(forKey: Key.communityRetryNotBefore)
            return 0
        }
        return Int(ceil(remaining))
    }

    func recordCommunityRetry(until date: Date) {
        defaults.set(
            date.timeIntervalSince1970,
            forKey: Key.communityRetryNotBefore
        )
    }

    private func persist() {
        defaults.set(visibleLineIDs.sorted(), forKey: Key.visibleLineIDs)
        defaults.set(favoriteLineIDs.sorted(), forKey: Key.favoriteLineIDs)
        defaults.set(
            notificationLineIDs.sorted(),
            forKey: Key.notificationLineIDs
        )
        defaults.set(favoritesOnly, forKey: Key.favoritesOnly)
    }
}
