import XCTest
@testable import TrainLiveMap

final class PolylineGeometryTests: XCTestCase {
    func testInterpolationClampsProgressAndFractionsToUnitRange() {
        XCTAssertEqual(
            PolylineGeometry.interpolate(fromFraction: -1, toFraction: 2, progress: -3),
            0
        )
        XCTAssertEqual(
            PolylineGeometry.interpolate(fromFraction: -1, toFraction: 2, progress: 3),
            1
        )
    }

    func testOutboundAndInboundInterpolationUseOppositeDirections() {
        let outbound = PolylineGeometry.interpolate(
            fromFraction: 0.2,
            toFraction: 0.8,
            progress: 0.25
        )
        let inbound = PolylineGeometry.interpolate(
            fromFraction: 0.8,
            toFraction: 0.2,
            progress: 0.25
        )

        XCTAssertEqual(outbound, 0.35, accuracy: 0.000_001)
        XCTAssertEqual(inbound, 0.65, accuracy: 0.000_001)
    }

    func testOffTrackCoordinateClampsToPolyline() throws {
        let geometry = PolylineGeometry(
            coordinates: [
                MapCoordinate(longitude: 139.0, latitude: 35.0),
                MapCoordinate(longitude: 140.0, latitude: 35.0)
            ]
        )
        let clamped = try XCTUnwrap(
            geometry.clampedCoordinate(
                for: MapCoordinate(longitude: 139.5, latitude: 36.0)
            )
        )

        XCTAssertEqual(clamped.longitude, 139.5, accuracy: 0.001)
        XCTAssertEqual(clamped.latitude, 35.0, accuracy: 0.001)
    }

    func testMotionFollowsRouteDirectionThenStopsWithoutExtrapolating() throws {
        let engine = TrainMotionEngine()
        let receivedAt = Date(timeIntervalSince1970: 1_000)
        let outbound = estimatedTrain(
            id: "outbound",
            direction: .outbound,
            coordinates: [
                MapCoordinate(longitude: 139.0, latitude: 35.0),
                MapCoordinate(longitude: 140.0, latitude: 35.0)
            ]
        )
        let inbound = estimatedTrain(
            id: "inbound",
            direction: .inbound,
            coordinates: [
                MapCoordinate(longitude: 140.0, latitude: 35.0),
                MapCoordinate(longitude: 139.0, latitude: 35.0)
            ]
        )

        engine.ingest(
            trains: [outbound, inbound],
            railwayLines: [],
            at: receivedAt
        )

        let initial = engine.positions(at: receivedAt)
        let completed = engine.positions(
            at: receivedAt.addingTimeInterval(7)
        )
        let muchLater = engine.positions(
            at: receivedAt.addingTimeInterval(60)
        )

        XCTAssertGreaterThan(
            try XCTUnwrap(completed["outbound"]).longitude,
            try XCTUnwrap(initial["outbound"]).longitude
        )
        XCTAssertLessThan(
            try XCTUnwrap(completed["inbound"]).longitude,
            try XCTUnwrap(initial["inbound"]).longitude
        )
        XCTAssertEqual(
            try XCTUnwrap(completed["outbound"]).longitude,
            try XCTUnwrap(muchLater["outbound"]).longitude,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(completed["inbound"]).longitude,
            try XCTUnwrap(muchLater["inbound"]).longitude,
            accuracy: 0.000_001
        )
    }

    private func estimatedTrain(
        id: String,
        direction: TrainDirection,
        coordinates: [MapCoordinate]
    ) -> TrainLocation {
        TrainLocation(
            id: id,
            lineId: "line",
            lineName: "テスト線",
            lineColor: "#f68b1e",
            trainNumber: nil,
            direction: direction,
            destination: "終点",
            trainType: .local,
            latitude: 35.0,
            longitude: 139.5,
            delayMinutes: 0,
            speedKmh: 60,
            status: .running,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            stoppedSince: nil,
            dataAccuracy: .estimated,
            routeSegment: RouteSegmentEstimate(
                fromFraction: 0,
                toFraction: 1,
                coordinates: coordinates
            )
        )
    }
}
