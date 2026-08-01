import XCTest
@testable import TrainLiveMap

@MainActor
final class ReporterIDStoreTests: XCTestCase {
    private static let legacyKey = "train-live-map.community-reporter-id"

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ReporterIDStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testGeneratesAndRestoresThirtyTwoCharacterHexIDFromSecureStore() throws {
        let store = InMemorySecureStringStore()

        let first = UserPreferences(defaults: defaults, secureStore: store)
        let restored = UserPreferences(defaults: defaults, secureStore: store)

        XCTAssertNotNil(
            first.reporterID.range(
                of: #"^[0-9A-F]{32}$"#,
                options: .regularExpression
            )
        )
        XCTAssertEqual(restored.reporterID, first.reporterID)
        XCTAssertEqual(
            try store.string(forKey: SecureStorageKey.communityReporterID),
            first.reporterID
        )
        XCTAssertNil(defaults.string(forKey: Self.legacyKey))
    }

    func testMigratesValidLegacyIDThenDeletesUserDefaultsValue() throws {
        let store = InMemorySecureStringStore()
        let legacyID = "LegacyReporter_123456"
        defaults.set(legacyID, forKey: Self.legacyKey)

        let preferences = UserPreferences(defaults: defaults, secureStore: store)

        XCTAssertEqual(preferences.reporterID, legacyID)
        XCTAssertEqual(
            try store.string(forKey: SecureStorageKey.communityReporterID),
            legacyID
        )
        XCTAssertNil(defaults.string(forKey: Self.legacyKey))
    }

    func testKeepsLegacyValueWhenKeychainSaveFails() {
        let legacyID = "LegacyReporter_123456"
        defaults.set(legacyID, forKey: Self.legacyKey)
        let store = InMemorySecureStringStore(writeError: TestStoreError.failed)

        let preferences = UserPreferences(defaults: defaults, secureStore: store)

        XCTAssertEqual(preferences.reporterID, legacyID)
        XCTAssertFalse(preferences.reporterIDIsSecurelyStored)
        XCTAssertEqual(defaults.string(forKey: Self.legacyKey), legacyID)
    }

    func testReplacesInvalidLegacyValueAfterSecureSave() throws {
        defaults.set("invalid", forKey: Self.legacyKey)
        let store = InMemorySecureStringStore()

        let preferences = UserPreferences(defaults: defaults, secureStore: store)

        XCTAssertNotEqual(preferences.reporterID, "invalid")
        XCTAssertEqual(preferences.reporterID.count, 32)
        XCTAssertEqual(
            try store.string(forKey: SecureStorageKey.communityReporterID),
            preferences.reporterID
        )
        XCTAssertNil(defaults.string(forKey: Self.legacyKey))
    }

    func testCommunityRetryDeadlinePersistsAndExpiredValueIsRemoved() {
        let store = InMemorySecureStringStore()
        let now = Date(timeIntervalSince1970: 10_000)
        let preferences = UserPreferences(defaults: defaults, secureStore: store)
        preferences.recordCommunityRetry(until: now.addingTimeInterval(45.2))

        let restored = UserPreferences(defaults: defaults, secureStore: store)
        XCTAssertEqual(restored.remainingCommunityRetry(now: now), 46)
        XCTAssertEqual(
            restored.remainingCommunityRetry(now: now.addingTimeInterval(46)),
            0
        )
        XCTAssertNil(
            defaults.object(forKey: "train-live-map.community-retry-not-before")
        )
    }
}

private enum TestStoreError: Error {
    case failed
}

private final class InMemorySecureStringStore:
    SecureStringStoring,
    @unchecked Sendable {
    private var values: [String: String]
    private let writeError: Error?

    init(
        values: [String: String] = [:],
        writeError: Error? = nil
    ) {
        self.values = values
        self.writeError = writeError
    }

    func string(forKey key: String) throws -> String? {
        values[key]
    }

    func set(_ value: String, forKey key: String) throws {
        if let writeError {
            throw writeError
        }
        values[key] = value
    }

    func removeValue(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
}
