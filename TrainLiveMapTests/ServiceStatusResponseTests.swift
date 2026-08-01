import XCTest
@testable import TrainLiveMap

final class ServiceStatusResponseTests: XCTestCase {
    func testExplicitEmptyStatusesRemainEmpty() {
        let response = makeResponse(serviceStatuses: [])

        XCTAssertTrue(response.allStatuses.isEmpty)
    }

    func testMissingStatusesUsesLegacySingleton() {
        let response = makeResponse(serviceStatuses: nil)

        XCTAssertEqual(response.allStatuses, [response.serviceStatus])
    }

    private func makeResponse(
        serviceStatuses: [ServiceStatus]?
    ) -> ServiceStatusAPIResponse {
        ServiceStatusAPIResponse(
            serviceStatus: ServiceStatus(
                lineId: "legacy-line",
                lineName: "互換用路線",
                severity: .normal,
                message: "平常です。",
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                dataAccuracy: .actual
            ),
            serviceStatuses: serviceStatuses,
            isMock: false,
            source: .odpt,
            fallback: false,
            notice: nil
        )
    }
}
