import XCTest
@testable import TrainLiveMap

final class CommunityReportLogicTests: XCTestCase {
    func testVoteValidationRequiresDelayMinutesOnlyForDelayed() {
        XCTAssertNil(
            CommunityReportLogic.validatedVote(
                lineID: "tokaido",
                status: .delayed,
                delayMinutes: nil
            )
        )
        XCTAssertNil(
            CommunityReportLogic.validatedVote(
                lineID: "tokaido",
                status: .delayed,
                delayMinutes: 121
            )
        )
        XCTAssertEqual(
            CommunityReportLogic.validatedVote(
                lineID: "tokaido",
                status: .onTime,
                delayMinutes: 30
            )?.delayMinutes,
            nil
        )
    }

    func testThirtyMinuteAggregationUsesMedianAndHigherSeverityTieBreak() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let reports = [
            report(.onTime, nil, "a", -60, now),
            report(.onTime, nil, "b", -120, now),
            report(.delayed, 4, "c", -180, now),
            report(.delayed, 10, "d", -240, now),
            report(.suspended, nil, "old", -1_900, now)
        ]

        let summary = try XCTUnwrap(
            CommunityReportLogic.aggregate(reports, now: now).first
        )
        XCTAssertEqual(summary.status, .delayed)
        XCTAssertEqual(summary.delayMinutes, 7)
        XCTAssertEqual(summary.voteCount, 4)
        XCTAssertEqual(summary.counts.onTime, 2)
        XCTAssertEqual(summary.counts.delayed, 2)
    }

    func testSuspensionSpikeUsesUniqueLatestReporterAndThresholds() {
        let now = Date(timeIntervalSince1970: 20_000)
        let reports = [
            report(.suspended, nil, "a", -60, now),
            report(.onTime, nil, "a", -50, now),
            report(.suspended, nil, "b", -40, now),
            report(.suspended, nil, "c", -30, now),
            report(.suspended, nil, "d", -20, now),
            report(.onTime, nil, "e", -10, now)
        ]

        let result = CommunityReportLogic.detectSuspensionSpike(
            reports: reports,
            lineID: "tokaido",
            now: now
        )
        XCTAssertTrue(result.detected)
        XCTAssertEqual(result.recentSuspended, 3)
        XCTAssertEqual(result.recentTotal, 5)
        XCTAssertEqual(result.suspendedShare, 0.6, accuracy: 0.000_001)
    }

    func testPreviousWindowRequiresDoublingAndCooldownEquivalent() {
        let now = Date(timeIntervalSince1970: 30_000)
        let reports = [
            report(.suspended, nil, "old-a", -500, now),
            report(.suspended, nil, "old-b", -400, now),
            report(.suspended, nil, "new-a", -100, now),
            report(.suspended, nil, "new-b", -90, now),
            report(.suspended, nil, "new-c", -80, now)
        ]

        let result = CommunityReportLogic.detectSuspensionSpike(
            reports: reports,
            lineID: "tokaido",
            now: now
        )
        XCTAssertFalse(result.detected)
        XCTAssertEqual(result.requiredSuspended, 4)
    }

    private func report(
        _ status: CommunityReportStatus,
        _ delay: Int?,
        _ reporter: String,
        _ seconds: TimeInterval,
        _ now: Date
    ) -> CommunityReportRecord {
        CommunityReportRecord(
            lineId: "tokaido",
            status: status,
            delayMinutes: delay,
            reporterHash: reporter,
            createdAt: now.addingTimeInterval(seconds)
        )
    }
}
