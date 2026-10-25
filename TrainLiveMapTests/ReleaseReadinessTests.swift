import XCTest
@testable import TrainLiveMap

final class ReleaseReadinessTests: XCTestCase {
    func testForecastDoesNotMeanResumedAndPartialSuspensionDoesNotStopEveryTrain() {
        let now = Date()
        let all = ServiceStatus(lineId: "yamanote", lineName: "山手線", severity: .major,
            message: "全線で運転を見合わせています。運転再開見込みは20時です。", updatedAt: now, dataAccuracy: .actual)
        XCTAssertTrue(ServiceStatusLogic.confirmsSuspension(all, now: now))
        XCTAssertEqual(ServiceStatusLogic.normalizedOfficialStatus(all).severity, .major)
        let partial = ServiceStatus(lineId: "yamanote", lineName: "山手線", severity: .major,
            message: "一部区間で運転を見合わせています。", updatedAt: now, dataAccuracy: .actual)
        XCTAssertFalse(ServiceStatusLogic.confirmsSuspension(partial, now: now))
        XCTAssertFalse(ServiceStatusLogic.confirmsSuspension(all, now: now.addingTimeInterval(601)))
    }

    func testSourceAndStationsDecodeFromCurrentProductionAPI() throws {
        let status = try JSONDecoder.trainLiveMap.decode(ServiceStatus.self, from: Data(##"{"lineId":"yamanote","lineName":"山手線","severity":"normal","message":"平常運転","updatedAt":"2026-10-25T18:38:47+09:00","dataAccuracy":"actual","sourceLabel":"JR東日本アイステイションズ（ODPT）","sourceUrl":"https://ckan.odpt.org/"}"##.utf8))
        XCTAssertEqual(status.updatedAt, ISO8601DateFormatter().date(from: "2026-10-25T09:38:47Z"))
        XCTAssertEqual(ServiceStatusLogic.normalizedOfficialStatus(status).sourceLabel, status.sourceLabel)
        let line = try JSONDecoder().decode(RailwayMapLine.self, from: Data(##"{"id":"yamanote","odptId":"odpt.Railway:JR-East.Yamanote","name":"山手線","color":"#85C023","coordinates":[],"stations":[{"id":"tokyo","name":"東京","position":[139.767,35.681]}]}"##.utf8))
        XCTAssertEqual(line.stations?.first?.name, "東京")
        XCTAssertEqual(line.stations?.first?.position.latitude, 35.681)
    }

    @MainActor
    func testNotificationPreferencesPersistAndDefaultToOptIn() throws {
        let name = "notification-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        XCTAssertFalse(preferences.notificationSettings.enabled)
        XCTAssertFalse(preferences.notificationSettings.includeCommunity)
        preferences.notificationSettings.enabled = true
        preferences.notificationSettings.includeCommunity = true
        preferences.notificationSettings.delay = true
        let restored = UserPreferences(defaults: defaults)
        XCTAssertEqual(restored.notificationSettings, preferences.notificationSettings)
    }
}
