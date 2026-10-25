import SwiftUI

struct ServiceStatusSheet: View {
    let options: [RailwayFilterOption]
    let statuses: [ServiceStatus]
    let isStale: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("公式運行情報と、列車位置情報から分かる遅れを区別して表示します。利用者投稿は「みんなの運行情報」で確認できます。")
                        .font(.footnote)
                    if isStale { Label("運行情報を取得できませんでした。最後の取得内容です。", systemImage: "wifi.exclamationmark") }
                }
                ForEach(options) { option in
                    Section(option.name) {
                        if let status = statuses.first(where: { $0.lineId == option.id }) {
                            Text(status.message.isEmpty ? "運行情報を取得できませんでした" : status.message)
                            LabeledContent("更新時刻", value: status.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            Text(status.dataAccuracy == .estimated ? "列車位置情報による補完" : status.dataAccuracy == .mock ? "モックデータ" : "公式運行情報")
                                .font(.footnote).foregroundStyle(.secondary)
                            if let urlString = status.sourceUrl, let url = URL(string: urlString), AppConfiguration.isSecureHTTPSURL(url) {
                                Link(status.sourceLabel ?? "情報提供元", destination: url).frame(minHeight: 44)
                            } else { Text(status.sourceLabel ?? "ODPT（公共交通オープンデータセンター）").font(.footnote) }
                        } else {
                            Text("運行情報を取得できませんでした").foregroundStyle(.secondary)
                        }
                    }
                }
                if options.isEmpty { Text("路線を選択すると運行情報を確認できます。") }
            }
            .navigationTitle("運行情報")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
