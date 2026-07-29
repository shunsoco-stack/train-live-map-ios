import Foundation
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class AdManager: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var privacyOptionsRequired = false

    let bannerUnitID: String?

    private let configuration: AppConfiguration
    private var hasPrepared = false

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        bannerUnitID = configuration.adMobBannerUnitID
    }

    func prepare() async {
        guard configuration.isAdvertisingConfigured, !hasPrepared else {
            return
        }
        hasPrepared = true

        let requestParameters = RequestParameters()
        _ = await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(
                with: requestParameters
            ) { error in
                continuation.resume(returning: error)
            }
        }

        await withCheckedContinuation { continuation in
            ConsentForm.loadAndPresentIfRequired(from: nil) { _ in
                continuation.resume()
            }
        }

        privacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required

        guard ConsentInformation.shared.canRequestAds else {
            return
        }
        await MobileAds.shared.start()
        isReady = true
    }

    func presentPrivacyOptions() async {
        guard privacyOptionsRequired else {
            return
        }
        await withCheckedContinuation { continuation in
            ConsentForm.presentPrivacyOptionsForm(from: nil) { _ in
                continuation.resume()
            }
        }
    }
}
