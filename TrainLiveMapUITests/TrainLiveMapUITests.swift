import XCTest

final class TrainLiveMapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Train Live Map"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["notification-settings-button"].exists)
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
