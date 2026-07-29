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

                    if train.dataAccuracy != .actual {
                        Label(
                            "表示位置は駅間情報などから求めた位置推定です。GPSの現在地ではありません。",
                            systemImage: "location.magnifyingglass"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
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
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var hero: some View {
        HStack(spacing: 18) {
            TrainIconView(train: train)
                .scaleEffect(1.35)
                .frame(width: 96, height: 100)

            VStack(alignment: .leading, spacing: 6) {
                Text(train.lineName)
                    .font(.title3.bold())
                Text(train.direction.displayText)
                    .font(.headline)
                Text("\(train.destination) 行き")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(
                    train.status.label,
                    systemImage: statusSystemImage
                )
                .font(.subheadline.bold())
                .foregroundStyle(statusColor)
            }
            Spacer()
        }
        .padding(16)
        .railPanel()
    }

    private var details: some View {
        VStack(spacing: 0) {
            DetailRow(label: "路線", value: train.lineName)
            DetailRow(label: "方向", value: train.direction.displayText)
            DetailRow(label: "行き先", value: train.destination)
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
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 16)
        }
        .accessibilityElement(children: .combine)
    }
}
