import XCTest
@testable import TrainLiveMap

final class AdvertisingConfigurationTests: XCTestCase {
    func testOnlyCompleteMatchingPublisherIDsEnableAdvertising() {
        func configured(_ appID: String?, _ unitID: String?) -> Bool {
            AppConfiguration(
                apiBaseURL: AppConfiguration.productionBaseURL,
                apnsRegistrationURL: nil,
                adMobAppID: appID,
                adMobBannerUnitID: unitID
            ).isAdvertisingConfigured
        }
        let app = "ca-app-pub-3013767899579778~7352774110"
        let unit = "ca-app-pub-3013767899579778/3017943283"
        XCTAssertTrue(configured(app, unit))
        XCTAssertFalse(configured(app, nil))
        XCTAssertFalse(configured(nil, unit))
        XCTAssertFalse(configured(unit, app))
        XCTAssertFalse(configured(app, "ca-app-pub-invalid"))
        XCTAssertFalse(configured(app, unit + "\n"))
        XCTAssertFalse(configured(app, "ca-app-pub-0000000000000000/3017943283"))
    }
}
