import SwiftUI

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image("BrandIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Train Live Map")
                                .font(RailFont.extraBold(.title2))
                            Text("JR東日本・関東版（非公式）")
                                .font(RailFont.bold(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("データについて") {
                    Label(
                        "ODPTライブ（位置は駅間推定）",
                        systemImage: "location.magnifyingglass"
                    )
                    .font(RailFont.bold(.body))
                    Text(
                        "JR東日本の列車位置はODPTチャレンジ2026限定データを"
                            + "Webバックエンド経由で取得します。緯度経度が直接提供されない"
                            + "場合は、駅間情報と路線形状から位置を推定します。GPS現在地ではありません。"
                    )
                    .font(RailFont.regular(.footnote))
                    Text(
                        "実データ・推定データ・モックデータを画面上で区別します。"
                    )
                    .font(RailFont.regular(.footnote))
                }

                Section("非公式アプリ") {
                    Text(
                        "本アプリはJR東日本および公共交通オープンデータ協議会の"
                            + "公式アプリではありません。公式ロゴや車両デザインは使用していません。"
                    )
                    .font(RailFont.regular(.footnote))
                }

                Section("プライバシーと通知") {
                    Label(
                        "通知配信に使用するAPNs端末トークンと購読路線は、配信サーバーで最終更新から最大180日間保持されます。",
                        systemImage: "hand.raised.fill"
                    )
                    .font(RailFont.regular(.footnote))
                    Text(
                        "通知登録の解除時にはサーバーへ購読情報の削除を要求します。"
                            + "APNs端末トークンはブラウザ用Web Push購読APIへ送信しません。"
                    )
                    .font(RailFont.regular(.caption))
                    .foregroundStyle(.secondary)
                }

                Section("お問い合わせ") {
                    Button {
                        openURL(
                            URL(
                                string: "mailto:train-live-map-support@gmail.com"
                            )!
                        )
                    } label: {
                        Label(
                            "train-live-map-support@gmail.com",
                            systemImage: "envelope.fill"
                        )
                    }
                    .minimumTapTarget()
                }
            }
            .navigationTitle("このアプリについて")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .font(RailFont.bold(.body))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .mplusAppTypography()
    }
}
