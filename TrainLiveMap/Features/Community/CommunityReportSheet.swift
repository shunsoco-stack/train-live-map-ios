import SwiftUI

struct CommunityReportSheet: View {
    let visibleOptions: [RailwayFilterOption]
    @ObservedObject var viewModel: MainViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLineID = ""
    @State private var selectedChoice = "on-time"
    private var selectedStatus: CommunityReportStatus {
        selectedChoice == "resumed" ? .onTime : selectedChoice == "major-delay" ? .delayed
            : CommunityReportStatus(rawValue: selectedChoice) ?? .onTime
    }
    @State private var delayMinutes = 5

    private var response: CommunityReportsAPIResponse? {
        viewModel.communityReportsResponse
    }

    private var lineNames: [String: String] {
        Dictionary(uniqueKeysWithValues: visibleOptions.map { ($0.id, $0.name) })
    }

    var body: some View {
        NavigationStack {
            Form {
                introductionSection
                currentReportsSection
                submissionSection
                privacySection
            }
            .navigationTitle("みんなの運行情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .font(RailFont.bold(.body))
                    .accessibilityLabel("みんなの運行情報を閉じる")
                }
            }
            .task {
                if selectedLineID.isEmpty {
                    selectedLineID = visibleOptions.first?.id ?? ""
                }
                await viewModel.refreshCommunityReports()
            }
            .onDisappear {
                viewModel.clearCommunityFeedback()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .mplusAppTypography()
    }

    private var introductionSection: some View {
        Section {
            Label("みんなの情報（非公式）", systemImage: "person.3.fill")
                .font(RailFont.extraBold(.headline))
                .foregroundStyle(RailTheme.communityPink)
            Text(
                "現在表示中の路線について、利用者から直近"
                    + "\(response?.windowMinutes ?? 30)分に届いた投稿を集計します。"
                    + "公式運行情報ではありません。"
            )
            .font(RailFont.regular(.footnote))
        }
    }

    @ViewBuilder
    private var currentReportsSection: some View {
        Section("直近の投稿") {
            if viewModel.isLoadingCommunityReports, response == nil {
                HStack {
                    ProgressView()
                    Text("投稿を取得中…")
                }
            } else if viewModel.visibleCommunitySummaries.isEmpty {
                Text(
                    visibleOptions.isEmpty
                        ? "表示中の路線がないため、投稿は表示されません。"
                        : "表示中の路線には直近の投稿がありません。"
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.visibleCommunitySummaries) { summary in
                    CommunitySummaryRow(
                        summary: summary,
                        lineName: lineNames[summary.lineId] ?? summary.lineId
                    )
                }
            }

            if viewModel.communityReportsAreStale {
                Label(
                    "通信に失敗したため、最後に取得した古い投稿を表示しています。",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(RailFont.regular(.caption))
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var submissionSection: some View {
        Section {
            if visibleOptions.isEmpty {
                ContentUnavailableView(
                    "表示中の路線がありません",
                    systemImage: "tram",
                    description: Text("先に地図へ表示する路線を選んでください。")
                )
            } else {
                Picker("路線", selection: $selectedLineID) {
                    ForEach(visibleOptions) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .accessibilityIdentifier("community-line-picker")

                Picker("状況", selection: $selectedChoice) {
                    Text("平常").tag("on-time")
                    Text("○分程度の遅れ").tag("delayed")
                    Text("大幅な遅れ").tag("major-delay")
                    Text("運転見合わせ").tag("suspended")
                    Text("運転再開").tag("resumed")
                }
                .accessibilityIdentifier("community-status-picker")
                .onChange(of: selectedChoice) { _, choice in
                    if choice == "major-delay" { delayMinutes = max(30, delayMinutes) }
                }
                if selectedChoice == "resumed" {
                    Text("利用者による再開の報告です。平常票にも集計されます。公式の運転再開とは区別します。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if selectedStatus == .delayed {
                    Stepper(
                        "遅延 \(delayMinutes)分",
                        value: $delayMinutes,
                        in: 1...120
                    )
                    .accessibilityLabel("遅延分数、\(delayMinutes)分")
                }

                if let message = viewModel.communityErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(RailFont.regular(.footnote))
                        .foregroundStyle(.red)
                }
                if let message = viewModel.communitySuccessMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(RailFont.regular(.footnote))
                        .foregroundStyle(.green)
                }

                Button {
                    Task {
                        _ = await viewModel.submitCommunityReport(
                            lineID: selectedLineID,
                            status: selectedStatus,
                            delayMinutes: selectedStatus == .delayed
                                ? delayMinutes
                                : nil,
                            isResumption: selectedChoice == "resumed"
                        )
                    }
                } label: {
                    HStack {
                        if viewModel.isSubmittingCommunityReport {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("みんなの情報として投稿")
                            .font(RailFont.bold(.body))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(RailTheme.communityPink)
                .disabled(
                    selectedLineID.isEmpty
                        || viewModel.isSubmittingCommunityReport
                        || response?.votingEnabled == false
                )
                .accessibilityIdentifier("community-submit-button")
            }
        } header: {
            Text("状況を投稿")
        } footer: {
            Text(
                response?.votingEnabled == false
                    ? "現在、バックエンドで投稿受付が停止されています。"
                    : "同じ端末からの連続投稿は制限されます。遅延分数は投稿値の中央値です。"
            )
        }
    }

    private var privacySection: some View {
        Section("プライバシー") {
            Label(
                "氏名やメールアドレスは投稿に不要です。端末で生成したランダムIDをKeychainに保存し、投稿内容とともに送信して連続投稿を制限します。",
                systemImage: "hand.raised.fill"
            )
            .font(RailFont.regular(.footnote))
            Text(
                response?.persistent == true
                    ? "投稿はバックエンドで保存・検証されます。"
                    : "この環境では投稿が永続保存されない場合があります。"
            )
            .font(RailFont.regular(.caption))
            .foregroundStyle(.secondary)
            Text(
                "通知機能を利用する場合、APNsトークン・選択路線・最終更新時刻などのPush情報は、配信側で最終更新から最大180日保持され、通知解除時に削除されます。"
            )
            .font(RailFont.regular(.caption))
            .foregroundStyle(.secondary)
        }
    }
}

private struct CommunitySummaryRow: View {
    let summary: CommunityReportSummary
    let lineName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: summary.status.systemImage)
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(lineName)
                    .font(RailFont.bold(.body))
                Text(statusText)
                    .font(RailFont.extraBold(.subheadline))
                    .foregroundStyle(statusColor)
                if let count = summary.resumedCount, count > 0 {
                    Text("利用者から運転再開の報告 \(count)件").font(.caption)
                }
                Text(
                    "計\(summary.voteCount)件 "
                        + "（平常\(summary.counts.onTime)・遅延\(summary.counts.delayed)"
                        + "・見合わせ\(summary.counts.suspended)）"
                )
                .font(RailFont.regular(.caption))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(summary.updatedAt, style: .time)
                .font(RailFont.regular(.caption2))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(lineName)、みんなの情報、\(statusText)、"
                + "\(summary.voteCount)件、公式情報ではありません"
        )
    }

    private var statusText: String {
        if summary.status == .delayed, let minutes = summary.delayMinutes {
            return "遅延・中央値 \(minutes)分"
        }
        return summary.status.label
    }

    private var statusColor: Color {
        switch summary.status {
        case .onTime: .green
        case .delayed: .orange
        case .suspended: .red
        }
    }
}
