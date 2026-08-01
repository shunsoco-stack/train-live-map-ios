import SwiftUI

struct TrainEmptyStateView: View {
    let title: String
    let message: String
    var systemImage = "train.side.front.car"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(RailTheme.accent)
                    .accessibilityHidden(true)

                Text(title)
                    .font(RailFont.extraBold(.subheadline))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(RailFont.regular(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title)。\(message)")

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(RailFont.bold(.caption))
                    .buttonStyle(.borderedProminent)
                    .tint(RailTheme.accent)
                    .minimumTapTarget()
                    .accessibilityHint("列車位置情報をもう一度取得します")
                    .accessibilityIdentifier("train-empty-retry-button")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 360)
        .railPanel(cornerRadius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("train-empty-state")
    }
}
