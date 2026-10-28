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

                Section("プライバシー") {
                    Label(
                        "利用者投稿には、端末内で作成した匿名の識別子を使用します。投稿と識別子は不正投稿の防止に使用します。",
                        systemImage: "hand.raised.fill"
                    )
                    .font(RailFont.regular(.footnote))
                    Text(
                        "端末の現在地は、現在地ボタンをタップした後に許可された場合だけ取得し、"
                            + "地図を現在地付近へ移動するために使用します。位置情報はサーバーへ送信せず、端末にも保存しません。"
                            + "列車の推定位置も地図表示・移動以外のAPIへ追加送信しません。"
                    )
                    .font(RailFont.regular(.caption))
                    .foregroundStyle(.secondary)
                }

                Section("地図の帰属") {
                    Link("OpenFreeMap", destination: URL(string: "https://openfreemap.org")!)
                    Link("© OpenMapTiles", destination: URL(string: "https://openmaptiles.org")!)
                    Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                }
                Section("法務情報") {
                    Link(destination: Self.privacyPolicyURL) {
                        Label(
                            "プライバシーポリシー",
                            systemImage: "hand.raised.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityHint("Safariでプライバシーポリシーを開きます")

                    Link(destination: Self.termsURL) {
                        Label(
                            "利用規約",
                            systemImage: "doc.text.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityHint("Safariで利用規約を開きます")
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

    private static let privacyPolicyURL = URL(
        string: "https://train-live-map.vercel.app/privacy"
    )!
    private static let termsURL = URL(
        string: "https://train-live-map.vercel.app/terms"
    )!
}
