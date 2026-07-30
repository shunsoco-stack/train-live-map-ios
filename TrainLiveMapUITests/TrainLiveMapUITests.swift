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
        XCTAssertTrue(app.buttons["notification-settings-button"].exists)
        XCTAssertTrue(app.buttons["community-report-button"].exists)
        XCTAssertTrue(app.buttons["railway-filter-button"].exists)
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

    func testLargeDynamicTypeDarkModeAndNotificationExplanation() {
        let app = makeApp()
        app.launchArguments += [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Train Live Map"].waitForExistence(timeout: 8))
        let notificationButton = app.buttons["notification-settings-button"]
        XCTAssertTrue(notificationButton.waitForExistence(timeout: 5))
        notificationButton.tap()

        let notificationNavigationBar = app.navigationBars["運行情報の通知"]
        if !notificationNavigationBar.waitForExistence(timeout: 5),
           notificationButton.isHittable {
            notificationButton.tap()
        }
        XCTAssertTrue(
            notificationNavigationBar.waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            app.staticTexts["運転見合わせの可能性をお知らせ"].exists
        )
        XCTAssertTrue(
            app.staticTexts
                .matching(
                    NSPredicate(
                        format: "label CONTAINS '利用者からの報告'"
                    )
                )
                .firstMatch
                .exists
        )
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
