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
            ["tokaido", "sagami"]
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

        XCTAssertEqual(preferences.visibleLineIDs, ["tokaido"])
        preferences.toggleVisibility(for: "chuo-rapid")
        preferences.toggleVisibility(for: "tokaido")
        preferences.toggleFavorite(for: "chuo-rapid")
        preferences.setFavoritesOnly(true)

        XCTAssertEqual(preferences.visibleLineIDs, ["chuo-rapid"])
        XCTAssertEqual(preferences.favoriteLineIDs, ["chuo-rapid"])
        XCTAssertEqual(preferences.effectiveVisibleLineIDs, ["chuo-rapid"])

        let restored = UserPreferences(defaults: defaults)
        restored.reconcile(with: options)
        XCTAssertEqual(restored.visibleLineIDs, ["chuo-rapid"])
        XCTAssertEqual(restored.favoriteLineIDs, ["chuo-rapid"])
        XCTAssertTrue(restored.favoritesOnly)
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
