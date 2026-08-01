import SwiftUI

struct TrainNumberSearchSheet: View {
    let trains: [TrainLocation]
    let selectedTrainID: String?
    let onSelectTrain: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [TrainLocation] {
        TrainNumberSearchLogic.results(in: trains, query: query)
    }

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    TrainEmptyStateView(
                        title: "該当する列車がありません",
                        message: emptyMessage,
                        systemImage: "magnifyingglass"
                    )
                    .padding()
                } else {
                    List(results) { train in
                        resultButton(for: train)
                            .listRowBackground(Color(.secondarySystemBackground))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("列車番号で検索")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "列車番号の先頭を入力"
            )
            .submitLabel(.search)
            .onSubmit(of: .search) {
                selectFirstResult()
            }
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .font(RailFont.bold(.body))
                    .accessibilityLabel("列車番号検索を閉じる")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .mplusAppTypography()
    }

    private func selectFirstResult() {
        guard let firstResult = results.first else {
            return
        }
        onSelectTrain(firstResult.id)
        dismiss()
    }

    private func resultButton(for train: TrainLocation) -> some View {
        let number = TrainPresentation.normalizedTrainNumber(train.trainNumber)
            ?? "番号不明"
        let isSelected = train.id == selectedTrainID

        return Button {
            onSelectTrain(train.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: train.lineColor))
                    .frame(width: 7, height: 44)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(.primary.opacity(0.25), lineWidth: 1)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(number)
                        .font(RailFont.extraBold(.headline))
                        .monospacedDigit()
                    Text("\(train.lineName) ・ \(train.destination)行き")
                        .font(RailFont.regular(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(train.direction.displayText)
                        .font(RailFont.bold(.caption))
                        .foregroundStyle(
                            train.direction == .inbound
                                ? RailTheme.inboundBlue
                                : RailTheme.outboundOrange
                        )
                    Text(train.status.label)
                        .font(RailFont.bold(.caption2))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TrainPresentation.accessibilityLabel(for: train))
        .accessibilityValue(isSelected ? "選択中" : "")
        .accessibilityHint("地図上の列車へ移動し、詳細を表示します")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("train-search-result-\(train.id)")
    }

    private var emptyMessage: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "現在表示できる列車番号はありません。"
        }
        return "「\(trimmed)」で始まる列車番号は見つかりませんでした。"
    }
}
