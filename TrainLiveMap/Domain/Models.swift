import Foundation

struct MapCoordinate: Codable, Hashable, Sendable {
    let longitude: Double
    let latitude: Double

    init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        longitude = try container.decode(Double.self)
        latitude = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(longitude)
        try container.encode(latitude)
    }

    var isFinite: Bool {
        longitude.isFinite && latitude.isFinite
    }
}

enum TrainDirection: String, Codable, CaseIterable, Sendable {
    case inbound
    case outbound

    var label: String {
        switch self {
        case .inbound: "上り"
        case .outbound: "下り"
        }
    }

    var symbol: String {
        switch self {
        case .inbound: "↑"
        case .outbound: "↓"
        }
    }

    var displayText: String {
        "\(symbol) \(label)"
    }
}

enum TrainStatus: String, Codable, CaseIterable, Sendable {
    case running
    case stopped
    case delayed
    case suspended
    case unknown

    var label: String {
        switch self {
        case .running: "走行中"
        case .stopped: "停車中"
        case .delayed: "遅延"
        case .suspended: "運転見合わせ"
        case .unknown: "不明"
        }
    }
}

enum DataAccuracy: String, Codable, CaseIterable, Sendable {
    case actual
    case estimated
    case mock

    var label: String {
        switch self {
        case .actual: "実データ"
        case .estimated: "推定データ（駅間推定）"
        case .mock: "モックデータ"
        }
    }

    var shortLabel: String {
        switch self {
        case .actual: "実データ"
        case .estimated: "推定"
        case .mock: "モック"
        }
    }
}

enum TrainType: String, Codable, Sendable {
    case local
    case rapid
    case specialRapid = "special_rapid"

    var label: String {
        switch self {
        case .local: "普通"
        case .rapid: "快速"
        case .specialRapid: "特別快速"
        }
    }
}

struct RouteSegmentEstimate: Codable, Equatable, Sendable {
    let fromFraction: Double
    let toFraction: Double
    let coordinates: [MapCoordinate]?
}

struct TrainLocation: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let lineId: String
    let lineName: String
    let lineColor: String
    let trainNumber: String?
    let direction: TrainDirection
    let destination: String
    let trainType: TrainType
    let latitude: Double
    let longitude: Double
    let delayMinutes: Int
    let speedKmh: Double
    let status: TrainStatus
    let lastUpdatedAt: Date
    let stoppedSince: Date?
    let dataAccuracy: DataAccuracy
    let routeSegment: RouteSegmentEstimate?
    /// Future-compatible station identifiers. The current Web API may omit both.
    let fromStation: String?
    let toStation: String?
    /// Raw ODPT rail direction when the backend elects to expose it.
    let railDirection: String?

    init(
        id: String,
        lineId: String,
        lineName: String,
        lineColor: String,
        trainNumber: String?,
        direction: TrainDirection,
        destination: String,
        trainType: TrainType,
        latitude: Double,
        longitude: Double,
        delayMinutes: Int,
        speedKmh: Double,
        status: TrainStatus,
        lastUpdatedAt: Date,
        stoppedSince: Date?,
        dataAccuracy: DataAccuracy,
        routeSegment: RouteSegmentEstimate?,
        fromStation: String? = nil,
        toStation: String? = nil,
        railDirection: String? = nil
    ) {
        self.id = id
        self.lineId = lineId
        self.lineName = lineName
        self.lineColor = lineColor
        self.trainNumber = trainNumber
        self.direction = direction
        self.destination = destination
        self.trainType = trainType
        self.latitude = latitude
        self.longitude = longitude
        self.delayMinutes = delayMinutes
        self.speedKmh = speedKmh
        self.status = status
        self.lastUpdatedAt = lastUpdatedAt
        self.stoppedSince = stoppedSince
        self.dataAccuracy = dataAccuracy
        self.routeSegment = routeSegment
        self.fromStation = fromStation
        self.toStation = toStation
        self.railDirection = railDirection
    }

    var coordinate: MapCoordinate {
        MapCoordinate(longitude: longitude, latitude: latitude)
    }

    var currentSegmentText: String {
        if let fromStation, let toStation, !fromStation.isEmpty, !toStation.isEmpty {
            return "\(fromStation)〜\(toStation)"
        }
        if routeSegment != nil || dataAccuracy == .estimated {
            return "駅間推定（駅名はAPI未提供）"
        }
        return "取得できません"
    }
}

enum ProviderSource: String, Codable, Sendable {
    case odpt
    case mock
}

struct TrainsAPIResponse: Codable, Equatable, Sendable {
    let trains: [TrainLocation]
    let generatedAt: Date
    let dataUpdatedAt: Date
    let isMock: Bool
    let source: ProviderSource
    let fallback: Bool
    let notice: String?
}

enum ServiceSeverity: String, Codable, Sendable {
    case normal
    case minor
    case major

    var label: String {
        switch self {
        case .normal: "平常"
        case .minor: "注意"
        case .major: "重要"
        }
    }
}

struct ServiceStatus: Codable, Identifiable, Equatable, Sendable {
    let lineId: String
    let lineName: String
    let severity: ServiceSeverity
    let message: String
    let updatedAt: Date
    let dataAccuracy: DataAccuracy

    var id: String { lineId }
}

struct ServiceStatusAPIResponse: Codable, Equatable, Sendable {
    let serviceStatus: ServiceStatus
    let serviceStatuses: [ServiceStatus]?
    let isMock: Bool
    let source: ProviderSource
    let fallback: Bool
    let notice: String?

    var allStatuses: [ServiceStatus] {
        guard let serviceStatuses, !serviceStatuses.isEmpty else {
            return [serviceStatus]
        }
        return serviceStatuses
    }
}

enum RailwayCoverage: String, Codable, CaseIterable, Sendable {
    case realtime
    case limited
    case unavailable
    case unknown

    var label: String {
        switch self {
        case .realtime: "リアルタイム対象"
        case .limited: "一部区間"
        case .unavailable: "位置情報対象外"
        case .unknown: "取得範囲確認中"
        }
    }
}

enum RailwayKind: String, Codable, Sendable {
    case line
    case service
}

struct RailwayMapLine: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let odptId: String
    let name: String
    let color: String
    let coordinates: [[MapCoordinate]]
}

struct RailwayFilterOption: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let category: String
    let color: String
    let aliases: [String]
    let coverage: RailwayCoverage
    let coverageNote: String?
    let kind: RailwayKind
    let available: Bool

    var isSelectable: Bool {
        available && coverage != .unavailable
    }

    var availabilityDescription: String {
        if !available {
            return "地図データを取得できません"
        }
        return coverageNote ?? coverage.label
    }
}

struct RailwaysAPIResponse: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case odpt
        case fallback
    }

    let lines: [RailwayMapLine]
    let options: [RailwayFilterOption]
    let generatedAt: Date
    let source: Source

    var selectableOptions: [RailwayFilterOption] {
        options.filter(\.isSelectable)
    }
}
