import GoogleMobileAds
import SwiftUI

/// A standard 320 × 50 banner keeps the same small footprint on every device.
struct MapBannerView: UIViewControllerRepresentable {
    let unitID: String
    @Binding var loaded: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.clipsToBounds = true
        #if DEBUG && targetEnvironment(simulator)
        if AppConfiguration.isAdvertisingLayoutTest {
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: 320, height: 50))
            label.text = "広告レイアウト確認（テスト）"
            label.textAlignment = .center
            label.backgroundColor = .secondarySystemBackground
            label.textColor = .label
            label.accessibilityIdentifier = "advertising-layout-fixture"
            controller.view.addSubview(label)
            return controller
        }
        #endif
        let banner = BannerView(adSize: AdSizeBanner)
        banner.rootViewController = controller
        banner.adUnitID = unitID
        banner.delegate = context.coordinator
        controller.view.addSubview(banner)
        banner.frame = CGRect(origin: .zero, size: AdSizeBanner.size)
        banner.load(Request())
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(loaded: $loaded) }

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var loaded: Bool
        init(loaded: Binding<Bool>) { _loaded = loaded }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) { loaded = true }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            AdManager.log.debug("Banner unavailable (code \((error as NSError).code, privacy: .public))")
            loaded = false
        }
    }
}

struct MapBannerFooter: View {
    let unitID: String
    @State private var loaded = AppConfiguration.isAdvertisingLayoutTest

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 320 {
                MapBannerView(unitID: unitID, loaded: $loaded)
                    .frame(width: 320, height: 50)
                    .frame(maxWidth: .infinity)
                    .onDisappear { loaded = false }
            }
        }
        .frame(height: loaded ? 50 : 0)
        .clipped()
        .padding(.top, loaded ? 8 : 0)
        .allowsHitTesting(loaded)
        .accessibilityHidden(!loaded)
    }
}
