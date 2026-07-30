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

    func testDelayBubbleAndSuspensionPriority() throws {
        let trains = try TestFixture.trainsResponse.trains
        let delayed = try train("train-delayed", in: trains)
        let suspended = try train("train-suspended", in: trains)

        XCTAssertEqual(
            TrainPresentation.delayBubbleText(for: delayed),
            "+8分"
        )
        XCTAssertNil(TrainPresentation.delayBubbleText(for: suspended))
        XCTAssertEqual(
            TrainPresentation.suspensionBadgeText(for: suspended),
            "見合わせ"
        )
    }

    func testDataAccuracyLabelsDistinguishActualEstimatedAndMock() {
        XCTAssertEqual(DataAccuracy.actual.label, "実データ")
        XCTAssertTrue(DataAccuracy.estimated.label.contains("駅間推定"))
        XCTAssertEqual(DataAccuracy.mock.label, "モックデータ")
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
