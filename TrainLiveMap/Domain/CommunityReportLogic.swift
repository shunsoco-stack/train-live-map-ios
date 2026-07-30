import Foundation

enum CommunityReportLogic {
    static let reportWindow: TimeInterval = 30 * 60
    static let spikeWindow: TimeInterval = 5 * 60
    static let minimumSuspensionReports = 3
    static let minimumSuspensionShare = 0.6

    static func validatedVote(
        lineID: String,
        status: CommunityReportStatus,
        delayMinutes: Int?
    ) -> CommunityReportVote? {
        let trimmedLineID = lineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLineID.isEmpty else {
            return nil
        }
        if status == .delayed {
            guard let delayMinutes, (1...120).contains(delayMinutes) else {
                return nil
            }
            return CommunityReportVote(
                lineId: trimmedLineID,
                status: status,
                delayMinutes: delayMinutes
            )
        }
        return CommunityReportVote(
            lineId: trimmedLineID,
            status: status,
            delayMinutes: nil
        )
    }

    static func aggregate(
        _ reports: [CommunityReportRecord],
        now: Date = .now
    ) -> [CommunityReportSummary] {
        let cutoff = now.addingTimeInterval(-reportWindow)
        let active = reports.filter {
            $0.createdAt >= cutoff && $0.createdAt <= now
        }
        let grouped = Dictionary(grouping: active, by: \.lineId)

        return grouped.map { lineID, lineReports in
            let counts = CommunityReportCounts(
                onTime: lineReports.filter { $0.status == .onTime }.count,
                delayed: lineReports.filter { $0.status == .delayed }.count,
                suspended: lineReports.filter { $0.status == .suspended }.count
            )
            let candidates: [(CommunityReportStatus, Int)] = [
                (.onTime, counts.onTime),
                (.delayed, counts.delayed),
                (.suspended, counts.suspended)
            ]
            let status = candidates.max {
                if $0.1 == $1.1 {
                    return $0.0.severityPriority < $1.0.severityPriority
                }
                return $0.1 < $1.1
            }?.0 ?? .onTime
            let delayedValues = lineReports
                .filter { $0.status == .delayed }
                .compactMap(\.delayMinutes)

            return CommunityReportSummary(
                lineId: lineID,
                status: status,
                delayMinutes: status == .delayed ? median(delayedValues) : nil,
                voteCount: lineReports.count,
                counts: counts,
                updatedAt: lineReports.map(\.createdAt).max() ?? now
            )
        }
        .sorted { $0.lineId < $1.lineId }
    }

    static func detectSuspensionSpike(
        reports: [CommunityReportRecord],
        lineID: String,
        now: Date = .now
    ) -> SuspensionSpikeResult {
        let recent = latestReportsByReporter(
            reports: reports,
            lineID: lineID,
            after: now.addingTimeInterval(-spikeWindow),
            through: now
        )
        let previous = latestReportsByReporter(
            reports: reports,
            lineID: lineID,
            after: now.addingTimeInterval(-spikeWindow * 2),
            through: now.addingTimeInterval(-spikeWindow)
        )
        let recentSuspended = recent.filter { $0.status == .suspended }.count
        let previousSuspended = previous.filter { $0.status == .suspended }.count
        let recentTotal = recent.count
        let share = recentTotal == 0
            ? 0
            : Double(recentSuspended) / Double(recentTotal)
        let required = max(
            minimumSuspensionReports,
            previousSuspended * 2,
            previousSuspended + 2
        )

        return SuspensionSpikeResult(
            detected: recentSuspended >= required && share >= minimumSuspensionShare,
            recentSuspended: recentSuspended,
            recentTotal: recentTotal,
            previousSuspended: previousSuspended,
            requiredSuspended: required,
            suspendedShare: share
        )
    }

    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Int(
                (
                    (Double(sorted[middle - 1]) + Double(sorted[middle])) / 2
                ).rounded()
            )
        }
        return sorted[middle]
    }

    private static func latestReportsByReporter(
        reports: [CommunityReportRecord],
        lineID: String,
        after: Date,
        through: Date
    ) -> [CommunityReportRecord] {
        reports
            .filter {
                $0.lineId == lineID
                    && $0.createdAt > after
                    && $0.createdAt <= through
            }
            .reduce(into: [String: CommunityReportRecord]()) { result, report in
                if let previous = result[report.reporterHash],
                   previous.createdAt >= report.createdAt {
                    return
                }
                result[report.reporterHash] = report
            }
            .map(\.value)
    }
}
