import SwiftUI

struct TrainDetailSheet: View {
    let train: TrainLocation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    details
                    positionNotice
                }
                .padding()
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("列車の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .font(RailFont.bold(.body))
                    .accessibilityLabel("列車の詳細を閉じる")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .mplusAppTypography()
    }

    private var hero: some View {
        HStack(spacing: 18) {
            TrainIconView(train: train)
                .scaleEffect(1.35)
                .frame(width: 96, height: 100)

            VStack(alignment: .leading, spacing: 6) {
                Text(train.lineName)
                    .font(RailFont.extraBold(.title3))
                Text(train.direction.displayText)
                    .font(RailFont.extraBold(.headline))
                    .foregroundStyle(directionColor)
                Text("\(train.destination) 行き")
                    .font(RailFont.regular(.subheadline))
                    .foregroundStyle(.secondary)

                Label(
                    train.status.label,
                    systemImage: statusSystemImage
                )
                .font(RailFont.bold(.subheadline))
                .foregroundStyle(statusColor)
            }
            Spacer()
        }
        .padding(16)
        .railPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrainPresentation.accessibilityLabel(for: train))
    }

    private var details: some View {
        VStack(spacing: 0) {
            if let trainNumber = TrainPresentation.normalizedTrainNumber(
                train.trainNumber
            ) {
                DetailRow(label: "列車番号", value: trainNumber)
            }
            DetailRow(label: "路線", value: train.lineName)
            DetailRow(label: "方向", value: train.direction.displayText)
            DetailRow(label: "行き先", value: train.destination)
            DetailRow(label: "現在の駅間", value: train.currentSegmentText)
            DetailRow(label: "種別", value: train.trainType.label)
            DetailRow(label: "状態", value: train.status.label)
            DetailRow(
                label: "遅延",
                value: train.delayMinutes > 0 ? "\(train.delayMinutes)分" : "なし"
            )
            DetailRow(label: "速度", value: "\(Int(train.speedKmh.rounded())) km/h")
            DetailRow(
                label: "最終更新",
                value: train.lastUpdatedAt.formatted(
                    date: .omitted,
                    time: .standard
                )
            )
            DetailRow(label: "データ精度", value: train.dataAccuracy.label)
            DetailRow(
                label: "データ区分",
                value: train.dataAccuracy == .actual
                    ? "実データ"
                    : train.dataAccuracy == .estimated
                        ? "位置推定"
                        : "モック"
            )

            if train.stoppedSince != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    DetailRow(
                        label: "停車時間",
                        value: TrainPresentation.stoppedDurationText(
                            for: train,
                            now: context.date
                        ) ?? "—"
                    )
                }
            }
        }
        .railPanel()
    }

    private var positionNotice: some View {
        Label(
            positionNoticeText,
            systemImage: train.dataAccuracy == .mock
                ? "exclamationmark.triangle.fill"
                : "location.magnifyingglass"
        )
        .font(RailFont.bold(.footnote))
        .foregroundStyle(train.dataAccuracy == .mock ? .orange : .secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(positionNoticeText)
        .accessibilityIdentifier("estimated-position-notice")
    }

    private var positionNoticeText: String {
        let positionExplanation =
            "位置は駅間情報などからの推定です。GPSによる正確な現在位置ではありません。"
        switch train.dataAccuracy {
        case .actual:
            return positionExplanation
                + " 列車情報はODPTの実データです。"
        case .estimated:
            return positionExplanation
                + " ODPTライブの駅間推定データです。"
        case .mock:
            return positionExplanation
                + " モックデータのため、実際の運行状況や位置を示すものではありません。"
        }
    }

    private var statusSystemImage: String {
        switch train.status {
        case .running: "arrow.forward.circle.fill"
        case .stopped: "pause.circle.fill"
        case .delayed: "exclamationmark.clock.fill"
        case .suspended: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch train.status {
        case .running: .green
        case .stopped: .orange
        case .delayed: .red
        case .suspended: .blue
        case .unknown: .secondary
        }
    }

    private var directionColor: Color {
        train.direction == .inbound
            ? RailTheme.inboundBlue
            : RailTheme.outboundOrange
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(RailFont.regular(.body))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 16)
        }
        .accessibilityElement(children: .combine)
    }
}
