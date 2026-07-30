import Foundation

protocol ResponseCaching: Sendable {
    func loadTrains() async -> TrainsAPIResponse?
    func loadServiceStatus() async -> ServiceStatusAPIResponse?
    func loadRailways() async -> RailwaysAPIResponse?
    func loadCommunityReports() async -> CommunityReportsAPIResponse?
    func saveTrains(_ response: TrainsAPIResponse) async
    func saveServiceStatus(_ response: ServiceStatusAPIResponse) async
    func saveRailways(_ response: RailwaysAPIResponse) async
    func saveCommunityReports(_ response: CommunityReportsAPIResponse) async
}

actor FileResponseCache: ResponseCaching {
    private enum Filename {
        static let trains = "trains.json"
        static let serviceStatus = "service-status.json"
        static let railways = "railways.json"
        static let communityReports = "community-reports.json"
    }

    private let directoryURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder.trainLiveMap
    private let encoder = JSONEncoder.trainLiveMap

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let base = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.directoryURL = base
                .appendingPathComponent("TrainLiveMap", isDirectory: true)
                .appendingPathComponent("Cache", isDirectory: true)
        }
    }

    func loadTrains() async -> TrainsAPIResponse? {
        load(TrainsAPIResponse.self, filename: Filename.trains)
    }

    func loadServiceStatus() async -> ServiceStatusAPIResponse? {
        load(ServiceStatusAPIResponse.self, filename: Filename.serviceStatus)
    }

    func loadRailways() async -> RailwaysAPIResponse? {
        load(RailwaysAPIResponse.self, filename: Filename.railways)
    }

    func loadCommunityReports() async -> CommunityReportsAPIResponse? {
        load(
            CommunityReportsAPIResponse.self,
            filename: Filename.communityReports
        )
    }

    func saveTrains(_ response: TrainsAPIResponse) async {
        save(response, filename: Filename.trains)
    }

    func saveServiceStatus(_ response: ServiceStatusAPIResponse) async {
        save(response, filename: Filename.serviceStatus)
    }

    func saveRailways(_ response: RailwaysAPIResponse) async {
        save(response, filename: Filename.railways)
    }

    func saveCommunityReports(_ response: CommunityReportsAPIResponse) async {
        save(response, filename: Filename.communityReports)
    }

    private func load<Value: Decodable>(
        _ type: Value.Type,
        filename: String
    ) -> Value? {
        let url = directoryURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(type, from: data)
    }

    private func save<Value: Encodable>(
        _ value: Value,
        filename: String
    ) {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(value)
            try data.write(
                to: directoryURL.appendingPathComponent(filename),
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
        } catch {
            // Cache errors must not replace otherwise valid network data.
        }
    }
}
