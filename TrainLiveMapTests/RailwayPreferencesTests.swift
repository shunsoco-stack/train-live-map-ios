import XCTest
@testable import TrainLiveMap

@MainActor
final class RailwayPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TrainLiveMapTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSearchMatchesNameAliasAndCategory() throws {
        let options = try TestFixture.railwaysResponse.options

        XCTAssertEqual(
            RailwayFilterLogic.filtered(
                options: options,
                query: "東海道",
                favoritesOnly: false,
                favoriteIDs: []
            ).map(\.id),
            ["tokaido"]
        )
        XCTAssertEqual(
            RailwayFilterLogic.filtered(
                options: options,
                query: "中央快速",
                favoritesOnly: false,
                favoriteIDs: []
            ).map(\.id),
            ["chuo-rapid"]
        )
    }

    func testVisibilityFavoritesAndFavoritesOnlyPersist() throws {
        let options = try TestFixture.railwaysResponse.options
        let preferences = UserPreferences(defaults: defaults)
        preferences.reconcile(with: options)

        XCTAssertEqual(
            preferences.visibleLineIDs,
            ["tokaido", "chuo-rapid"]
        )
        preferences.toggleVisibility(for: "chuo-rapid")
        preferences.toggleFavorite(for: "chuo-rapid")
        preferences.setFavoritesOnly(true)

        XCTAssertEqual(preferences.visibleLineIDs, ["tokaido"])
        XCTAssertEqual(preferences.favoriteLineIDs, ["chuo-rapid"])
        XCTAssertTrue(preferences.effectiveVisibleLineIDs.isEmpty)

        let restored = UserPreferences(defaults: defaults)
        restored.reconcile(with: options)
        XCTAssertEqual(restored.visibleLineIDs, ["tokaido"])
        XCTAssertEqual(restored.favoriteLineIDs, ["chuo-rapid"])
        XCTAssertTrue(restored.favoritesOnly)
    }

    func testFavoriteAndNotificationRoutesPersistSeparately() throws {
        let options = try TestFixture.railwaysResponse.options
        let preferences = UserPreferences(defaults: defaults)
        preferences.reconcile(with: options)
        preferences.toggleFavorite(for: "tokaido")
        preferences.toggleNotification(for: "chuo-rapid")

        let restored = UserPreferences(defaults: defaults)
        restored.reconcile(with: options)
        XCTAssertEqual(restored.favoriteLineIDs, ["tokaido"])
        XCTAssertEqual(restored.notificationLineIDs, ["chuo-rapid"])
    }

    func testFavoritesOnlyFilter() throws {
        let options = try TestFixture.railwaysResponse.options
        let filtered = RailwayFilterLogic.filtered(
            options: options,
            query: "",
            favoritesOnly: true,
            favoriteIDs: ["tokaido"]
        )
        XCTAssertEqual(filtered.map(\.id), ["tokaido"])
    }
}
