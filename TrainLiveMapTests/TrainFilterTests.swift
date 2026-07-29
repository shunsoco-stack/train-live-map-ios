import XCTest
@testable import TrainLiveMap

final class TrainFilterTests: XCTestCase {
    func testAllStatusFilters() throws {
        let trains = try TestFixture.trainsResponse.trains
        let normal = try XCTUnwrap(trains.first { $0.id == "train-normal" })
        let delayed = try XCTUnwrap(trains.first { $0.id == "train-delayed" })
        let suspended = try XCTUnwrap(trains.first { $0.id == "train-suspended" })

        XCTAssertTrue(TrainFilter.all.matches(normal))
        XCTAssertTrue(TrainFilter.running.matches(normal))
        XCTAssertFalse(TrainFilter.delayed.matches(normal))

        XCTAssertTrue(TrainFilter.delayed.matches(delayed))
        XCTAssertFalse(TrainFilter.running.matches(delayed))

        XCTAssertTrue(TrainFilter.suspended.matches(suspended))
        XCTAssertFalse(TrainFilter.delayed.matches(suspended))
    }

    func testStoppedFilter() throws {
        let base = try XCTUnwrap(TestFixture.trainsResponse.trains.first)
        let stopped = TrainLocation(
            id: base.id,
            lineId: base.lineId,
            lineName: base.lineName,
            lineColor: base.lineColor,
            trainNumber: base.trainNumber,
            direction: base.direction,
            destination: base.destination,
            trainType: base.trainType,
            latitude: base.latitude,
            longitude: base.longitude,
            delayMinutes: 0,
            speedKmh: 0,
            status: .stopped,
            lastUpdatedAt: base.lastUpdatedAt,
            stoppedSince: base.lastUpdatedAt,
            dataAccuracy: base.dataAccuracy,
            routeSegment: base.routeSegment
        )

        XCTAssertTrue(TrainFilter.stopped.matches(stopped))
        XCTAssertFalse(TrainFilter.running.matches(stopped))
    }
}
