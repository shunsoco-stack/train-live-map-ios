import Foundation

struct CachedTrainData: Sendable {
    let trains: TrainsAPIResponse?
    let serviceStatus: ServiceStatusAPIResponse?
    let railways: RailwaysAPIResponse?
    let communityReports: CommunityReportsAPIResponse?
}

protocol TrainRepository: Sendable {
    func loadCachedData() async -> CachedTrainData
    func refreshTrains() async throws -> TrainsAPIResponse
    func refreshServiceStatus() async throws -> ServiceStatusAPIResponse
    func refreshRailways() async throws -> RailwaysAPIResponse
    func refreshCommunityReports() async throws -> CommunityReportsAPIResponse
    func submitCommunityReport(
        _ vote: CommunityReportVote,
        reporterID: String
    ) async throws -> CommunityReportSubmitResponse
}

actor LiveTrainRepository: TrainRepository {
    private let api: TrainAPIService
    private let cache: ResponseCaching

    init(api: TrainAPIService, cache: ResponseCaching) {
        self.api = api
        self.cache = cache
    }

    init(configuration: AppConfiguration = .current) {
        api = URLSessionTrainAPIService(baseURL: configuration.apiBaseURL)
        cache = FileResponseCache()
    }

    func loadCachedData() async -> CachedTrainData {
        async let trains = cache.loadTrains()
        async let service = cache.loadServiceStatus()
        async let railways = cache.loadRailways()
        async let community = cache.loadCommunityReports()
        return await CachedTrainData(
            trains: trains,
            serviceStatus: service,
            railways: railways,
            communityReports: community
        )
    }

    func refreshTrains() async throws -> TrainsAPIResponse {
        let response = try await api.fetchTrains()
        await cache.saveTrains(response)
        return response
    }

    func refreshServiceStatus() async throws -> ServiceStatusAPIResponse {
        let response = try await api.fetchServiceStatus()
        await cache.saveServiceStatus(response)
        return response
    }

    func refreshRailways() async throws -> RailwaysAPIResponse {
        let response = try await api.fetchRailways()
        await cache.saveRailways(response)
        return response
    }

    func refreshCommunityReports() async throws -> CommunityReportsAPIResponse {
        let response = try await api.fetchCommunityReports()
        await cache.saveCommunityReports(response)
        return response
    }

    func submitCommunityReport(
        _ vote: CommunityReportVote,
        reporterID: String
    ) async throws -> CommunityReportSubmitResponse {
        let response = try await api.submitCommunityReport(
            vote,
            reporterID: reporterID
        )
        await cache.saveCommunityReports(response.reportsResponse)
        return response
    }
}
