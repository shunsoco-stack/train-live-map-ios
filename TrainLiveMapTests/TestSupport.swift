import Foundation
@testable import TrainLiveMap

enum TestFixture {
    static func data(named name: String) throws -> Data {
        let bundle = Bundle(for: FixtureToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static var trainsResponse: TrainsAPIResponse {
        get throws {
            try JSONDecoder.trainLiveMap.decode(
                TrainsAPIResponse.self,
                from: data(named: "trains")
            )
        }
    }

    static var serviceResponse: ServiceStatusAPIResponse {
        get throws {
            try JSONDecoder.trainLiveMap.decode(
                ServiceStatusAPIResponse.self,
                from: data(named: "service-status")
            )
        }
    }

    static var railwaysResponse: RailwaysAPIResponse {
        get throws {
            try JSONDecoder.trainLiveMap.decode(
                RailwaysAPIResponse.self,
                from: data(named: "railways")
            )
        }
    }

    static var communityResponse: CommunityReportsAPIResponse {
        get throws {
            try JSONDecoder.trainLiveMap.decode(
                CommunityReportsAPIResponse.self,
                from: data(named: "community-reports")
            )
        }
    }
}

private final class FixtureToken {}

final class StubAPIService: TrainAPIService, @unchecked Sendable {
    var trainsResult: Result<TrainsAPIResponse, Error>
    var serviceResult: Result<ServiceStatusAPIResponse, Error>
    var railwaysResult: Result<RailwaysAPIResponse, Error>
    var communityResult: Result<CommunityReportsAPIResponse, Error>
    var submitCommunityResult: Result<CommunityReportSubmitResponse, Error>

    init(
        trainsResult: Result<TrainsAPIResponse, Error>,
        serviceResult: Result<ServiceStatusAPIResponse, Error> = .failure(TestError.failed),
        railwaysResult: Result<RailwaysAPIResponse, Error> = .failure(TestError.failed),
        communityResult: Result<CommunityReportsAPIResponse, Error> = .failure(TestError.failed),
        submitCommunityResult: Result<CommunityReportSubmitResponse, Error> = .failure(TestError.failed)
    ) {
        self.trainsResult = trainsResult
        self.serviceResult = serviceResult
        self.railwaysResult = railwaysResult
        self.communityResult = communityResult
        self.submitCommunityResult = submitCommunityResult
    }

    func fetchTrains() async throws -> TrainsAPIResponse {
        try trainsResult.get()
    }

    func fetchServiceStatus() async throws -> ServiceStatusAPIResponse {
        try serviceResult.get()
    }

    func fetchRailways() async throws -> RailwaysAPIResponse {
        try railwaysResult.get()
    }

    func fetchCommunityReports() async throws -> CommunityReportsAPIResponse {
        try communityResult.get()
    }

    func submitCommunityReport(
        _ vote: CommunityReportVote,
        reporterID: String
    ) async throws -> CommunityReportSubmitResponse {
        try submitCommunityResult.get()
    }
}

actor MemoryResponseCache: ResponseCaching {
    var trains: TrainsAPIResponse?
    var service: ServiceStatusAPIResponse?
    var railways: RailwaysAPIResponse?
    var community: CommunityReportsAPIResponse?

    init(
        trains: TrainsAPIResponse? = nil,
        service: ServiceStatusAPIResponse? = nil,
        railways: RailwaysAPIResponse? = nil,
        community: CommunityReportsAPIResponse? = nil
    ) {
        self.trains = trains
        self.service = service
        self.railways = railways
        self.community = community
    }

    func loadTrains() async -> TrainsAPIResponse? { trains }
    func loadServiceStatus() async -> ServiceStatusAPIResponse? { service }
    func loadRailways() async -> RailwaysAPIResponse? { railways }
    func loadCommunityReports() async -> CommunityReportsAPIResponse? {
        community
    }
    func saveTrains(_ response: TrainsAPIResponse) async { trains = response }
    func saveServiceStatus(_ response: ServiceStatusAPIResponse) async { service = response }
    func saveRailways(_ response: RailwaysAPIResponse) async { railways = response }
    func saveCommunityReports(
        _ response: CommunityReportsAPIResponse
    ) async {
        community = response
    }
}

enum TestError: LocalizedError {
    case failed

    var errorDescription: String? {
        "テスト用の通信失敗"
    }
}

enum TestRequestBody {
    static func data(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else {
                return nil
            }
            guard count > 0 else {
                return data
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
