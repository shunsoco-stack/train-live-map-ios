import UIKit

enum AppAppearance {
    static func configure() {
        let navigationBar = UINavigationBar.appearance()
        navigationBar.titleTextAttributes = [
            .font: RailFont.uiBold(size: 17, textStyle: .headline)
        ]
        navigationBar.largeTitleTextAttributes = [
            .font: RailFont.uiExtraBold(size: 34)
        ]

        UIBarButtonItem.appearance().setTitleTextAttributes(
            [.font: RailFont.uiBold(size: 15, textStyle: .body)],
            for: .normal
        )
        UISearchTextField.appearance().font = RailFont.uiRegular(
            size: 16,
            textStyle: .body
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: RailFont.uiBold(size: 12, textStyle: .caption1)],
            for: .normal
        )
    }
}
