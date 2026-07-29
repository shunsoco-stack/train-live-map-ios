import SwiftUI

struct MainView: View {
    @ObservedObject private var viewModel: MainViewModel
    @ObservedObject private var preferences: UserPreferences
    @ObservedObject private var adManager: AdManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var railwaySheetPresented = false
    @State private var adBannerLoaded = false

    init(viewModel: MainViewModel, adManager: AdManager) {
        self.viewModel = viewModel
        preferences = viewModel.preferences
        self.adManager = adManager
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                MapLibreTrainMap(
                    trains: viewModel.filteredTrains,
                    railwayLines: viewModel.visibleRailwayLines,
                    isActive: scenePhase == .active,
                    onSelectTrain: { trainID in
                        viewModel.selectedTrainID = trainID
                    }
                )
                .ignoresSafeArea(edges: .horizontal)

                mapOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if adManager.isReady, let unitID = adManager.bannerUnitID {
                Color.clear
                    .frame(height: adBannerLoaded ? bannerHeight : 1)
                    .overlay(alignment: .bottom) {
                        AdaptiveBannerView(
                            adUnitID: unitID,
                            isLoaded: $adBannerLoaded
                        )
                        .frame(maxWidth: .infinity, maxHeight: bannerHeight)
                    }
                    .background(
                        adBannerLoaded ? Color(.systemBackground) : Color.clear
                    )
                    .clipped()
                    .accessibilityLabel("広告")
                    .accessibilityHidden(!adBannerLoaded)
                    .animation(.easeOut(duration: 0.2), value: adBannerLoaded)
            }
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $railwaySheetPresented) {
            RailwayFilterSheet(
                options: viewModel.railwaysResponse?.options ?? [],
                isLoading: viewModel.isLoadingRailways,
                preferences: preferences
            )
        }
        .sheet(item: selectedTrainBinding) { train in
            TrainDetailSheet(train: train)
        }
    }

    private var bannerHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 90 : 52
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "train.side.front.car")
                .font(.title2.bold())
                .foregroundStyle(RailTheme.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Train Live Map")
                    .font(.headline.weight(.black))
                    .foregroundStyle(RailTheme.cream)
                Label("列車の位置推定", systemImage: "location.magnifyingglass")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(RailTheme.mutedCream)
            }

            Spacer()

            if let response = viewModel.trainsResponse {
                let source = DataSourcePresentation(response: response)
                Label(
                    source.title,
                    systemImage: source.isWarning
                        ? "exclamationmark.triangle.fill"
                        : "network"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(source.isWarning ? Color.yellow : RailTheme.cream)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.white.opacity(0.1), in: Capsule())
                .accessibilityLabel("データ取得元 \(source.title)")
            }

            if adManager.privacyOptionsRequired {
                Button {
                    Task {
                        await adManager.presentPrivacyOptions()
                    }
                } label: {
                    Image(systemName: "hand.raised.fill")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(RailTheme.cream)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("広告プライバシー設定")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(RailTheme.darkBrown)
    }

    private var mapOverlay: some View {
        VStack(spacing: 8) {
            if let service = viewModel.serviceStatusResponse {
                ServiceStatusPanel(
                    response: service,
                    isStale: viewModel.serviceStatusIsStale
                )
                .frame(maxWidth: 560)
            }

            if let error = viewModel.trainErrorMessage
                ?? viewModel.serviceErrorMessage
                ?? viewModel.railwayErrorMessage {
                ErrorPanel(message: error, onRetry: viewModel.retryAll)
                    .frame(maxWidth: 560)
            } else if let dataSourceNotice {
                NoticePanel(message: dataSourceNotice)
                    .frame(maxWidth: 560)
            }

            Spacer(minLength: 80)

            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    DataUpdatePanel(viewModel: viewModel)
                    TrainFilterBar(selection: $viewModel.selectedFilter)
                }

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Button {
                        preferences.setFavoritesOnly(!preferences.favoritesOnly)
                    } label: {
                        Image(
                            systemName: preferences.favoritesOnly ? "star.fill" : "star"
                        )
                        .font(.title3.bold())
                        .foregroundStyle(
                            preferences.favoritesOnly ? Color.yellow : Color.primary
                        )
                        .frame(width: 50, height: 50)
                        .background(.ultraThickMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.primary.opacity(0.18), lineWidth: 1)
                        }
                        .shadow(radius: 5, y: 2)
                    }
                    .accessibilityLabel(
                        preferences.favoritesOnly
                            ? "お気に入りのみを解除"
                            : "お気に入り路線だけ表示"
                    )

                    Button {
                        railwaySheetPresented = true
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(.title2)
                            Text("\(preferences.effectiveVisibleLineIDs.count)")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(RailTheme.accent, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.85), lineWidth: 2)
                        }
                        .shadow(radius: 6, y: 3)
                    }
                    .accessibilityLabel(
                        "表示路線を選ぶ。\(preferences.effectiveVisibleLineIDs.count)路線を表示中"
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .allowsHitTesting(true)
    }

    private var dataSourceNotice: String? {
        var notices: [String] = []

        if let response = viewModel.trainsResponse {
            let source = DataSourcePresentation(response: response)
            if let detail = source.detail {
                notices.append("列車位置: \(detail)")
            }
        }

        if let response = viewModel.serviceStatusResponse {
            if response.fallback {
                notices.append(
                    "運行情報: \(response.notice ?? "フォールバックデータを表示中")"
                )
            } else if response.isMock || response.source == .mock {
                notices.append(
                    "運行情報: \(response.notice ?? "モックデータを表示中")"
                )
            }
        }

        if viewModel.railwaysResponse?.source == .fallback {
            notices.append("路線情報: フォールバックデータを表示中")
        }

        return notices.isEmpty ? nil : notices.joined(separator: "\n")
    }

    private var selectedTrainBinding: Binding<TrainLocation?> {
        Binding(
            get: { viewModel.selectedTrain },
            set: { newValue in
                if newValue == nil {
                    viewModel.selectedTrainID = nil
                }
            }
        )
    }
}

