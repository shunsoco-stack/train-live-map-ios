import Foundation

struct AppConfiguration: Equatable {
    static let productionBaseURL = URL(string: "https://train-live-map.vercel.app")!

    let apiBaseURL: URL
    let apnsRegistrationURL: URL?
    let adMobAppID: String?
    let adMobBannerUnitID: String?

    init(
        apiBaseURL: URL,
        apnsRegistrationURL: URL?,
        adMobAppID: String?,
        adMobBannerUnitID: String?
    ) {
        self.apiBaseURL = Self.validatedAPIBaseURL(apiBaseURL)
        self.apnsRegistrationURL = Self.validatedNativeAPNSEndpoint(
            apnsRegistrationURL
        )
        self.adMobAppID = adMobAppID
        self.adMobBannerUnitID = adMobBannerUnitID
    }

    static var current: AppConfiguration {
        let dictionary = Bundle.main.infoDictionary ?? [:]
        let configuredBaseURL = normalizedString(dictionary["APIBaseURL"])
            .flatMap(URL.init(string:))
            ?? productionBaseURL
        return AppConfiguration(
            apiBaseURL: configuredBaseURL,
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

    static func validatedAPIBaseURL(_ url: URL?) -> URL {
        guard isSecureHTTPSURL(url),
              url?.query == nil,
              url?.fragment == nil else {
            return productionBaseURL
        }
        return url ?? productionBaseURL
    }

    static func validatedNativeAPNSEndpoint(_ url: URL?) -> URL? {
        guard isSecureHTTPSURL(url), let url, url.query == nil, url.fragment == nil else {
            return nil
        }

        let pathComponents = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.lowercased() }
        guard !pathComponents.starts(with: ["api", "push"]) else {
            // /api/push/* is the browser Web Push contract. APNs tokens must
            // only be sent to a separately implemented native endpoint.
            return nil
        }
        return url
    }

    static func isSecureHTTPSURL(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil else {
            return false
        }
        return true
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
