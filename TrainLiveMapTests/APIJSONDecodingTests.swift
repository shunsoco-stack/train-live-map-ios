import XCTest
@testable import TrainLiveMap

final class APIJSONDecodingTests: XCTestCase {
    func testDecodesTrainsResponseAndRouteSegment() throws {
        let response = try TestFixture.trainsResponse

        XCTAssertEqual(response.trains.count, 3)
        XCTAssertFalse(response.isMock)
        XCTAssertEqual(response.source, .odpt)
        XCTAssertFalse(response.fallback)

        let train = try XCTUnwrap(response.trains.first)
        XCTAssertEqual(train.id, "train-normal")
        XCTAssertEqual(train.direction, .outbound)
        XCTAssertEqual(train.trainType, .local)
        XCTAssertEqual(train.status, .running)
        XCTAssertEqual(train.dataAccuracy, .estimated)
        XCTAssertEqual(train.routeSegment?.fromFraction, 0.2)
        XCTAssertEqual(train.routeSegment?.toFraction, 0.4)
        XCTAssertEqual(train.routeSegment?.coordinates?.count, 2)
        let firstLongitude = try XCTUnwrap(
            train.routeSegment?.coordinates?.first?.longitude
        )
        XCTAssertEqual(firstLongitude, 139.7671, accuracy: 0.000_001)
    }

    func testDecodesServiceStatusResponse() throws {
        let response = try TestFixture.serviceResponse

        XCTAssertEqual(response.serviceStatus.lineId, "tokaido")
        XCTAssertEqual(response.serviceStatus.severity, .minor)
        XCTAssertEqual(response.serviceStatus.dataAccuracy, .actual)
        XCTAssertEqual(response.serviceStatus.message, "一部列車に遅れが出ています")
        XCTAssertEqual(response.allStatuses.count, 2)
    }

    func testDecodesRailwayLinesOptionsAvailabilityAndCoverage() throws {
        let response = try TestFixture.railwaysResponse

        XCTAssertEqual(response.lines.count, 1)
        XCTAssertEqual(response.options.count, 3)
        XCTAssertEqual(response.source, .odpt)
        XCTAssertEqual(response.lines.first?.color, "#f68b1e")
        let unavailable = try XCTUnwrap(
            response.options.first { $0.id == "sagami" }
        )
        XCTAssertFalse(unavailable.available)
        XCTAssertEqual(unavailable.coverage, .unavailable)
        XCTAssertEqual(unavailable.coverageNote, "ODPT列車位置情報の対象外")
        XCTAssertEqual(response.selectableOptions.map(\.id), ["tokaido", "chuo-rapid"])
    }

    func testDecodesCommunityReportsResponse() throws {
        let response = try TestFixture.communityResponse

        XCTAssertEqual(response.windowMinutes, 30)
        XCTAssertEqual(response.cooldownSeconds, 60)
        XCTAssertTrue(response.persistent)
        XCTAssertTrue(response.votingEnabled)
        XCTAssertEqual(response.summaries.first?.status, .delayed)
        XCTAssertEqual(response.summaries.first?.delayMinutes, 7)
    }
}
