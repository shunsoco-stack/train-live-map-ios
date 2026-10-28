import SwiftUI

enum MapSceneActivityPolicy {
    static func keepsOneShotLocationRequestAlive(
        during scenePhase: ScenePhase
    ) -> Bool {
        scenePhase != .background
    }
}

struct MainView: View {
    @ObservedObject private var viewModel: MainViewModel
    @ObservedObject private var preferences: UserPreferences
    @ObservedObject private var notificationManager: NotificationManager

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var railwaySheetPresented = false
    @State private var communitySheetPresented = false
    @State private var notificationSheetPresented = false
    @State private var aboutSheetPresented = false
    @State private var trainSearchSheetPresented = false
    @State private var serviceSheetPresented = false
    @State private var legendSheetPresented = false
    @State private var pendingSearchedTrainID: String?
    @State private var locationRequestID = 0
    @State private var locationIsRequesting = false
    @State private var locationStatusMessage: String?
    @State private var locationAlert: LocationAlert?
    @State private var locationFeedbackDismissTask: Task<Void, Never>?

    init(
        viewModel: MainViewModel,
        notificationManager: NotificationManager
    ) {
        self.viewModel = viewModel
        preferences = viewModel.preferences
        self.notificationManager = notificationManager
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                MapLibreTrainMap(
                    trains: viewModel.filteredTrains,
                    railwayLines: viewModel.visibleRailwayLines,
                    selectedTrainID: viewModel.selectedTrainID,
                    // A system permission alert temporarily changes the scene
                    // to inactive. Keep the one-shot request alive there, and
                    // stop it only after the app truly enters background.
                    isActive: MapSceneActivityPolicy
                        .keepsOneShotLocationRequestAlive(during: scenePhase),
                    reduceMotion: reduceMotion,
                    locationRequestID: locationRequestID,
                    onSelectTrain: { trainID in
                        viewModel.selectedTrainID = trainID
                    },
                    onLocationEvent: handleMapLocationEvent
                )
                .ignoresSafeArea(edges: .horizontal)

                mapOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                attributionLinks
                attributionLinks.font(.system(size: 9))
            }
            .frame(maxWidth: .infinity).background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $railwaySheetPresented) {
            RailwayFilterSheet(
                options: viewModel.selectableRailwayOptions,
                isLoading: viewModel.isLoadingRailways,
                preferences: preferences
            )
        }
        .sheet(isPresented: $serviceSheetPresented) {
            ServiceStatusSheet(options: visibleRailwayOptions, statuses: viewModel.visibleServiceStatuses, isStale: viewModel.serviceStatusIsStale)
        }
        .sheet(isPresented: $communitySheetPresented) {
            CommunityReportSheet(
                visibleOptions: visibleRailwayOptions,
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $notificationSheetPresented) {
            NotificationSettingsSheet(
                options: viewModel.selectableRailwayOptions,
                preferences: preferences,
                notificationManager: notificationManager
            )
        }
        .sheet(isPresented: $aboutSheetPresented) {
            AboutSheet()
        }
        .sheet(
            isPresented: $trainSearchSheetPresented,
            onDismiss: selectPendingSearchedTrain
        ) {
            TrainNumberSearchSheet(
                trains: visibleCurrentTrains,
                selectedTrainID: viewModel.selectedTrainID,
                onSelectTrain: { trainID in
                    pendingSearchedTrainID = trainID
                }
            )
        }
        .sheet(isPresented: $legendSheetPresented) {
            TrainMapLegendSheet()
        }
        .sheet(item: selectedTrainBinding) { train in
            TrainDetailSheet(train: train)
        }
        .alert(item: $locationAlert) { alert in
            Alert(
                title: Text("現在地を表示できません"),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: notificationManager.pendingLineID) { _, lineID in
            guard let lineID,
                  viewModel.selectableRailwayOptions.contains(
                    where: { $0.id == lineID }
                  ) else {
                return
            }
            preferences.showOnly(lineID: lineID)
            _ = notificationManager.consumePendingLineID()
        }
        .onChange(of: preferences.notificationSettings) { _, settings in
            Task { await notificationManager.syncSubscriptions(lineIDs: preferences.notificationLineIDs, settings: settings) }
        }
        .onChange(of: preferences.notificationLineIDs) { _, lineIDs in
            Task {
                await notificationManager.syncSubscriptions(lineIDs: lineIDs, settings: preferences.notificationSettings)
            }
        }
        .onDisappear {
            locationFeedbackDismissTask?.cancel()
        }
    }

    private var visibleRailwayOptions: [RailwayFilterOption] {
        let visibleIDs = preferences.effectiveVisibleLineIDs
        return viewModel.selectableRailwayOptions.filter {
            visibleIDs.contains($0.id)
        }
    }

    private var visibleCurrentTrains: [TrainLocation] {
        let visibleIDs = preferences.effectiveVisibleLineIDs
        return viewModel.currentTrains.filter { visibleIDs.contains($0.lineId) }
    }

    private var trainFilterCounts: [TrainFilter: Int] {
        TrainFilter.counts(in: visibleCurrentTrains)
    }

    private var shouldShowTrainEmptyState: Bool {
        if preferences.effectiveVisibleLineIDs.isEmpty {
            return true
        }
        if !visibleCurrentTrains.isEmpty {
            return viewModel.filteredTrains.isEmpty
        }
        guard !viewModel.isLoadingTrains else {
            return false
        }
        return viewModel.trainsResponse != nil
            || viewModel.trainErrorMessage != nil
            || viewModel.isOffline
            || preferences.effectiveVisibleLineIDs.isEmpty
    }

    private var trainEmptyTitle: String {
        if preferences.effectiveVisibleLineIDs.isEmpty {
            if viewModel.railwayErrorMessage != nil {
                return "路線情報を取得できません"
            }
            return "表示する路線がありません"
        }
        if viewModel.trainsAreStale || viewModel.isOffline {
            return "現在の列車位置を表示できません"
        }
        if !visibleCurrentTrains.isEmpty, viewModel.filteredTrains.isEmpty {
            return "条件に合う列車がありません"
        }
        return "列車位置情報がありません"
    }

    private var trainEmptyMessage: String {
        if preferences.effectiveVisibleLineIDs.isEmpty {
            return [
                "路線選択から表示する路線を選んでください。",
                viewModel.railwayErrorMessage,
                viewModel.isOffline
                    ? "オフライン中は再送しません。接続が戻ると自動で更新します。"
                    : nil
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        }
        if viewModel.isOffline {
            return trainEmptyMessageWithRequestContext(
                "オフラインのため、過去の列車位置は現在位置として表示していません。"
            )
        }
        if viewModel.trainsAreStale {
            return trainEmptyMessageWithRequestContext(
                "更新に失敗しました。最後に成功した古いデータが0件のため、列車を表示できません。"
            )
        }
        if !visibleCurrentTrains.isEmpty, viewModel.filteredTrains.isEmpty {
            return "別の列車状態フィルターを選んでください。"
        }
        return trainEmptyMessageWithRequestContext(
            "表示中の路線では、現在表示できる列車がありません。"
        )
    }

    private var shouldOfferTrainRetry: Bool {
        viewModel.canRetryRailwayRequest
            || (visibleCurrentTrains.isEmpty && viewModel.canRetryTrainRequest)
    }

    private var networkErrorMessage: String? {
        let parts = [
            viewModel.trainErrorMessage,
            viewModel.trainErrorMessage == nil
                ? nil
                : viewModel.trainRetrySuppressionMessage,
            viewModel.serviceErrorMessage,
            viewModel.serviceErrorMessage == nil
                ? nil
                : viewModel.serviceRetrySuppressionMessage,
            viewModel.railwayErrorMessage
        ]
        let messages = parts.compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private var canRetryNetworkError: Bool {
        (viewModel.trainErrorMessage != nil && viewModel.canRetryTrainRequest)
            || viewModel.canRetryServiceStatusRequest
            || viewModel.canRetryRailwayRequest
    }

    private func retryEmptyState() {
        Task {
            if viewModel.canRetryRailwayRequest {
                await viewModel.refreshRailways()
            }
            if viewModel.canRetryTrainRequest {
                await viewModel.refreshTrains()
            }
        }
    }

    private func retryNetworkErrors() {
        Task {
            if viewModel.railwayErrorMessage != nil,
               viewModel.canRetryRailwayRequest {
                await viewModel.refreshRailways()
            }
            if viewModel.trainErrorMessage != nil,
               viewModel.canRetryTrainRequest {
                await viewModel.refreshTrains()
            }
            if viewModel.serviceErrorMessage != nil,
               viewModel.canRetryServiceStatusRequest {
                await viewModel.refreshServiceStatus()
            }
        }
    }

    private func trainEmptyMessageWithRequestContext(_ base: String) -> String {
        [
            base,
            viewModel.trainErrorMessage,
            viewModel.serviceErrorMessage,
            viewModel.railwayErrorMessage,
            trainLastSuccessfulUpdateMessage,
            viewModel.trainRetrySuppressionMessage
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private var trainLastSuccessfulUpdateMessage: String? {
        guard viewModel.trainsAreStale
                || viewModel.trainErrorMessage != nil
                || viewModel.isOffline else {
            return nil
        }
        guard let response = viewModel.trainsResponse else {
            return "最後に成功した列車位置データはありません。"
        }
        let updatedAt = response.dataUpdatedAt.formatted(
            date: .abbreviated,
            time: .standard
        )
        return "最後に成功した更新は\(updatedAt)です。"
    }

    private func selectPendingSearchedTrain() {
        defer { pendingSearchedTrainID = nil }
        guard let pendingSearchedTrainID,
              visibleCurrentTrains.contains(
                where: { $0.id == pendingSearchedTrainID }
              ) else {
            return
        }
        viewModel.selectedFilter = .all
        viewModel.selectedTrainID = pendingSearchedTrainID
    }

    @MainActor
    private func handleMapLocationEvent(_ event: MapLocationEvent) {
        locationFeedbackDismissTask?.cancel()
        locationFeedbackDismissTask = nil

        switch event {
        case .requesting:
            locationIsRequesting = true
            locationStatusMessage = "現在地を確認しています"
        case .centered:
            locationIsRequesting = false
            locationStatusMessage = "現在地付近へ地図を移動しました"
            locationFeedbackDismissTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    return
                }
                locationStatusMessage = nil
            }
        case .cancelled:
            locationIsRequesting = false
            locationStatusMessage = nil
        case let .failed(message):
            locationIsRequesting = false
            locationStatusMessage = nil
            locationAlert = LocationAlert(message: message)
        }
    }

    private var attributionLinks: some View {
        HStack(spacing: 6) {
            Link("OpenFreeMap", destination: URL(string: "https://openfreemap.org")!)
            Link("© OpenMapTiles", destination: URL(string: "https://openmaptiles.org")!)
            Link("© OpenStreetMap", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
        }
        .font(.caption2).frame(minHeight: 44)
        .accessibilityIdentifier("map-attribution")
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button {
                aboutSheetPresented = true
            } label: {
                Image("BrandIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(.white.opacity(0.6), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            .accessibilityLabel("このアプリについて")

            VStack(alignment: .leading, spacing: 0) {
                Text("Train Live Map")
                    .font(RailFont.extraBold(.headline))
                    .foregroundStyle(RailTheme.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("app-title")
                Text("JR東日本・関東版（非公式）")
                    .font(RailFont.bold(.caption2))
                    .foregroundStyle(RailTheme.mutedCream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("edition-title")
            }

            Spacer(minLength: 2)

            if AppConfiguration.current.apnsRegistrationURL != nil {
                Button {
                    notificationSheetPresented = true
                } label: {
                    Image(
                        systemName: notificationManager.state == .authorized
                            ? "bell.fill"
                            : "bell"
                    )
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(RailTheme.cream)
                    .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("運行情報の通知設定")
                .accessibilityIdentifier("notification-settings-button")
            }


        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 58)
        .background(RailTheme.darkBrown)
    }

    private var mapOverlay: some View {
        VStack(spacing: 7) {
            HStack(alignment: .top, spacing: 7) {
                if let response = viewModel.trainsResponse {
                    DataSourceBadge(response: response)
                }
                Spacer(minLength: 0)

                MapCircleButton(
                    systemName: locationIsRequesting
                        ? "location.magnifyingglass"
                        : "location.fill",
                    foreground: .primary,
                    background: Color(.systemBackground),
                    label: locationIsRequesting
                        ? "現在地を確認中"
                        : "現在地付近へ地図を移動",
                    isEnabled: !locationIsRequesting
                ) {
                    locationStatusMessage = nil
                    locationRequestID &+= 1
                }
                .accessibilityIdentifier("current-location-button")
            }

            if let locationStatusMessage {
                LocationStatusPanel(
                    message: locationStatusMessage,
                    isLoading: locationIsRequesting
                )
                .frame(maxWidth: 600)
            }

            if !viewModel.visibleServiceStatuses.isEmpty {
                Button { serviceSheetPresented = true } label: {
                    ServiceStatusPanel(
                        statuses: viewModel.visibleServiceStatuses,
                        isStale: viewModel.serviceStatusIsStale
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("service-status-button")
                .frame(maxWidth: 600)
            }

            if !shouldShowTrainEmptyState,
               let error = networkErrorMessage {
                ErrorPanel(
                    message: error,
                    onRetry: canRetryNetworkError ? retryNetworkErrors : nil
                )
                    .frame(maxWidth: 600)
            } else if let dataSourceNotice {
                NoticePanel(message: dataSourceNotice)
                    .frame(maxWidth: 600)
            }

            Spacer(minLength: 24)

            if shouldShowTrainEmptyState {
                TrainEmptyStateView(
                    title: trainEmptyTitle,
                    message: trainEmptyMessage,
                    systemImage: viewModel.trainsAreStale
                        || viewModel.railwayErrorMessage != nil
                        ? "clock.badge.exclamationmark"
                        : "train.side.front.car",
                    actionTitle: shouldOfferTrainRetry ? "再試行" : nil,
                    action: shouldOfferTrainRetry
                        ? retryEmptyState
                        : nil
                )
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 24)

            HStack(alignment: .bottom, spacing: 7) {
                VStack(alignment: .leading, spacing: 7) {
                    DataUpdatePanel(viewModel: viewModel)
                    TrainFilterBar(
                        selection: $viewModel.selectedFilter,
                        counts: trainFilterCounts
                    )
                }

                Spacer(minLength: 0)

                VStack(spacing: 7) {
                    HStack(spacing: 7) {
                        MapCircleButton(
                            systemName: "magnifyingglass",
                            foreground: .primary,
                            background: Color(.systemBackground),
                            label: "列車番号で検索"
                        ) {
                            trainSearchSheetPresented = true
                        }
                        .accessibilityIdentifier("train-search-button")

                        MapCircleButton(
                            systemName: "questionmark.circle.fill",
                            foreground: .primary,
                            background: Color(.systemBackground),
                            label: "列車状態と位置の凡例"
                        ) {
                            legendSheetPresented = true
                        }
                        .accessibilityIdentifier("train-legend-button")
                    }

                    MapCircleButton(
                        systemName: "person.3.fill",
                        foreground: .white,
                        background: RailTheme.communityPink,
                        label: "みんなの運行情報"
                    ) {
                        communitySheetPresented = true
                    }
                    .accessibilityIdentifier("community-report-button")

                    MapCircleButton(
                        systemName: preferences.favoritesOnly
                            ? "star.fill"
                            : "star",
                        foreground: preferences.favoritesOnly
                            ? .yellow
                            : .primary,
                        background: Color(.systemBackground),
                        label: preferences.favoritesOnly
                            ? "お気に入りのみを解除"
                            : "お気に入り路線だけ表示"
                    ) {
                        preferences.setFavoritesOnly(!preferences.favoritesOnly)
                    }

                    Button {
                        railwaySheetPresented = true
                    } label: {
                        VStack(spacing: 0) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 19, weight: .bold))
                            Text("\(preferences.effectiveVisibleLineIDs.count)")
                                .font(RailFont.extraBold(.caption2))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(RailTheme.accent, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.9), lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "表示路線を選ぶ。"
                            + "\(preferences.effectiveVisibleLineIDs.count)路線を表示中"
                    )
                    .accessibilityIdentifier("railway-filter-button")
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }

    private var dataSourceNotice: String? {
        var notices: [String] = []

        if let response = viewModel.trainsResponse,
           let detail = DataSourcePresentation(response: response).detail {
            notices.append(detail)
        }

        if let response = viewModel.serviceStatusResponse {
            if response.fallback {
                notices.append(
                    "公式運行情報: "
                        + (response.notice ?? "フォールバックデータを表示中")
                )
            } else if response.isMock || response.source == .mock {
                notices.append(
                    "公式運行情報: "
                        + (response.notice ?? "モックデータを表示中")
                )
            }
        }

        if viewModel.railwaysResponse?.source == .fallback {
            notices.append("路線情報はフォールバックデータです。")
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

private struct LocationAlert: Identifiable {
    let id = UUID()
    let message: String
}

private struct LocationStatusPanel: View {
    let message: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "location.fill")
                    .foregroundStyle(RailTheme.inboundBlue)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(RailFont.bold(.caption))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .railPanel(cornerRadius: 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityIdentifier("current-location-status")
    }
}

private struct DataSourceBadge: View {
    let response: TrainsAPIResponse

    var body: some View {
        let presentation = DataSourcePresentation(response: response)
        Label(
            presentation.title,
            systemImage: presentation.isWarning
                ? "exclamationmark.triangle.fill"
                : "location.magnifyingglass"
        )
        .font(RailFont.bold(.caption2))
        .foregroundStyle(presentation.isWarning ? Color.orange : Color.primary)
        .lineLimit(2)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .railPanel(cornerRadius: 11)
        .accessibilityLabel("データ取得元、\(presentation.title)")
        .accessibilityIdentifier("data-source-badge")
    }
}

private struct ServiceStatusPanel: View {
    let statuses: [ServiceStatus]
    let isStale: Bool

    private var abnormalStatuses: [ServiceStatus] {
        statuses.filter { $0.severity != .normal }
    }

    private var displayedStatuses: [ServiceStatus] {
        Array(abnormalStatuses.prefix(1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text("運行情報")
                    .font(RailFont.extraBold(.caption))
                if isStale {
                    Text("古い情報")
                        .font(RailFont.bold(.caption2))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
            }

            if abnormalStatuses.isEmpty {
                Label(
                    isStale ? "運行情報を取得できませんでした"
                        : statuses.contains(where: { $0.dataAccuracy == .estimated })
                            ? "列車位置情報では大きな遅れはありません（推定）"
                            : "表示中の\(statuses.count)路線は平常です",
                    systemImage: "checkmark.circle.fill"
                )
                .font(RailFont.bold(.subheadline))
                .foregroundStyle(isStale ? .orange : .green)
            } else {
                ForEach(displayedStatuses) { status in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: symbol(for: status.severity))
                            .foregroundStyle(color(for: status.severity))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(status.lineName)
                                .font(RailFont.extraBold(.caption))
                            if status.dataAccuracy == .estimated {
                                Label(
                                    "列車位置から補完",
                                    systemImage: "location.magnifyingglass"
                                )
                                .font(RailFont.bold(.caption2))
                                .foregroundStyle(.orange)
                            }
                            Text(status.message)
                                .font(RailFont.bold(.caption))
                                .lineLimit(2)
                            Text("\(status.updatedAt.formatted(date: .omitted, time: .shortened)) ・ \(status.dataAccuracy == .estimated ? "列車位置情報からの推定" : (status.sourceLabel ?? "ODPT"))")
                                .font(RailFont.regular(.caption2))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 2)
                    }
                    .accessibilityElement(children: .combine)
                }
                if abnormalStatuses.count > displayedStatuses.count {
                    Text("ほか\(abnormalStatuses.count - displayedStatuses.count)路線")
                        .font(RailFont.regular(.caption2))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .railPanel(cornerRadius: 13)
    }

    private func color(for severity: ServiceSeverity) -> Color {
        switch severity {
        case .normal: .green
        case .minor: .orange
        case .major: .red
        }
    }

    private func symbol(for severity: ServiceSeverity) -> String {
        switch severity {
        case .normal: "checkmark.circle.fill"
        case .minor: "exclamationmark.triangle.fill"
        case .major: "xmark.octagon.fill"
        }
    }
}

private struct ErrorPanel: View {
    let message: String
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(RailFont.regular(.caption))
                .lineLimit(3)
            Spacer(minLength: 4)
            if let onRetry {
                Button("再試行", action: onRetry)
                    .font(RailFont.bold(.caption))
                    .buttonStyle(.borderedProminent)
                    .tint(RailTheme.accent)
                    .minimumTapTarget()
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .railPanel(cornerRadius: 13)
    }
}

private struct NoticePanel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(RailFont.bold(.caption))
            .foregroundStyle(.orange)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .railPanel(cornerRadius: 13)
    }
}

private struct DataUpdatePanel: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        HStack(spacing: 6) {
            if viewModel.isLoadingTrains {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("更新中")
            } else {
                Image(
                    systemName: viewModel.trainsAreStale
                        ? "clock.badge.exclamationmark"
                        : "clock"
                )
                .foregroundStyle(viewModel.trainsAreStale ? .orange : .secondary)
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(updateText)
                    .font(RailFont.regular(.caption2))
                    .monospacedDigit()
                Text(nextUpdateText)
                    .font(RailFont.regular(.caption2))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .railPanel(cornerRadius: 11)
        .accessibilityElement(children: .combine)
    }

    private var updateText: String {
        guard let response = viewModel.trainsResponse else {
            return "列車データを取得中"
        }
        let prefix = viewModel.trainsAreStale
            ? "古いデータ・最終更新"
            : "最終更新"
        return "\(prefix) "
            + response.dataUpdatedAt.formatted(date: .omitted, time: .standard)
    }

    private var nextUpdateText: String {
        if viewModel.isOffline {
            return "オフライン中は更新停止"
        }
        guard let next = viewModel.nextTrainRefreshAt else {
            return "バックグラウンド中は更新停止"
        }
        let remaining = max(0, Int(ceil(next.timeIntervalSince(.now))))
        return "次回更新まで約 \(remaining)秒"
    }
}

private struct TrainFilterBar: View {
    @Binding var selection: TrainFilter
    let counts: [TrainFilter: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(TrainFilter.allCases) { filter in
                    let count = counts[filter] ?? 0
                    Button {
                        selection = filter
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filter.systemImage)
                                .accessibilityHidden(true)
                            Text(filter.label)
                            Text("\(count)")
                                .font(RailFont.extraBold(.caption2))
                                .monospacedDigit()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    (selection == filter
                                        ? Color.white
                                        : Color.secondary
                                    ).opacity(0.16),
                                    in: Capsule()
                                )
                        }
                            .font(RailFont.bold(.caption))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .frame(minHeight: 44)
                            .foregroundStyle(selection == filter ? .white : .primary)
                            .background(
                                selection == filter
                                    ? RailTheme.accent
                                    : Color(.systemBackground).opacity(0.96),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().stroke(
                                    .primary.opacity(0.2),
                                    lineWidth: 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)
                    .opacity(count == 0 ? 0.48 : 1)
                    .accessibilityLabel("\(filter.label)、\(count)件")
                    .accessibilityValue(
                        selection == filter
                            ? "選択中"
                            : count == 0 ? "該当列車なし" : ""
                    )
                    .accessibilityHint(
                        count == 0
                            ? "このフィルターは選択できません"
                            : "地図に表示する列車状態を絞り込みます"
                    )
                    .accessibilityAddTraits(
                        selection == filter ? .isSelected : []
                    )
                    .accessibilityIdentifier("train-filter-\(filter.rawValue)")
                }
            }
        }
        .frame(maxWidth: 520)
    }
}

private struct MapCircleButton: View {
    let systemName: String
    let foreground: Color
    let background: Color
    let label: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 48, height: 48)
                .background(background, in: Circle())
                .overlay {
                    Circle().stroke(.primary.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(label)
    }
}
