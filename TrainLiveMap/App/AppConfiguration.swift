import Foundation

struct AppConfiguration: Equatable {
    static let productionBaseURL = URL(string: "https://train-live-map.vercel.app")!

    let apiBaseURL: URL
    let apnsRegistrationURL: URL?
    let adMobAppID: String?
    let adMobBannerUnitID: String?

    static var current: AppConfiguration {
        let dictionary = Bundle.main.infoDictionary ?? [:]
        let baseURL = normalizedString(dictionary["APIBaseURL"])
            .flatMap(URL.init(string:))
            ?? productionBaseURL
        return AppConfiguration(
            apiBaseURL: baseURL,
            apnsRegistrationURL: normalizedString(
                dictionary["APNSRegistrationURL"]
            ).flatMap(URL.init(string:)),
            adMobAppID: normalizedString(dictionary["GADApplicationIdentifier"]),
            adMobBannerUnitID: normalizedString(dictionary["AdMobBannerUnitID"])
        )
    }

    var isAdvertisingConfigured: Bool {
        guard let adMobAppID, let adMobBannerUnitID else {
            return false
        }
        return adMobAppID.hasPrefix("ca-app-pub-")
            && adMobBannerUnitID.hasPrefix("ca-app-pub-")
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            && !isUITesting
    }

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }
}
