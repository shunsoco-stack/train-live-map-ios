import GoogleMobileAds
import SwiftUI
import UIKit

struct AdaptiveBannerView: UIViewControllerRepresentable {
    let adUnitID: String
    @Binding var isLoaded: Bool

    func makeUIViewController(context: Context) -> AdaptiveBannerViewController {
        let controller = AdaptiveBannerViewController(adUnitID: adUnitID)
        let loaded = $isLoaded
        controller.onAdLoaded = {
            loaded.wrappedValue = true
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: AdaptiveBannerViewController,
        context: Context
    ) {
        let loaded = $isLoaded
        uiViewController.onAdLoaded = {
            loaded.wrappedValue = true
        }
    }
}

final class AdaptiveBannerViewController: UIViewController, BannerViewDelegate {
    var onAdLoaded: (() -> Void)?

    private let adUnitID: String
    private let bannerView = BannerView()
    private var lastLoadedWidth: CGFloat = 0

    init(adUnitID: String) {
        self.adUnitID = adUnitID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = self
        bannerView.delegate = self
        view.addSubview(bannerView)
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = floor(view.bounds.width)
        guard width > 0, abs(width - lastLoadedWidth) >= 1 else {
            return
        }
        lastLoadedWidth = width
        let maxHeight: CGFloat =
            traitCollection.userInterfaceIdiom == .pad ? 90 : 52
        bannerView.adSize = inlineAdaptiveBanner(
            width: width,
            maxHeight: maxHeight
        )
        bannerView.load(Request())
    }

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        onAdLoaded?()
    }
}
