import XCTest
@testable import TrainLiveMap

final class ServiceStatusLogicTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_785_488_730)

    func testResumedOperationIsTreatedAsDelay() {
        let result = ServiceStatusLogic.normalizedOfficialStatus(
            status(
                severity: .major,
                message: "運転を見合わせていましたが、運転を再開しました。"
            )
        )

        XCTAssertEqual(result.severity, .minor)
    }

    func testOnlyCurrentSuspensionWordingBecomesMajor() {
        XCTAssertEqual(
            ServiceStatusLogic.classifySeverity(
                from: "人身事故の影響で、上下線で運転を見合わせています。"
            ),
            .major
        )
        XCTAssertEqual(
            ServiceStatusLogic.classifySeverity(
                from: "運転見合わせの影響で一部列車に遅れがあります。"
            ),
            .minor
        )
    }

    func testExplicitOfficialDisruptionWinsOverTrainFallback() {
        let official = status(
            severity: .minor,
            message: "一部列車に遅れがでています。"
        )
        let result = ServiceStatusLogic.statusWithTrainDelayFallback(
            official,
            trains: [train(id: "large-delay", delay: 72)],
            now: now
        )

        XCTAssertEqual(result, official)
        XCTAssertEqual(result.dataAccuracy, .actual)
    }

    func testFreshTrainDelayPreventsNormalDisplay() {
        let result = ServiceStatusLogic.statusWithTrainDelayFallback(
            status(),
            trains: [train(id: "delay", delay: 8)],
            now: now
        )

        XCTAssertEqual(result.severity, .minor)
        XCTAssertEqual(result.dataAccuracy, .estimated)
        XCTAssertEqual(
            result.message,
            "列車位置情報では最大8分程度の遅れが確認されています。"
        )
    }

    func testEmptyOfficialMessageUsesFreshTrainFallback() {
        let result = ServiceStatusLogic.statusWithTrainDelayFallback(
            status(message: ""),
            trains: [train(id: "delay", delay: 6)],
            now: now
        )

        XCTAssertEqual(result.severity, .minor)
        XCTAssertEqual(result.dataAccuracy, .estimated)
    }

    func testBackendMajorDelayClassificationIsNotDowngraded() {
        let backendStatus = ServiceStatus(
            lineId: "saikyo",
            lineName: "埼京線",
            severity: .major,
            message: "列車位置情報では最大72分の大幅な遅れが確認されています。公式の運行情報もあわせてご確認ください。",
            updatedAt: now.addingTimeInterval(-20),
            dataAccuracy: .estimated
        )

        XCTAssertEqual(
            ServiceStatusLogic.normalizedOfficialStatus(backendStatus),
            backendStatus
        )
    }

    func testMaximumThirtyMinutesIsMajorDelay() {
        let result = ServiceStatusLogic.statusWithTrainDelayFallback(
            status(),
            trains: [
                train(id: "major", delay: 30),
                train(id: "normal", delay: 0)
            ],
            now: now
        )

        XCTAssertEqual(result.severity, .major)
        XCTAssertEqual(
            result.message,
            "列車位置情報では最大30分の大幅な遅れが確認されています。公式の運行情報もあわせてご確認ください。"
        )
    }

    func testHalfOfRecentTrainsAtLeastFifteenMinutesIsMajorDelay() {
        let result = ServiceStatusLogic.statusWithTrainDelayFallback(
            status(),
            trains: [
                train(id: "delay-1", delay: 18),
                train(id: "delay-2", delay: 15),
                train(id: "normal-1", delay: 0),
                train(id: "normal-2", delay: 0)
            ],
            now: now
        )

        XCTAssertEqual(result.severity, .major)
    }

    func testFewerThanHalfAtFifteenMinutesStaysMinor() {
        let result = ServiceStatusLogic.statusWithTrainDelayFallback(
            status(),
            trains: [
                train(id: "large", delay: 20),
                train(id: "small", delay: 3),
                train(id: "normal-1", delay: 0),
                train(id: "normal-2", delay: 0)
            ],
            now: now
        )

        XCTAssertEqual(result.severity, .minor)
    }

    func testOlderThanTwoMinutesIsNotUsed() {
        let result = ServiceStatusLogic.statusWithTrainDelayFallback(
            status(),
            trains: [
                train(
                    id: "old",
                    delay: 60,
                    updatedAt: now.addingTimeInterval(-121)
                )
            ],
            now: now
        )

        XCTAssertEqual(result, status())
    }

    func testTrainDelayNeverClaimsSuspension() {
        let result = ServiceStatusLogic.statusWithTrainDelayFallback(
            status(),
            trains: [train(id: "large", delay: 45)],
            now: now
        )

        XCTAssertEqual(result.severity, .major)
        XCTAssertFalse(result.message.contains("見合わせ"))
        XCTAssertTrue(result.message.contains("大幅な遅れ"))
    }

    private func status(
        severity: ServiceSeverity = .normal,
        message: String = "平常どおり運転しています。"
    ) -> ServiceStatus {
        ServiceStatus(
            lineId: "saikyo",
            lineName: "埼京線",
            severity: severity,
            message: message,
            updatedAt: now.addingTimeInterval(-20),
            dataAccuracy: .actual
        )
    }

    private func train(
        id: String,
        delay: Int,
        updatedAt: Date? = nil
    ) -> TrainLocation {
        TrainLocation(
            id: id,
            lineId: "saikyo",
            lineName: "埼京線",
            lineColor: "#00ac9a",
            trainNumber: nil,
            direction: .inbound,
            destination: "大宮",
            trainType: .local,
            latitude: 35.7,
            longitude: 139.7,
            delayMinutes: delay,
            speedKmh: 0,
            status: delay > 0 ? .delayed : .running,
            lastUpdatedAt: updatedAt ?? now.addingTimeInterval(-30),
            stoppedSince: nil,
            dataAccuracy: .actual,
            routeSegment: nil
        )
    }
}