private struct ServiceStatusPanel: View {
    let response: ServiceStatusAPIResponse
    let isStale: Bool

    private var color: Color {
        switch response.serviceStatus.severity {
        case .normal: .green
        case .minor: .orange
        case .major: .red
        }
    }

    private var symbol: String {
        switch response.serviceStatus.severity {
        case .normal: "checkmark.circle.fill"
        case .minor: "exclamationmark.triangle.fill"
        case .major: "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(response.serviceStatus.lineName)
                        .font(.caption.bold())
                    if isStale {
                        Text("古い情報")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }
                Text(response.serviceStatus.message)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            Spacer()
            Text(
                response.serviceStatus.updatedAt.formatted(
                    date: .omitted,
                    time: .shortened
                )
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .railPanel(cornerRadius: 13)
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorPanel: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("再試行", action: onRetry)
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
                .tint(RailTheme.accent)
                .minimumTapTarget()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .railPanel(cornerRadius: 13)
    }
}

private struct NoticePanel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .railPanel(cornerRadius: 13)
    }
}

private struct DataUpdatePanel: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                if viewModel.isLoadingTrains {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("更新中")
                } else {
                    Image(systemName: viewModel.trainsAreStale ? "clock.badge.exclamationmark" : "clock")
                        .foregroundStyle(viewModel.trainsAreStale ? .orange : .secondary)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(updateText)
                        .font(.caption2.monospacedDigit())
                    Text(nextUpdateText(now: context.date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .railPanel(cornerRadius: 12)
            .accessibilityElement(children: .combine)
        }
    }

    private var updateText: String {
        guard let response = viewModel.trainsResponse else {
            return "列車データを取得中"
        }
        let prefix = viewModel.trainsAreStale ? "古いデータ・最終更新" : "最終更新"
        return "\(prefix) \(response.dataUpdatedAt.formatted(date: .omitted, time: .standard))"
    }

    private func nextUpdateText(now: Date) -> String {
        guard let next = viewModel.nextTrainRefreshAt else {
            return "バックグラウンド中は更新を停止"
        }
        let remaining = max(0, Int(ceil(next.timeIntervalSince(now))))
        return "次回更新まで \(remaining)秒"
    }
}

private struct TrainFilterBar: View {
    @Binding var selection: TrainFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TrainFilter.allCases) { filter in
                    Button {
                        selection = filter
                    } label: {
                        Label(filter.label, systemImage: filter.systemImage)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .foregroundStyle(selection == filter ? .white : .primary)
                            .background(
                                selection == filter
                                    ? RailTheme.accent
                                    : Color(.systemBackground).opacity(0.94),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().stroke(.primary.opacity(0.18), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: 520)
    }
}
