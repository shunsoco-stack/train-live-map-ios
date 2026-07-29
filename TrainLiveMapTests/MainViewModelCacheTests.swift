import XCTest
@testable import TrainLiveMap

@MainActor
final class MainViewModelCacheTests: XCTestCase {
    func testAPIFailureKeepsCachedTrainsAndMarksThemStale() async throws {
        let cachedResponse = try TestFixture.trainsResponse
        let cache = MemoryResponseCache(trains: cachedResponse)
        let api = StubAPIService(trainsResult: .failure(TestError.failed))
        let preferences = UserPreferences(
            defaults: UserDefaults(suiteName: "cache-test-\(UUID().uuidString)")!
        )
        let viewModel = MainViewModel(
            api: api,
            cache: cache,
            preferences: preferences
        )

        await viewModel.loadCachedDataIfNeeded()
        XCTAssertEqual(viewModel.trainsResponse, cachedResponse)
        XCTAssertTrue(viewModel.trainsAreStale)

        await viewModel.refreshTrains()
        XCTAssertEqual(viewModel.trainsResponse, cachedResponse)
        XCTAssertTrue(viewModel.trainsAreStale)
        XCTAssertNotNil(viewModel.trainErrorMessage)
    }

    func testSuccessfulRefreshReplacesStaleCache() async throws {
        let response = try TestFixture.trainsResponse
        let cache = MemoryResponseCache(trains: response)
        let api = StubAPIService(trainsResult: .success(response))
        let preferences = UserPreferences(
            defaults: UserDefaults(suiteName: "success-test-\(UUID().uuidString)")!
        )
        let viewModel = MainViewModel(
            api: api,
            cache: cache,
            preferences: preferences
        )

        await viewModel.loadCachedDataIfNeeded()
        XCTAssertTrue(viewModel.trainsAreStale)
        await viewModel.refreshTrains()
        XCTAssertFalse(viewModel.trainsAreStale)
        XCTAssertNil(viewModel.trainErrorMessage)
    }

    func testMockAndFallbackPresentationAreExplicit() throws {
        let response = try TestFixture.trainsResponse
        let mock = TrainsAPIResponse(
            trains: response.trains,
            generatedAt: response.generatedAt,
            dataUpdatedAt: response.dataUpdatedAt,
            isMock: true,
            source: .mock,
            fallback: false,
            notice: "モックデータです"
        )
        let fallback = TrainsAPIResponse(
            trains: response.trains,
            generatedAt: response.generatedAt,
            dataUpdatedAt: response.dataUpdatedAt,
            isMock: true,
            source: .mock,
            fallback: true,
            notice: "フォールバック中"
        )

        XCTAssertEqual(DataSourcePresentation(response: mock).title, "モック")
        XCTAssertTrue(DataSourcePresentation(response: mock).isWarning)
        XCTAssertEqual(DataSourcePresentation(response: fallback).title, "フォールバック")
        XCTAssertEqual(
            DataSourcePresentation(response: fallback).detail,
            "フォールバック中"
        )
    }
}
