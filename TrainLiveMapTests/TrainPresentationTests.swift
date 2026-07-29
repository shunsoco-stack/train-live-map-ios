import XCTest
@testable import TrainLiveMap

final class TrainPresentationTests: XCTestCase {
    func testNormalDelayedAndSuspendedFaces() throws {
        let trains = try TestFixture.trainsResponse.trains

        XCTAssertEqual(
            TrainPresentation.face(for: try train("train-normal", in: trains)),
            .smiling
        )
        XCTAssertEqual(
            TrainPresentation.face(for: try train("train-delayed", in: trains)),
            .troubled
        )
        XCTAssertEqual(
            TrainPresentation.face(for: try train("train-suspended", in: trains)),
            .sadWithTear
        )
    }

    func testDirectionDisplayUsesArrowAndJapaneseText() {
        XCTAssertEqual(TrainDirection.inbound.displayText, "↑ 上り")
        XCTAssertEqual(TrainDirection.outbound.displayText, "↓ 下り")
    }

    func testAccessibilityLabelIncludesStateDirectionDestinationAndDelay() throws {
        let delayed = try train(
            "train-delayed",
            in: TestFixture.trainsResponse.trains
        )
        let label = TrainPresentation.accessibilityLabel(for: delayed)

        XCTAssertTrue(label.contains("山手線"))
        XCTAssertTrue(label.contains("上り"))
        XCTAssertTrue(label.contains("東京"))
        XCTAssertTrue(label.contains("遅延"))
        XCTAssertTrue(label.contains("8分遅れ"))
    }

    private func train(
        _ id: String,
        in trains: [TrainLocation]
    ) throws -> TrainLocation {
        try XCTUnwrap(trains.first { $0.id == id })
    }
}
