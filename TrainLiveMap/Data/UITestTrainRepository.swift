import Foundation

actor UITestTrainRepository: TrainRepository {
    private let now = Date(timeIntervalSince1970: 1_785_363_600)

    func loadCachedData() async -> CachedTrainData {
        CachedTrainData(
            trains: nil,
            serviceStatus: nil,
            railways: nil,
            communityReports: nil
        )
    }

    func refreshTrains() async throws -> TrainsAPIResponse {
        TrainsAPIResponse(
            trains: [
                train(
                    id: "ui-yamanote",
                    lineID: "yamanote",
                    lineName: "山手線",
                    color: "#9acd32",
                    direction: .inbound,
                    destination: "東京",
                    status: .running,
                    delay: 0,
                    longitude: 139.767
                ),
                train(
                    id: "ui-tokaido",
                    lineID: "tokaido",
                    lineName: "東海道線",
                    color: "#f68b1e",
                    direction: .outbound,
                    destination: "横浜",
                    status: .delayed,
                    delay: 3,
                    longitude: 139.72
                )
            ],
            generatedAt: now,
            dataUpdatedAt: now,
            isMock: false,
            source: .odpt,
            fallback: false,
            notice: nil
        )
    }

    func refreshServiceStatus() async throws -> ServiceStatusAPIResponse {
        let statuses = [
            ServiceStatus(
                lineId: "tokaido",
                lineName: "東海道線",
                severity: .minor,
                message: "一部列車に遅れが出ています。",
                updatedAt: now,
                dataAccuracy: .actual
            ),
            ServiceStatus(
                lineId: "yamanote",
                lineName: "山手線",
                severity: .normal,
                message: "平常どおり運転しています。",
                updatedAt: now,
                dataAccuracy: .actual
            )
        ]
        return ServiceStatusAPIResponse(
            serviceStatus: statuses[0],
            serviceStatuses: statuses,
            isMock: false,
            source: .odpt,
            fallback: false,
            notice: nil
        )
    }

    func refreshRailways() async throws -> RailwaysAPIResponse {
        let options = Self.options
        return RailwaysAPIResponse(
            lines: options.map { option in
                RailwayMapLine(
                    id: option.id,
                    odptId: "odpt.Railway:JR-East.\(option.id)",
                    name: option.name,
                    color: option.color,
                    coordinates: [[
                        MapCoordinate(longitude: 139.62, latitude: 35.58),
                        MapCoordinate(longitude: 139.77, latitude: 35.68),
                        MapCoordinate(longitude: 139.84, latitude: 35.74)
                    ]]
                )
            },
            options: options,
            generatedAt: now,
            source: .odpt
        )
    }

    func refreshCommunityReports() async throws -> CommunityReportsAPIResponse {
        communityResponse
    }

    func submitCommunityReport(
        _ vote: CommunityReportVote,
        reporterID: String
    ) async throws -> CommunityReportSubmitResponse {
        let summary = CommunityReportSummary(
            lineId: vote.lineId,
            status: vote.status,
            delayMinutes: vote.delayMinutes,
            voteCount: 1,
            counts: CommunityReportCounts(
                onTime: vote.status == .onTime ? 1 : 0,
                delayed: vote.status == .delayed ? 1 : 0,
                suspended: vote.status == .suspended ? 1 : 0
            ),
            updatedAt: now
        )
        return CommunityReportSubmitResponse(
            summaries: [summary],
            windowMinutes: 30,
            cooldownSeconds: 60,
            persistent: true,
            votingEnabled: true,
            summary: summary
        )
    }

    private var communityResponse: CommunityReportsAPIResponse {
        CommunityReportsAPIResponse(
            summaries: [
                CommunityReportSummary(
                    lineId: "tokaido",
                    status: .delayed,
                    delayMinutes: 5,
                    voteCount: 3,
                    counts: CommunityReportCounts(
                        onTime: 1,
                        delayed: 2,
                        suspended: 0
                    ),
                    updatedAt: now
                )
            ],
            windowMinutes: 30,
            cooldownSeconds: 60,
            persistent: true,
            votingEnabled: true
        )
    }

    private func train(
        id: String,
        lineID: String,
        lineName: String,
        color: String,
        direction: TrainDirection,
        destination: String,
        status: TrainStatus,
        delay: Int,
        longitude: Double
    ) -> TrainLocation {
        TrainLocation(
            id: id,
            lineId: lineID,
            lineName: lineName,
            lineColor: color,
            trainNumber: nil,
            direction: direction,
            destination: destination,
            trainType: .local,
            latitude: 35.68,
            longitude: longitude,
            delayMinutes: delay,
            speedKmh: status == .running ? 55 : 0,
            status: status,
            lastUpdatedAt: now,
            stoppedSince: nil,
            dataAccuracy: .estimated,
            routeSegment: nil,
            fromStation: "品川駅",
            toStation: "新橋駅"
        )
    }

    private static let options: [RailwayFilterOption] = [
        option("yamanote", "山手線", "山手線", "#9acd32"),
        option("shonan-shinjuku", "湘南新宿ライン", "直通系統", "#e21f26"),
        option("tokaido", "東海道線", "東海道方面", "#f68b1e"),
        option("utsunomiya", "宇都宮線", "東北・高崎方面", "#f68b1e"),
        option("chuo-rapid", "中央線快速電車", "中央方面", "#f15a22"),
        option("joban", "常磐線", "常磐方面", "#00a68c", note: "羽鳥駅以南のみ"),
        option("sobu-rapid", "総武快速線", "総武方面", "#0067c0")
    ]

    private static func option(
        _ id: String,
        _ name: String,
        _ category: String,
        _ color: String,
        note: String? = nil
    ) -> RailwayFilterOption {
        RailwayFilterOption(
            id: id,
            name: name,
            category: category,
            color: color,
            aliases: [],
            coverage: note == nil ? .realtime : .limited,
            coverageNote: note,
            kind: .line,
            available: true
        )
    }
}
