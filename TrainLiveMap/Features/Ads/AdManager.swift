import GoogleMobileAds
import OSLog
import SwiftUI
import UserMessagingPlatform

@MainActor
final class AdManager: ObservableObject {
    static let log = Logger(subsystem: "com.shunsoco.trainlivemap", category: "Advertising")
    @Published private(set) var canShowBanner = false
    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var privacyError: String?
    private var preparing = false
    private var prepared = false
    private var sdkStarted = false

    func prepare() async {
        guard AppConfiguration.current.isAdvertisingConfigured,
              !AppConfiguration.isRunningTests, !AppConfiguration.isUITesting,
              !preparing, !prepared else { return }
        Self.log.info("Preparing advertising consent")
        preparing = true
        defer { preparing = false }
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            Self.log.info("Consent information updated")
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
            prepared = true
            Self.log.info("Consent form completed")
            await applyConsent()
        } catch {
            Self.log.error("UMP consent unavailable (code \((error as NSError).code, privacy: .public))")
            privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        }
    }

    func presentPrivacyOptions() async {
        guard privacyOptionsRequired, !preparing else { return }
        preparing = true
        defer { preparing = false }
        canShowBanner = false
        privacyError = nil
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            await applyConsent()
        } catch {
            privacyError = "広告のプライバシー設定を開けませんでした。もう一度お試しください。"
        }
    }

    private func applyConsent() async {
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard ConsentInformation.shared.canRequestAds else {
            Self.log.info("Advertising unavailable under current consent")
            canShowBanner = false
            return
        }
        if !sdkStarted {
            let config = MobileAds.shared.requestConfiguration
            config.publisherPrivacyPersonalizationState = .disabled
            config.setPublisherFirstPartyIDEnabled(false)
            config.maxAdContentRating = .general
            await MobileAds.shared.start()
            sdkStarted = true
        }
        canShowBanner = ConsentInformation.shared.canRequestAds
        Self.log.info("Banner requests enabled")
    }
}
