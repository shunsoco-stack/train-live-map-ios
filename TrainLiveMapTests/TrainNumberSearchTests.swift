import XCTest
@testable import TrainLiveMap

final class TrainNumberSearchTests: XCTestCase {
    func testSearchUsesTrimmedCaseInsensitivePrefix() throws {
        let trains = try TestFixture.trainsResponse.trains

        XCTAssertEqual(
            TrainNumberSearchLogic.results(
                in: trains,
                query: "  123m  "
            ).map(\.id),
            ["train-normal"]
        )
        XCTAssertTrue(
            TrainNumberSearchLogic.results(in: trains, query: "23").isEmpty
        )
    }

    func testSearchExcludesMissingOrBlankNumbers() throws {
        let base = try XCTUnwrap(TestFixture.trainsResponse.trains.first)
        let trains = [
            train(from: base, id: "missing", number: nil),
            train(from: base, id: "blank", number: "   "),
            train(from: base, id: "found", number: "100M")
        ]

        XCTAssertEqual(
            TrainNumberSearchLogic.results(in: trains, query: "").map(\.id),
            ["found"]
        )
    }

    func testSearchReturnsAtMostFiveResults() throws {
        let base = try XCTUnwrap(TestFixture.trainsResponse.trains.first)
        let trains = (1...8).map { index in
            train(
                from: base,
                id: "train-\(index)",
                number: "10\(index)M"
            )
        }

        let results = TrainNumberSearchLogic.results(in: trains, query: "10")

        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(results.map(\.trainNumber), [
            "101M", "102M", "103M", "104M", "105M"
        ])
    }

    private func train(
        from base: TrainLocation,
        id: String,
        number: String?
    ) -> TrainLocation {
        TrainLocation(
            id: id,
            lineId: base.lineId,
            lineName: base.lineName,
            lineColor: base.lineColor,
            trainNumber: number,
            direction: base.direction,
            destination: base.destination,
            trainType: base.trainType,
            latitude: base.latitude,
            longitude: base.longitude,
            delayMinutes: base.delayMinutes,
            speedKmh: base.speedKmh,
            status: base.status,
            lastUpdatedAt: base.lastUpdatedAt,
            stoppedSince: base.stoppedSince,
            dataAccuracy: base.dataAccuracy,
            routeSegment: base.routeSegment,
            fromStation: base.fromStation,
            toStation: base.toStation,
            railDirection: base.railDirection
        )
    }
}
