import SwiftUI

struct RailwayFilterSheet: View {
    let options: [RailwayFilterOption]
    let isLoading: Bool
    @ObservedObject var preferences: UserPreferences

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredOptions: [RailwayFilterOption] {
        RailwayFilterLogic.filtered(
            options: options,
            query: query,
            favoritesOnly: preferences.favoritesOnly,
            favoriteIDs: preferences.favoriteLineIDs
        )
    }

    private var groupedOptions: [(String, [RailwayFilterOption])] {
        let grouped = Dictionary(grouping: filteredOptions, by: \.category)
        let categoryOrder = options.map(\.category).uniqued()
        return categoryOrder.compactMap { category in
            grouped[category].map { (category, $0) }
        }
    }

    private var selectedCount: Int {
        options.filter {
            $0.isSelectable && preferences.visibleLineIDs.contains($0.id)
        }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: favoritesOnlyBinding) {
                        Label(
                            "お気に入りのみ",
                            systemImage: preferences.favoritesOnly ? "star.fill" : "star"
                        )
                    }
                    .tint(.yellow)
                    .font(RailFont.bold(.body))
                    .accessibilityHint("地図と一覧をお気に入り路線だけに絞り込みます")

                    HStack(spacing: 12) {
                        Button("すべて表示") {
                            preferences.showAll(options)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RailTheme.accent)
                        .font(RailFont.bold(.body))
                        .minimumTapTarget()

                        Button("すべて隠す") {
                            preferences.hideAll()
                        }
                        .buttonStyle(.bordered)
                        .font(RailFont.bold(.body))
                        .minimumTapTarget()
                    }
                } footer: {
                    Text("表示設定とお気に入りはこの端末に保存されます。")
                }

                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("利用可能な路線を確認中…")
                                .font(RailFont.regular(.body))
                        }
                    }
                }

                ForEach(groupedOptions, id: \.0) { category, categoryOptions in
                    Section(category) {
                        ForEach(categoryOptions) { option in
                            RailwayOptionRow(
                                option: option,
                                selected: preferences.visibleLineIDs.contains(option.id),
                                favorite: preferences.favoriteLineIDs.contains(option.id),
                                onToggleVisibility: {
                                    preferences.toggleVisibility(for: option.id)
                                },
                                onToggleFavorite: {
                                    preferences.toggleFavorite(for: option.id)
                                }
                            )
                        }
                    }
                }

                if !isLoading && filteredOptions.isEmpty {
                    ContentUnavailableView(
                        preferences.favoritesOnly && preferences.favoriteLineIDs.isEmpty
                            ? "お気に入りがありません"
                            : "該当する路線がありません",
                        systemImage: "tram",
                        description: Text(
                            preferences.favoritesOnly && preferences.favoriteLineIDs.isEmpty
                                ? "各路線の星ボタンから登録できます。"
                                : "検索語を変えてお試しください。"
                        )
                    )
                    .listRowBackground(Color.clear)
                }
            }
            .searchable(text: $query, prompt: "路線名・別名を検索")
            .navigationTitle("表示する路線")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(selectedCount)路線")
                        .font(RailFont.bold(.caption))
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
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

    private var favoritesOnlyBinding: Binding<Bool> {
        Binding(
            get: { preferences.favoritesOnly },
            set: preferences.setFavoritesOnly
        )
    }
}

private struct RailwayOptionRow: View {
    let option: RailwayFilterOption
    let selected: Bool
    let favorite: Bool
    let onToggleVisibility: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleVisibility) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: option.color))
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle().stroke(.primary.opacity(0.35), lineWidth: 1)
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.name)
                            .font(RailFont.bold(.body))
                            .foregroundStyle(.primary)
                        HStack(spacing: 5) {
                            Image(systemName: coverageSymbol)
                                .accessibilityHidden(true)
                            Text(option.availabilityDescription)
                                .lineLimit(2)
                        }
                        .font(RailFont.regular(.caption2))
                        .foregroundStyle(coverageColor)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? RailTheme.accent : .secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: 50)
            .accessibilityLabel(
                "\(option.name)、\(option.availabilityDescription)、\(selected ? "表示中" : "非表示")"
            )
            .accessibilityHint("ダブルタップで表示を切り替えます")

            Button(action: onToggleFavorite) {
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(favorite ? .yellow : .secondary)
                    .minimumTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(option.name)をお気に入り\(favorite ? "から解除" : "に登録")"
            )
        }
    }

    private var coverageSymbol: String {
        switch option.coverage {
        case .realtime: "dot.radiowaves.left.and.right"
        case .limited: "circle.lefthalf.filled"
        case .unavailable: "location.slash"
        case .unknown: "questionmark.circle"
        }
    }

    private var coverageColor: Color {
        switch option.coverage {
        case .realtime: .green
        case .limited: .orange
        case .unavailable: .secondary
        case .unknown: .secondary
        }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
