import XCTest
@testable import TrainLiveMap

final class RailwaySelectionLogicTests: XCTestCase {
    func testInitialSelectionUsesFirstSelectableOptionPerCategory() throws {
        let options = try TestFixture.railwaysResponse.options

        XCTAssertEqual(
            RailwaySelectionLogic.defaultVisibleIDs(from: options),
            ["tokaido", "chuo-rapid"]
        )
    }

    func testOfficialStatusIncludesOnlySelectedRoutesInSeverityOrder() throws {
        let statuses = try TestFixture.serviceResponse.allStatuses
        let selected = RailwaySelectionLogic.filteredServiceStatuses(
            statuses,
            visibleLineIDs: ["chuo-rapid"]
        )
        XCTAssertEqual(selected.map(\.lineId), ["chuo-rapid"])

        let all = RailwaySelectionLogic.filteredServiceStatuses(
            statuses,
            visibleLineIDs: ["tokaido", "chuo-rapid"]
        )
        XCTAssertEqual(all.map(\.lineId), ["tokaido", "chuo-rapid"])
    }

    func testNoSelectedRoutesProducesNoOfficialMessage() throws {
        XCTAssertTrue(
            RailwaySelectionLogic.filteredServiceStatuses(
                try TestFixture.serviceResponse.allStatuses,
                visibleLineIDs: []
            ).isEmpty
        )
    }
}
