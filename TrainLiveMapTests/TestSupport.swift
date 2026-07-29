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
}

private final class FixtureToken {}

final class StubAPIService: TrainAPIService, @unchecked Sendable {
    var trainsResult: Result<TrainsAPIResponse, Error>
    var serviceResult: Result<ServiceStatusAPIResponse, Error>
    var railwaysResult: Result<RailwaysAPIResponse, Error>

    init(
        trainsResult: Result<TrainsAPIResponse, Error>,
        serviceResult: Result<ServiceStatusAPIResponse, Error> = .failure(TestError.failed),
        railwaysResult: Result<RailwaysAPIResponse, Error> = .failure(TestError.failed)
    ) {
        self.trainsResult = trainsResult
        self.serviceResult = serviceResult
        self.railwaysResult = railwaysResult
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
}

actor MemoryResponseCache: ResponseCaching {
    var trains: TrainsAPIResponse?
    var service: ServiceStatusAPIResponse?
    var railways: RailwaysAPIResponse?

    init(
        trains: TrainsAPIResponse? = nil,
        service: ServiceStatusAPIResponse? = nil,
        railways: RailwaysAPIResponse? = nil
    ) {
        self.trains = trains
        self.service = service
        self.railways = railways
    }

    func loadTrains() async -> TrainsAPIResponse? { trains }
    func loadServiceStatus() async -> ServiceStatusAPIResponse? { service }
    func loadRailways() async -> RailwaysAPIResponse? { railways }
    func saveTrains(_ response: TrainsAPIResponse) async { trains = response }
    func saveServiceStatus(_ response: ServiceStatusAPIResponse) async { service = response }
    func saveRailways(_ response: RailwaysAPIResponse) async { railways = response }
}

enum TestError: LocalizedError {
    case failed

    var errorDescription: String? {
        "テスト用の通信失敗"
    }
}
