import XCTest
@testable import TrainLiveMap

final class AppConfigurationSecurityTests: XCTestCase {
    func testHTTPAPIURLFallsBackToProductionHTTPS() {
        let configuration = AppConfiguration(
            apiBaseURL: URL(string: "http://example.com")!,
            apnsRegistrationURL: nil,
            adMobAppID: nil,
            adMobBannerUnitID: nil
        )

        XCTAssertEqual(
            configuration.apiBaseURL,
            AppConfiguration.productionBaseURL
        )
        XCTAssertEqual(configuration.apiBaseURL.scheme, "https")
    }

    func testRejectsHTTPAndCredentialedAPNSEndpoints() {
        XCTAssertNil(
            AppConfiguration.validatedNativeAPNSEndpoint(
                URL(string: "http://example.com/api/apns/devices")
            )
        )
        XCTAssertNil(
            AppConfiguration.validatedNativeAPNSEndpoint(
                URL(string: "https://user:password@example.com/api/apns/devices")
            )
        )
    }

    func testRejectsBrowserWebPushEndpointForAPNsToken() {
        XCTAssertNil(
            AppConfiguration.validatedNativeAPNSEndpoint(
                URL(string: "https://train-live-map.vercel.app/api/push/subscriptions")
            )
        )
        XCTAssertNil(
            AppConfiguration.validatedNativeAPNSEndpoint(
                URL(string: "https://train-live-map.vercel.app/api/push/config")
            )
        )
    }

    func testAcceptsDedicatedHTTPSAPNSEndpoint() {
        let url = URL(string: "https://notify.example.com/api/apns/devices")!
        XCTAssertEqual(
            AppConfiguration.validatedNativeAPNSEndpoint(url),
            url
        )
    }
}
