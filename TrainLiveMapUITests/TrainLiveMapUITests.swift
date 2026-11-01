import XCTest
import UIKit

final class TrainLiveMapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Uses Google's test-device serving on a simulator and the real published UMP form.
    func testLiveAdvertisingConsentAndBanner() throws {
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TLM_AD_UI_TESTS"] == "1")
        let app = XCUIApplication()
        app.launchArguments = ["-AdConsentEEATest", "-AdConsentReset", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let decline = app.webViews.buttons["同意しない"].firstMatch
        XCTAssertTrue(decline.waitForExistence(timeout: 30), app.debugDescription)
        decline.tap()
        // UMP retains an offscreen form for privacy-options reuse. Its controls
        // remain in the accessibility tree after dismissal.
        let mapReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["railway-filter-button"])
        XCTAssertEqual(XCTWaiter.wait(for: [mapReady], timeout: 15), .completed)

        app.buttons["このアプリについて"].tap()
        let privacy = app.buttons["広告のプライバシー設定"]
        for _ in 0..<5 where !privacy.isHittable { app.swipeUp() }
        XCTAssertTrue(privacy.isHittable, app.debugDescription)
        privacy.tap()
        let consent = app.webViews.buttons["同意"].firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 15), app.debugDescription)
        consent.tap()
        let settingsReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: privacy)
        XCTAssertEqual(XCTWaiter.wait(for: [settingsReady], timeout: 15), .completed)
        app.navigationBars["このアプリについて"].buttons["閉じる"].tap()

        let banner = app.descendants(matching: .any).matching(identifier: "advertising-banner-container").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 30))
        XCTAssertEqual(banner.frame.height, 50, accuracy: 1)
        XCTAssertLessThanOrEqual(banner.frame.maxY, app.frame.maxY)
        XCTAssertLessThanOrEqual(app.buttons["railway-filter-button"].frame.maxY, banner.frame.minY)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Google test banner after UMP consent"
        image.lifetime = .keepAlways
        add(image)
        #else
        throw XCTSkip("Live advertising checks only run on simulators, which Google treats as test devices.")
        #endif
    }

    func testBannerStaysBelowAttributionAndMapControls() {
        let app = makeApp()
        app.launchArguments.append("-UITestAdBanner")
        app.launch()
        let banner = app.staticTexts["advertising-layout-fixture"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        let attribution = app.descendants(matching: .any).matching(identifier: "map-attribution").firstMatch
        XCTAssertLessThanOrEqual(attribution.frame.maxY, banner.frame.minY + 1)
        for id in ["railway-filter-button", "current-location-button", "community-report-button"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.isHittable)
            XCTAssertLessThanOrEqual(button.frame.maxY, banner.frame.minY)
        }
        XCTAssertEqual(banner.frame.height, 50, accuracy: 1)
        XCTAssertLessThanOrEqual(banner.frame.maxY, app.frame.maxY)
        XCTAssertGreaterThanOrEqual(banner.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(banner.frame.maxX, app.frame.maxX)
        app.buttons["railway-filter-button"].tap()
        XCTAssertTrue(app.navigationBars["表示する路線"].waitForExistence(timeout: 5))
    }

    func testMainMapControlsAccessibilitySmoke() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Train Live Map"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)["data-source-badge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["notification-settings-button"].exists)
        XCTAssertTrue(app.buttons["community-report-button"].exists)
        XCTAssertTrue(app.buttons["railway-filter-button"].exists)
        XCTAssertTrue(app.buttons["current-location-button"].exists)
        XCTAssertEqual(
            app.buttons["current-location-button"].label,
            "現在地付近へ地図を移動"
        )
        XCTAssertTrue(app.buttons["train-filter-all"].exists)
        XCTAssertTrue(app.buttons["train-filter-delayed"].exists)
        XCTAssertTrue(
            app.buttons
                .matching(
                    NSPredicate(format: "label BEGINSWITH '東海道線、下り'")
                )
                .firstMatch
                .waitForExistence(timeout: 5)
        )
    }

    func testMainRouteSelectionAndCommunityFlows() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Train Live Map"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["JR東日本・関東版（非公式）"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["data-source-badge"]
                .waitForExistence(timeout: 5)
        )

        let routeButton = app.buttons["railway-filter-button"]
        XCTAssertTrue(routeButton.waitForExistence(timeout: 5))
        routeButton.tap()
        XCTAssertTrue(app.navigationBars["表示する路線"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["山手線"].exists)

        let routeSearch = app.searchFields.firstMatch
        XCTAssertTrue(routeSearch.waitForExistence(timeout: 4))
        routeSearch.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            routeSearch.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            )
            .tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        routeSearch.typeText("常磐")
        XCTAssertTrue(
            app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH '常磐線、'"))
                .firstMatch
                .waitForExistence(timeout: 4)
        )
        let searchCloseButton = app.buttons["閉じる"]
        if searchCloseButton.waitForExistence(timeout: 2) {
            searchCloseButton.tap()
        }
        let routeDoneButton = app.buttons["完了"]
        XCTAssertTrue(routeDoneButton.waitForExistence(timeout: 4))
        routeDoneButton.tap()
        XCTAssertTrue(
            app.navigationBars["表示する路線"].waitForNonExistence(timeout: 4)
        )

        let communityButton = app.buttons["community-report-button"]
        XCTAssertTrue(communityButton.waitForExistence(timeout: 4))
        communityButton.tap()
        XCTAssertTrue(
            app.navigationBars["みんなの運行情報"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["みんなの情報（非公式）"].exists)
        let submitButton = app.buttons["community-submit-button"]
        let communityForm = app.collectionViews.firstMatch
        for _ in 0..<3 where !submitButton.exists {
            communityForm.swipeUp()
        }
        XCTAssertTrue(submitButton.waitForExistence(timeout: 4))
        app.buttons["みんなの運行情報を閉じる"].tap()
    }

    func testLargeDynamicTypeDarkModeAndPrivacyExplanation() {
        let app = makeApp()
        app.launchArguments += [
            "-UITestAdBanner",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Train Live Map"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["advertising-layout-fixture"].exists)
        XCTAssertFalse(app.buttons["notification-settings-button"].exists)
        XCTAssertTrue(app.buttons["compact-map-menu"].isHittable)
        app.buttons["compact-map-menu"].tap()
        app.buttons["表示する路線"].tap()
        XCTAssertTrue(app.navigationBars["表示する路線"].waitForExistence(timeout: 8))
        app.buttons["完了"].tap()
        app.buttons["data-status-button"].tap()
        XCTAssertTrue(app.navigationBars["データの状態"].waitForExistence(timeout: 8))
        app.navigationBars["データの状態"].buttons["閉じる"].tap()
        let largeMap = XCTAttachment(screenshot: app.screenshot())
        largeMap.name = "Maximum text size map without advertising"
        largeMap.lifetime = .keepAlways
        add(largeMap)
        app.buttons["このアプリについて"].tap()
        XCTAssertTrue(app.navigationBars["このアプリについて"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["JR東日本・関東版（非公式）"].exists)
        let privacy = app.staticTexts["プライバシー"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<4 where !privacy.isHittable { list.swipeUp() }
        XCTAssertTrue(privacy.exists)

    }

    func testTrainNumberSearchLegendDetailAndDisabledFilters() {
        let app = makeApp()
        app.launch()

        let stoppedFilter = app.buttons["train-filter-stopped"]
        XCTAssertTrue(stoppedFilter.waitForExistence(timeout: 8))
        XCTAssertFalse(stoppedFilter.isEnabled)
        XCTAssertTrue(app.buttons["train-filter-all"].isSelected)

        let searchButton = app.buttons["train-search-button"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.tap()
        XCTAssertTrue(
            app.navigationBars["列車番号で検索"]
                .waitForExistence(timeout: 5)
        )

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 4))
        searchField.tap()
        searchField.typeText("123")

        let result = app.buttons["train-search-result-ui-yamanote"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()

        XCTAssertTrue(
            app.navigationBars["列車の詳細"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["123G"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["estimated-position-notice"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.staticTexts
                .matching(
                    NSPredicate(
                        format: "label CONTAINS 'GPSによる正確な現在位置ではありません'"
                    )
                )
                .firstMatch
                .exists
        )

        app.buttons["列車の詳細を閉じる"].tap()
        let legendButton = app.buttons["train-legend-button"]
        XCTAssertTrue(legendButton.waitForExistence(timeout: 5))
        legendButton.tap()
        XCTAssertTrue(
            app.navigationBars["地図の凡例"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["列車の状態"].exists)
        XCTAssertTrue(app.staticTexts["進行方向"].exists)
        XCTAssertTrue(app.staticTexts["位置推定"].exists)
    }

    func testFavoritesAndOfficialInformation() {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["service-status-button"].waitForExistence(timeout: 15))
        app.buttons["service-status-button"].tap()
        XCTAssertTrue(app.navigationBars["運行情報"].waitForExistence(timeout: 8))
        app.buttons["閉じる"].tap()
        app.buttons["railway-filter-button"].tap()
        let favorite = app.buttons["山手線をお気に入りに登録"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 8))
        favorite.tap()
        XCTAssertTrue(app.buttons["山手線をお気に入りから解除"].exists)
        app.switches["favorites-only-toggle"].tap()
        XCTAssertFalse(app.buttons["東海道線をお気に入りに登録"].exists)
    }

    func testOfflineDoesNotShowLiveTrainPositions() {
        let app = makeApp()
        app.launchArguments += ["-UITestOffline"]
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'オフライン'")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '東海道線、下り'")).firstMatch.exists)
    }

    /// Opt-in release check. Reads the real backend without submitting reports or
    /// requesting location/notification permission. Normal CI remains offline.
    func testLiveBackendMapAndForegroundRecovery() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TLM_LIVE_UI_TESTS"] == "1",
            "Enable explicitly when validating a connected release device."
        )
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()

        let liveBadge = app.descendants(matching: .any)
            .matching(identifier: "data-source-badge")
            .matching(NSPredicate(format: "label CONTAINS %@", "ODPTライブ"))
            .firstMatch
        XCTAssertTrue(liveBadge.waitForExistence(timeout: 45), app.debugDescription)
        for attribution in ["OpenFreeMap", "© OpenMapTiles", "© OpenStreetMap"] {
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", attribution))
                    .firstMatch.exists,
                "Missing map attribution: \(attribution)"
            )
        }
        let mapImage = XCTAttachment(screenshot: app.screenshot())
        mapImage.name = "Live backend map"
        mapImage.lifetime = .keepAlways
        add(mapImage)

        app.buttons["railway-filter-button"].tap()
        XCTAssertTrue(app.navigationBars["表示する路線"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["山手線"].exists)
        app.buttons["完了"].tap()
        XCTAssertTrue(app.navigationBars["表示する路線"].waitForNonExistence(timeout: 8))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(liveBadge.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["notification-settings-button"].exists)
        let resumedImage = XCTAttachment(screenshot: app.screenshot())
        resumedImage.name = "Live map after foreground recovery"
        resumedImage.lifetime = .keepAlways
        add(resumedImage)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
            "-DisableAdsForUITesting"
        ]
        return app
    }
}
