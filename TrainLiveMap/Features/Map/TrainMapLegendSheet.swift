import SwiftUI

struct TrainMapLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusLegend
                    directionLegend
                    positionLegend
                }
                .padding()
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("地図の凡例")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .font(RailFont.bold(.body))
                    .accessibilityLabel("地図の凡例を閉じる")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .mplusAppTypography()
    }

    private var statusLegend: some View {
        legendSection(title: "列車の状態") {
            LegendRow(
                symbol: "face.smiling",
                symbolColor: .green,
                title: "走行中",
                detail: "笑顔の電車で表示します。"
            )
            LegendRow(
                symbol: "pause.circle.fill",
                symbolColor: .orange,
                title: "停車中",
                detail: "停車時間が取得できる場合は詳細で確認できます。"
            )
            LegendRow(
                symbol: "exclamationmark.clock.fill",
                symbolColor: .red,
                title: "遅延",
                detail: "困り顔と「+N分」の吹き出しで表示します。"
            )
            LegendRow(
                symbol: "drop.fill",
                symbolColor: .blue,
                title: "運転見合わせ",
                detail: "泣き顔と「見合わせ」バッジで表示します。"
            )
            LegendRow(
                symbol: "questionmark.circle.fill",
                symbolColor: .secondary,
                title: "状態不明",
                detail: "状態を確認できない列車です。詳細の更新時刻も確認してください。"
            )
        }
    }

    private var directionLegend: some View {
        legendSection(title: "進行方向") {
            DirectionLegendRow(
                text: "↑ 上り",
                color: RailTheme.inboundBlue,
                detail: "ODPTのrailDirectionを優先した上り方向"
            )
            DirectionLegendRow(
                text: "↓ 下り",
                color: RailTheme.outboundOrange,
                detail: "ODPTのrailDirectionを優先した下り方向"
            )
        }
    }

    private var positionLegend: some View {
        legendSection(title: "位置とデータ区分") {
            LegendRow(
                symbol: "location.magnifyingglass",
                symbolColor: RailTheme.accent,
                title: "位置推定",
                detail: "駅間情報などから線路上に推定した位置です。GPSによる正確な現在位置ではありません。"
            )
            LegendRow(
                symbol: "wave.3.right.circle.fill",
                symbolColor: .green,
                title: "実データ",
                detail: "ODPTから取得した列車情報です。位置自体は駅間推定の場合があります。"
            )
            LegendRow(
                symbol: "shippingbox.fill",
                symbolColor: .orange,
                title: "モックデータ",
                detail: "実際の運行状況や現在位置を示すデータではありません。"
            )
        }
    }

    private func legendSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(RailFont.extraBold(.headline))
            VStack(spacing: 0) {
                content()
            }
            .railPanel()
        }
    }
}

private struct LegendRow: View {
    let symbol: String
    let symbolColor: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(symbolColor)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RailFont.extraBold(.subheadline))
                Text(detail)
                    .font(RailFont.regular(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 57)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)。\(detail)")
    }
}

private struct DirectionLegendRow: View {
    let text: String
    let color: Color
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(text)
                .font(RailFont.extraBold(.subheadline))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(color, in: Capsule())
                .accessibilityHidden(true)
            Text(detail)
                .font(RailFont.regular(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 13)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text)。\(detail)")
    }
}
