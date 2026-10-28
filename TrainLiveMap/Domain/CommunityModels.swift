import Foundation

enum CommunityReportStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case onTime = "on-time"
    case delayed
    case suspended

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onTime: "平常"
        case .delayed: "遅延"
        case .suspended: "運転見合わせ"
        }
    }

    var systemImage: String {
        switch self {
        case .onTime: "checkmark.circle.fill"
        case .delayed: "exclamationmark.clock.fill"
        case .suspended: "xmark.octagon.fill"
        }
    }

    var severityPriority: Int {
        switch self {
        case .onTime: 0
        case .delayed: 1
        case .suspended: 2
        }
    }
}

struct CommunityReportVote: Codable, Equatable, Sendable {
    let lineId: String
    let status: CommunityReportStatus
    let delayMinutes: Int?
    var event: String? = nil
}

struct CommunityReportRecord: Codable, Equatable, Sendable {
    let lineId: String
    let status: CommunityReportStatus
    let delayMinutes: Int?
    let reporterHash: String
    let createdAt: Date
}

struct CommunityReportCounts: Codable, Equatable, Sendable {
    let onTime: Int
    let delayed: Int
    let suspended: Int
}

struct CommunityReportSummary: Codable, Identifiable, Equatable, Sendable {
    let lineId: String
    let status: CommunityReportStatus
    let delayMinutes: Int?
    let voteCount: Int
    var resumedCount: Int? = nil
    let counts: CommunityReportCounts
    let updatedAt: Date

    var id: String { lineId }
}

struct CommunityReportsAPIResponse: Codable, Equatable, Sendable {
    let summaries: [CommunityReportSummary]
    let windowMinutes: Int
    let cooldownSeconds: Int
    let persistent: Bool
    let votingEnabled: Bool
}

struct CommunityReportSubmitResponse: Codable, Equatable, Sendable {
    let summaries: [CommunityReportSummary]
    let windowMinutes: Int
    let cooldownSeconds: Int
    let persistent: Bool
    let votingEnabled: Bool
    let summary: CommunityReportSummary

    var reportsResponse: CommunityReportsAPIResponse {
        CommunityReportsAPIResponse(
            summaries: summaries,
            windowMinutes: windowMinutes,
            cooldownSeconds: cooldownSeconds,
            persistent: persistent,
            votingEnabled: votingEnabled
        )
    }
}

struct SuspensionSpikeResult: Equatable, Sendable {
    let detected: Bool
    let recentSuspended: Int
    let recentTotal: Int
    let previousSuspended: Int
    let requiredSuspended: Int
    let suspendedShare: Double
}
