import XCTest
@testable import TrainLiveMap

@MainActor
final class MainViewModelCommunitySecurityTests: XCTestCase {
    func testDoesNotSubmitWhenReporterIDCannotBeStoredInKeychain() async {
        let api = RateLimitedAPIService(
            retryAfter: Date().addingTimeInterval(120)
        )
        let suiteName = "CommunitySecurityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = UserPreferences(
            defaults: defaults,
            secureStore: CommunitySecurityMemoryStore(failsWrites: true)
        )
        let viewModel = MainViewModel(
            api: api,
            cache: MemoryResponseCache(),
            preferences: preferences
        )

        let result = await viewModel.submitCommunityReport(
            lineID: "JR-East.Tokaido",
            status: .onTime,
            delayMinutes: nil
        )
        let submissionCount = await api.submissionCount()

        XCTAssertFalse(result)
        XCTAssertEqual(submissionCount, 0)
        XCTAssertTrue(viewModel.communityErrorMessage?.contains("Keychain") == true)
    }

    func testRateLimitDeadlinePreventsSecondRepositorySubmission() async {
        let retryAfter = Date().addingTimeInterval(120)
        let api = RateLimitedAPIService(retryAfter: retryAfter)
        let suiteName = "CommunitySecurityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = UserPreferences(
            defaults: defaults,
            secureStore: CommunitySecurityMemoryStore()
        )
        let viewModel = MainViewModel(
            api: api,
            cache: MemoryResponseCache(),
            preferences: preferences
        )

        let firstResult = await viewModel.submitCommunityReport(
            lineID: "JR-East.Tokaido",
            status: .onTime,
            delayMinutes: nil
        )
        let secondResult = await viewModel.submitCommunityReport(
            lineID: "JR-East.Tokaido",
            status: .onTime,
            delayMinutes: nil
        )
        let submissionCount = await api.submissionCount()

        XCTAssertFalse(firstResult)
        XCTAssertFalse(secondResult)
        XCTAssertEqual(submissionCount, 1)
        XCTAssertGreaterThan(preferences.remainingCommunityRetry(), 0)
        XCTAssertTrue(
            viewModel.communityErrorMessage?.contains("再送") == true
        )
    }
}

private actor RateLimitedAPIService: TrainAPIService {
    private let retryAfter: Date
    private var count = 0

    init(retryAfter: Date) {
        self.retryAfter = retryAfter
    }

    func fetchTrains(lineIDs: Set<String>) async throws -> TrainsAPIResponse {
        throw TestError.failed
    }

    func fetchServiceStatus(
        lineIDs: Set<String>
    ) async throws -> ServiceStatusAPIResponse {
        throw TestError.failed
    }

    func fetchRailways() async throws -> RailwaysAPIResponse {
        throw TestError.failed
    }

    func fetchCommunityReports() async throws -> CommunityReportsAPIResponse {
        throw TestError.failed
    }

    func submitCommunityReport(
        _ vote: CommunityReportVote,
        reporterID: String
    ) async throws -> CommunityReportSubmitResponse {
        count += 1
        throw APIClientError.rateLimited(
            retryAfter: retryAfter,
            message: "短時間の投票上限に達しました。"
        )
    }

    func submissionCount() -> Int { count }
}

private final class CommunitySecurityMemoryStore: SecureStringStoring,
    @unchecked Sendable {
    private var values: [String: String] = [:]
    private let failsWrites: Bool

    init(failsWrites: Bool = false) {
        self.failsWrites = failsWrites
    }

    func string(forKey key: String) throws -> String? {
        values[key]
    }

    func set(_ value: String, forKey key: String) throws {
        if failsWrites {
            throw TestError.failed
        }
        values[key] = value
    }

    func removeValue(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
}
