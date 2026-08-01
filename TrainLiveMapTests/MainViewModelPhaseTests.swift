import SwiftUI
import XCTest
@testable import TrainLiveMap

@MainActor
final class MainViewModelPhaseTests: XCTestCase {
    func testOneShotLocationRequestSurvivesPermissionAlertInactivity() {
        XCTAssertTrue(
            MapSceneActivityPolicy.keepsOneShotLocationRequestAlive(
                during: .active
            )
        )
        XCTAssertTrue(
            MapSceneActivityPolicy.keepsOneShotLocationRequestAlive(
                during: .inactive
            )
        )
        XCTAssertFalse(
            MapSceneActivityPolicy.keepsOneShotLocationRequestAlive(
                during: .background
            )
        )
    }

    func testRefreshUsesEffectiveSelectedLineIDsAndTenSecondCadence() async throws {
        let response = try TestFixture.trainsResponse
        let repository = PhaseRecordingRepository(trainsResponse: response)
        let preferences = makePreferences()
        preferences.setVisibleLineIDs(["yamanote", "tokaido"])
        let viewModel = MainViewModel(
            repository: repository,
            preferences: preferences,
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        await viewModel.refreshTrains()
        await viewModel.refreshServiceStatus()

        let trainLineIDs = await repository.recordedTrainLineIDs()
        let serviceLineIDs = await repository.recordedServiceLineIDs()
        XCTAssertEqual(trainLineIDs, ["yamanote", "tokaido"])
        XCTAssertEqual(serviceLineIDs, ["yamanote", "tokaido"])
        XCTAssertEqual(MainViewModel.trainRefreshInterval, 10)
        XCTAssertEqual(MainViewModel.serviceRefreshInterval, 10)
        XCTAssertEqual(MainViewModel.communityRefreshInterval, 10)
    }

    func testZeroSelectedLinesDoNotRequestAllLines() async throws {
        let repository = PhaseRecordingRepository(
            trainsResponse: try TestFixture.trainsResponse
        )
        let preferences = makePreferences()
        preferences.hideAll()
        let viewModel = MainViewModel(
            repository: repository,
            preferences: preferences,
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        await viewModel.refreshTrains()
        await viewModel.refreshServiceStatus()

        let trainRequestCount = await repository.trainRequestCount()
        let serviceRequestCount = await repository.serviceRequestCount()
        XCTAssertEqual(trainRequestCount, 0)
        XCTAssertEqual(serviceRequestCount, 0)
        XCTAssertTrue(viewModel.currentTrains.isEmpty)
    }

    func testCachedPositionsRemainVisibleAsExplicitlyStaleWhileOnline() async throws {
        let response = try TestFixture.trainsResponse
        let repository = PhaseRecordingRepository(
            trainsResponse: response,
            cachedTrains: response
        )
        let preferences = makePreferences()
        preferences.setVisibleLineIDs(Set(response.trains.map(\.lineId)))
        let viewModel = MainViewModel(
            repository: repository,
            preferences: preferences,
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        await viewModel.loadCachedDataIfNeeded()

        XCTAssertTrue(viewModel.trainsAreStale)
        XCTAssertFalse(viewModel.currentTrains.isEmpty)
        XCTAssertFalse(viewModel.filteredTrains.isEmpty)
        viewModel.selectedTrainID = response.trains.first?.id
        XCTAssertNotNil(viewModel.selectedTrain)
    }

    func testBadRequestIsNotRepeatedUntilSelectionChanges() async throws {
        let repository = PhaseRecordingRepository(
            trainsResponse: try TestFixture.trainsResponse,
            trainError: APIClientError.badRequest(
                message: "路線指定を確認してください"
            )
        )
        let preferences = makePreferences()
        preferences.setVisibleLineIDs(["yamanote"])
        let viewModel = MainViewModel(
            repository: repository,
            preferences: preferences,
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        await viewModel.refreshTrains()
        await viewModel.refreshTrains()
        var requestCount = await repository.trainRequestCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(viewModel.canRetryTrainRequest)
        XCTAssertTrue(
            viewModel.trainRetrySuppressionMessage?.contains(
                "路線選択を変更"
            ) == true
        )

        preferences.setVisibleLineIDs(["tokaido"])
        await viewModel.refreshTrains()
        requestCount = await repository.trainRequestCount()
        XCTAssertEqual(requestCount, 2)
    }

    func testRetryAfterPreventsManualOrPeriodicRequestBeforeDeadline() async throws {
        let retryAfter = Date.now.addingTimeInterval(120)
        let repository = PhaseRecordingRepository(
            trainsResponse: try TestFixture.trainsResponse,
            trainError: APIClientError.rateLimited(
                retryAfter: retryAfter,
                message: "待ってください"
            )
        )
        let preferences = makePreferences()
        preferences.setVisibleLineIDs(["yamanote"])
        let viewModel = MainViewModel(
            repository: repository,
            preferences: preferences,
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        await viewModel.refreshTrains()
        preferences.setVisibleLineIDs(["tokaido"])
        await viewModel.refreshTrains()

        let requestCount = await repository.trainRequestCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(viewModel.canRetryTrainRequest)
        XCTAssertTrue(
            viewModel.trainRetrySuppressionMessage?.contains(
                "までは再送しません"
            ) == true
        )
    }

    func testServiceRetryAfterPreventsRepeatedRequest() async throws {
        let retryAfter = Date.now.addingTimeInterval(120)
        let repository = PhaseRecordingRepository(
            trainsResponse: try TestFixture.trainsResponse,
            serviceError: APIClientError.serviceUnavailable(
                retryAfter: retryAfter,
                message: "一時停止中"
            )
        )
        let preferences = makePreferences()
        preferences.setVisibleLineIDs(["yamanote"])
        let viewModel = MainViewModel(
            repository: repository,
            preferences: preferences,
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        await viewModel.refreshServiceStatus()
        await viewModel.refreshServiceStatus()

        let requestCount = await repository.serviceRequestCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(
            viewModel.serviceRetrySuppressionMessage?.contains(
                "までは再送しません"
            ) == true
        )
    }

    func testOfflineHidesPositionsStopsPollingAndReconnectsImmediately() async throws {
        let response = try TestFixture.trainsResponse
        let repository = PhaseRecordingRepository(
            trainsResponse: response,
            cachedTrains: response
        )
        let preferences = makePreferences()
        preferences.setVisibleLineIDs(Set(response.trains.map(\.lineId)))
        let connectivity = PhaseConnectivityMonitor(initialStatus: .offline)
        let viewModel = MainViewModel(
            repository: repository,
            preferences: preferences,
            connectivityMonitor: connectivity
        )
        await viewModel.loadCachedDataIfNeeded()
        viewModel.selectedTrainID = response.trains.first?.id

        viewModel.activate()
        defer { viewModel.deactivate() }
        await Task.yield()

        XCTAssertTrue(viewModel.isOffline)
        XCTAssertTrue(viewModel.currentTrains.isEmpty)
        XCTAssertNil(viewModel.selectedTrainID)
        XCTAssertFalse(viewModel.canRetryTrainRequest)
        XCTAssertTrue(
            viewModel.trainRetrySuppressionMessage?.contains(
                "オフライン中は再送しません"
            ) == true
        )
        var trainRequestCount = await repository.trainRequestCount()
        var serviceRequestCount = await repository.serviceRequestCount()
        var communityRequestCount = await repository.communityRequestCount()
        XCTAssertEqual(trainRequestCount, 0)
        XCTAssertEqual(serviceRequestCount, 0)
        XCTAssertEqual(communityRequestCount, 0)

        connectivity.send(.online)
        for _ in 0..<100 {
            trainRequestCount = await repository.trainRequestCount()
            serviceRequestCount = await repository.serviceRequestCount()
            communityRequestCount = await repository.communityRequestCount()
            if trainRequestCount == 1,
               serviceRequestCount == 1,
               communityRequestCount == 1 {
                break
            }
            await Task.yield()
        }

        XCTAssertFalse(viewModel.isOffline)
        XCTAssertEqual(trainRequestCount, 1)
        XCTAssertEqual(serviceRequestCount, 1)
        XCTAssertEqual(communityRequestCount, 1)
        XCTAssertFalse(viewModel.currentTrains.isEmpty)

        viewModel.selectedTrainID = response.trains.first?.id
        connectivity.send(.offline)
        for _ in 0..<100 where !viewModel.isOffline {
            await Task.yield()
        }
        XCTAssertTrue(viewModel.isOffline)
        XCTAssertTrue(viewModel.currentTrains.isEmpty)
        XCTAssertNil(viewModel.selectedTrainID)
    }

    func testCachedRailwaysAreRefreshedBeforeSelectedLinePolling() async throws {
        let response = try TestFixture.trainsResponse
        let railways = try TestFixture.railwaysResponse
        let repository = PhaseRecordingRepository(
            trainsResponse: response,
            cachedRailways: railways
        )
        let preferences = makePreferences()
        let selectedIDs = Set(railways.selectableOptions.prefix(2).map(\.id))
        preferences.setVisibleLineIDs(selectedIDs)
        let viewModel = MainViewModel(
            repository: repository,
            preferences: preferences,
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        await viewModel.loadCachedDataIfNeeded()
        viewModel.activate()
        defer { viewModel.deactivate() }

        for _ in 0..<100 {
            let railwayCount = await repository.railwayRequestCount()
            let trainCount = await repository.trainRequestCount()
            let serviceCount = await repository.serviceRequestCount()
            if railwayCount == 1, trainCount == 1, serviceCount == 1 {
                break
            }
            await Task.yield()
        }

        let railwayCount = await repository.railwayRequestCount()
        let trainCount = await repository.trainRequestCount()
        let serviceCount = await repository.serviceRequestCount()
        let trainLineIDs = await repository.recordedTrainLineIDs()
        let serviceLineIDs = await repository.recordedServiceLineIDs()
        XCTAssertEqual(railwayCount, 1)
        XCTAssertEqual(trainCount, 1)
        XCTAssertEqual(serviceCount, 1)
        XCTAssertEqual(trainLineIDs, selectedIDs)
        XCTAssertEqual(serviceLineIDs, selectedIDs)
    }

    func testRailwayFailureStopsPollingAndDirectRetryResumesIt() async throws {
        let repository = PhaseRecordingRepository(
            trainsResponse: try TestFixture.trainsResponse,
            railwayError: .serviceUnavailable(
                retryAfter: .now.addingTimeInterval(10),
                message: "準備中です"
            )
        )
        let viewModel = MainViewModel(
            repository: repository,
            preferences: makePreferences(),
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        viewModel.activate()
        defer { viewModel.deactivate() }
        for _ in 0..<100 {
            if await repository.railwayRequestCount() >= 1 {
                break
            }
            await Task.yield()
        }

        var railwayCount = await repository.railwayRequestCount()
        var trainCount = await repository.trainRequestCount()
        var serviceCount = await repository.serviceRequestCount()
        XCTAssertEqual(railwayCount, 1)
        XCTAssertEqual(trainCount, 0)
        XCTAssertEqual(serviceCount, 0)
        XCTAssertTrue(viewModel.canRetryRailwayRequest)

        await repository.setRailwayError(nil)
        await viewModel.refreshRailways()
        for _ in 0..<100 {
            if await repository.trainRequestCount() >= 1,
               await repository.serviceRequestCount() >= 1 {
                break
            }
            await Task.yield()
        }

        railwayCount = await repository.railwayRequestCount()
        trainCount = await repository.trainRequestCount()
        serviceCount = await repository.serviceRequestCount()
        XCTAssertEqual(railwayCount, 2)
        XCTAssertEqual(trainCount, 1)
        XCTAssertEqual(serviceCount, 1)
    }

    func testRailwayRefreshCannotRunTwiceConcurrently() async throws {
        let repository = PhaseRecordingRepository(
            trainsResponse: try TestFixture.trainsResponse,
            railwayDelay: .milliseconds(100)
        )
        let viewModel = MainViewModel(
            repository: repository,
            preferences: makePreferences(),
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        let firstRefresh = Task {
            await viewModel.refreshRailways()
        }
        for _ in 0..<100 {
            if await repository.railwayRequestCount() == 1 {
                break
            }
            await Task.yield()
        }
        await viewModel.refreshRailways()
        await firstRefresh.value

        let requestCount = await repository.railwayRequestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testReactivationWaitsForCancelledRailwayRefreshThenRetries() async throws {
        let repository = PhaseRecordingRepository(
            trainsResponse: try TestFixture.trainsResponse,
            railwayDelay: .milliseconds(100)
        )
        let viewModel = MainViewModel(
            repository: repository,
            preferences: makePreferences(),
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        viewModel.activate()
        for _ in 0..<100 {
            if await repository.railwayRequestCount() == 1 {
                break
            }
            await Task.yield()
        }
        viewModel.deactivate()
        viewModel.activate()
        defer { viewModel.deactivate() }

        for _ in 0..<200 {
            if await repository.railwayRequestCount() >= 2,
               await repository.trainRequestCount() >= 1,
               await repository.serviceRequestCount() >= 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }

        let railwayCount = await repository.railwayRequestCount()
        let trainCount = await repository.trainRequestCount()
        let serviceCount = await repository.serviceRequestCount()
        XCTAssertEqual(railwayCount, 2)
        XCTAssertEqual(trainCount, 1)
        XCTAssertEqual(serviceCount, 1)
    }

    func testCommunitySubmissionCannotBeSentTwiceConcurrently() async throws {
        let community = try TestFixture.communityResponse
        let summary = try XCTUnwrap(community.summaries.first)
        let submitResponse = CommunityReportSubmitResponse(
            summaries: community.summaries,
            windowMinutes: community.windowMinutes,
            cooldownSeconds: community.cooldownSeconds,
            persistent: community.persistent,
            votingEnabled: community.votingEnabled,
            summary: summary
        )
        let repository = PhaseRecordingRepository(
            trainsResponse: try TestFixture.trainsResponse,
            submitResponse: submitResponse,
            submitDelay: .milliseconds(100)
        )
        let viewModel = MainViewModel(
            repository: repository,
            preferences: makePreferences(),
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        let firstSubmission = Task { @MainActor in
            await viewModel.submitCommunityReport(
                lineID: summary.lineId,
                status: .onTime,
                delayMinutes: nil
            )
        }
        for _ in 0..<100 {
            if await repository.submissionRequestCount() == 1 {
                break
            }
            await Task.yield()
        }
        let secondResult = await viewModel.submitCommunityReport(
            lineID: summary.lineId,
            status: .onTime,
            delayMinutes: nil
        )
        let firstResult = await firstSubmission.value
        let submissionCount = await repository.submissionRequestCount()

        XCTAssertTrue(firstResult)
        XCTAssertFalse(secondResult)
        XCTAssertEqual(submissionCount, 1)
    }

    func testCommunityRefreshCannotRunTwiceConcurrently() async throws {
        let repository = PhaseRecordingRepository(
            trainsResponse: try TestFixture.trainsResponse,
            communityDelay: .milliseconds(100)
        )
        let viewModel = MainViewModel(
            repository: repository,
            preferences: makePreferences(),
            connectivityMonitor: AssumedOnlineConnectivityMonitor()
        )

        let firstRefresh = Task {
            await viewModel.refreshCommunityReports()
        }
        for _ in 0..<100 {
            if await repository.communityRequestCount() == 1 {
                break
            }
            await Task.yield()
        }
        await viewModel.refreshCommunityReports()
        await firstRefresh.value

        let requestCount = await repository.communityRequestCount()
        XCTAssertEqual(requestCount, 1)
    }

    private func makePreferences() -> UserPreferences {
        UserPreferences(
            defaults: UserDefaults(
                suiteName: "phase-view-model-\(UUID().uuidString)"
            )!,
            secureStore: PhaseSecureStringStore()
        )
    }
}

private actor PhaseRecordingRepository: TrainRepository {
    private let trainsResponse: TrainsAPIResponse
    private let cachedTrains: TrainsAPIResponse?
    private let cachedRailways: RailwaysAPIResponse?
    private let trainError: APIClientError?
    private let serviceError: APIClientError?
    private var railwayError: APIClientError?
    private let submitResponse: CommunityReportSubmitResponse?
    private let railwayDelay: Duration?
    private let communityDelay: Duration?
    private let submitDelay: Duration?
    private var trainRequests: [Set<String>] = []
    private var serviceRequests: [Set<String>] = []
    private var railwayRequests = 0
    private var communityRequests = 0
    private var submissionRequests = 0

    init(
        trainsResponse: TrainsAPIResponse,
        cachedTrains: TrainsAPIResponse? = nil,
        cachedRailways: RailwaysAPIResponse? = nil,
        trainError: APIClientError? = nil,
        serviceError: APIClientError? = nil,
        railwayError: APIClientError? = nil,
        submitResponse: CommunityReportSubmitResponse? = nil,
        railwayDelay: Duration? = nil,
        communityDelay: Duration? = nil,
        submitDelay: Duration? = nil
    ) {
        self.trainsResponse = trainsResponse
        self.cachedTrains = cachedTrains
        self.cachedRailways = cachedRailways
        self.trainError = trainError
        self.serviceError = serviceError
        self.railwayError = railwayError
        self.submitResponse = submitResponse
        self.railwayDelay = railwayDelay
        self.communityDelay = communityDelay
        self.submitDelay = submitDelay
    }

    func loadCachedData() async -> CachedTrainData {
        CachedTrainData(
            trains: cachedTrains,
            serviceStatus: nil,
            railways: cachedRailways,
            communityReports: nil
        )
    }

    func refreshTrains(lineIDs: Set<String>) async throws -> TrainsAPIResponse {
        trainRequests.append(lineIDs)
        if let trainError {
            throw trainError
        }
        return trainsResponse
    }

    func refreshServiceStatus(
        lineIDs: Set<String>
    ) async throws -> ServiceStatusAPIResponse {
        serviceRequests.append(lineIDs)
        if let serviceError {
            throw serviceError
        }
        return try TestFixture.serviceResponse
    }

    func refreshRailways() async throws -> RailwaysAPIResponse {
        railwayRequests += 1
        if let railwayDelay {
            try await Task.sleep(for: railwayDelay)
        }
        if let railwayError {
            throw railwayError
        }
        return try TestFixture.railwaysResponse
    }

    func setRailwayError(_ error: APIClientError?) {
        railwayError = error
    }

    func refreshCommunityReports() async throws -> CommunityReportsAPIResponse {
        communityRequests += 1
        if let communityDelay {
            try await Task.sleep(for: communityDelay)
        }
        return try TestFixture.communityResponse
    }

    func submitCommunityReport(
        _ vote: CommunityReportVote,
        reporterID: String
    ) async throws -> CommunityReportSubmitResponse {
        submissionRequests += 1
        if let submitDelay {
            try await Task.sleep(for: submitDelay)
        }
        guard let submitResponse else {
            throw TestError.failed
        }
        return submitResponse
    }

    func recordedTrainLineIDs() -> Set<String>? { trainRequests.last }
    func recordedServiceLineIDs() -> Set<String>? { serviceRequests.last }
    func trainRequestCount() -> Int { trainRequests.count }
    func serviceRequestCount() -> Int { serviceRequests.count }
    func railwayRequestCount() -> Int { railwayRequests }
    func communityRequestCount() -> Int { communityRequests }
    func submissionRequestCount() -> Int { submissionRequests }
}

private final class PhaseSecureStringStore: SecureStringStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]

    func string(forKey key: String) throws -> String? {
        storage[key]
    }

    func set(_ value: String, forKey key: String) throws {
        storage[key] = value
    }

    func removeValue(forKey key: String) throws {
        storage.removeValue(forKey: key)
    }
}

private final class PhaseConnectivityMonitor: NetworkConnectivityMonitoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var status: NetworkConnectivityStatus
    private var continuation: AsyncStream<NetworkConnectivityStatus>.Continuation?

    init(initialStatus: NetworkConnectivityStatus) {
        status = initialStatus
    }

    var currentStatus: NetworkConnectivityStatus {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    func statusUpdates() -> AsyncStream<NetworkConnectivityStatus> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            let currentStatus = status
            lock.unlock()
            continuation.yield(currentStatus)
        }
    }

    func send(_ status: NetworkConnectivityStatus) {
        lock.lock()
        self.status = status
        let continuation = continuation
        lock.unlock()
        continuation?.yield(status)
    }
}
