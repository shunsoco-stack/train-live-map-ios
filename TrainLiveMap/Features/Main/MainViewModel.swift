import Foundation

@MainActor
final class MainViewModel: ObservableObject {
    static let trainRefreshInterval: TimeInterval = 10
    static let serviceRefreshInterval: TimeInterval = 10
    static let communityRefreshInterval: TimeInterval = 10

    @Published private(set) var trainsResponse: TrainsAPIResponse?
    @Published private(set) var serviceStatusResponse: ServiceStatusAPIResponse?
    @Published private(set) var railwaysResponse: RailwaysAPIResponse?
    @Published private(set) var communityReportsResponse: CommunityReportsAPIResponse?

    @Published private(set) var trainsAreStale = false
    @Published private(set) var serviceStatusIsStale = false
    @Published private(set) var communityReportsAreStale = false

    @Published private(set) var trainErrorMessage: String?
    @Published private(set) var serviceErrorMessage: String?
    @Published private(set) var railwayErrorMessage: String?
    @Published private(set) var communityErrorMessage: String?
    @Published private(set) var communitySuccessMessage: String?

    @Published private(set) var isLoadingTrains = false
    @Published private(set) var isLoadingRailways = false
    @Published private(set) var isLoadingCommunityReports = false
    @Published private(set) var isSubmittingCommunityReport = false
    @Published private(set) var nextTrainRefreshAt: Date?
    @Published private(set) var isOffline = false

    @Published var selectedFilter: TrainFilter = .all
    @Published var selectedTrainID: String?

    let preferences: UserPreferences

    private let repository: TrainRepository
    private let connectivityMonitor: NetworkConnectivityMonitoring
    private var trainPollingTask: Task<Void, Never>?
    private var servicePollingTask: Task<Void, Never>?
    private var communityPollingTask: Task<Void, Never>?
    private var railwayTask: Task<Void, Never>?
    private var connectivityTask: Task<Void, Never>?
    private var isActive = false
    private var hasLoadedCache = false
    private var hasCompletedStartupRailwayRefresh = false
    private var isRefreshingTrains = false
    private var isRefreshingServiceStatus = false
    private var isRefreshingRailways = false
    private var isRefreshingCommunityReports = false
    private var trainBadRequestLineIDs: Set<String>?
    private var serviceBadRequestLineIDs: Set<String>?
    private var trainRetryNotBefore: Date?
    private var serviceRetryNotBefore: Date?

    init(
        repository: TrainRepository,
        preferences: UserPreferences,
        connectivityMonitor: NetworkConnectivityMonitoring =
            NWPathConnectivityMonitor()
    ) {
        self.repository = repository
        self.preferences = preferences
        self.connectivityMonitor = connectivityMonitor
        isOffline = connectivityMonitor.currentStatus == .offline
    }

    convenience init(configuration: AppConfiguration = .current) {
        self.init(
            repository: LiveTrainRepository(configuration: configuration),
            preferences: UserPreferences(),
            connectivityMonitor: NWPathConnectivityMonitor()
        )
    }

    convenience init(
        api: TrainAPIService,
        cache: ResponseCaching,
        preferences: UserPreferences,
        connectivityMonitor: NetworkConnectivityMonitoring =
            AssumedOnlineConnectivityMonitor()
    ) {
        self.init(
            repository: LiveTrainRepository(api: api, cache: cache),
            preferences: preferences,
            connectivityMonitor: connectivityMonitor
        )
    }

    var selectedTrain: TrainLocation? {
        guard let selectedTrainID else {
            return nil
        }
        return currentTrains.first { $0.id == selectedTrainID }
    }

    var selectableRailwayOptions: [RailwayFilterOption] {
        railwaysResponse?.selectableOptions ?? []
    }

    var visibleRailwayLines: [RailwayMapLine] {
        let visibleIDs = preferences.effectiveVisibleLineIDs
        return railwaysResponse?.lines.filter { visibleIDs.contains($0.id) } ?? []
    }

    var filteredTrains: [TrainLocation] {
        currentTrains.filter(selectedFilter.matches)
    }

    /// Keep the last successful snapshot visible during an online API failure,
    /// with `trainsAreStale` driving the warning UI. Once connectivity is known
    /// to be offline, never present that historical snapshot as a current map or
    /// search result.
    var currentTrains: [TrainLocation] {
        guard !isOffline else {
            return []
        }
        let visibleIDs = preferences.effectiveVisibleLineIDs
        let suspendedIDs: Set<String> = serviceErrorMessage == nil
            && serviceStatusResponse?.isMock == false && serviceStatusResponse?.fallback == false
            ? Set((serviceStatusResponse?.allStatuses ?? [])
                .filter { ServiceStatusLogic.confirmsSuspension($0) }.map(\.lineId)) : []
        var seen = Set<String>()
        return (trainsResponse?.trains ?? []).filter {
            visibleIDs.contains($0.lineId) && $0.coordinate.isFinite
                && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
                && seen.insert($0.id).inserted
        }.map { train in
            var displayed = train
            if suspendedIDs.contains(train.lineId) { displayed.status = .suspended }
            return displayed
        }
    }

    /// Whether a user-initiated retry can issue a train request right now.
    /// A disabled retry is important here: HTTP 400 remains blocked until the
    /// selected line set changes, while HTTP 429/503 remain blocked until the
    /// server-provided (or safe default) retry deadline.
    var canRetryTrainRequest: Bool {
        let lineIDs = preferences.effectiveVisibleLineIDs
        guard isActive,
              !isOffline,
              !isLoadingTrains,
              !isRefreshingTrains,
              !lineIDs.isEmpty else {
            return false
        }
        if trainBadRequestLineIDs == lineIDs {
            return false
        }
        if let trainRetryNotBefore, trainRetryNotBefore > .now {
            return false
        }
        return true
    }

    var canRetryServiceStatusRequest: Bool {
        let lineIDs = preferences.effectiveVisibleLineIDs
        guard serviceErrorMessage != nil,
              isActive,
              !isOffline,
              !isRefreshingServiceStatus,
              !lineIDs.isEmpty else {
            return false
        }
        if serviceBadRequestLineIDs == lineIDs {
            return false
        }
        if let serviceRetryNotBefore, serviceRetryNotBefore > .now {
            return false
        }
        return true
    }

    var canRetryRailwayRequest: Bool {
        isActive
            && !isOffline
            && !isLoadingRailways
            && !isRefreshingRailways
            && railwayErrorMessage != nil
    }

    /// Explanation shown inside the single train empty-state surface when a
    /// retry is intentionally suppressed.
    var trainRetrySuppressionMessage: String? {
        let lineIDs = preferences.effectiveVisibleLineIDs
        if isOffline {
            return "オフライン中は再送しません。接続が戻ると自動で更新します。"
        }
        if trainBadRequestLineIDs == lineIDs {
            return "この路線指定では再送を停止しています。路線選択を変更してください。"
        }
        if let trainRetryNotBefore, trainRetryNotBefore > .now {
            let time = trainRetryNotBefore.formatted(
                date: .omitted,
                time: .shortened
            )
            return "サーバーの指定に従い、\(time)までは再送しません。"
        }
        return nil
    }

    var serviceRetrySuppressionMessage: String? {
        let lineIDs = preferences.effectiveVisibleLineIDs
        if isOffline {
            return "オフライン中は公式運行情報を再送しません。"
        }
        if serviceBadRequestLineIDs == lineIDs {
            return "この路線指定では公式運行情報の再送を停止しています。路線選択を変更してください。"
        }
        if let serviceRetryNotBefore, serviceRetryNotBefore > .now {
            let time = serviceRetryNotBefore.formatted(
                date: .omitted,
                time: .shortened
            )
            return "サーバーの指定に従い、公式運行情報は\(time)までは再送しません。"
        }
        return nil
    }

    var visibleServiceStatuses: [ServiceStatus] {
        let statuses = serviceStatusResponse?.allStatuses ?? []
        let canUseODPTTrainFallback = serviceStatusResponse?.source == .odpt
            && serviceStatusResponse?.isMock == false
            && serviceStatusResponse?.fallback == false
            && trainsResponse?.source == .odpt
            && trainsResponse?.isMock == false
            && trainsResponse?.fallback == false
            && !trainsAreStale
        let resolvedStatuses = ServiceStatusLogic.resolvedStatuses(
            statuses,
            trains: canUseODPTTrainFallback ? trainsResponse?.trains ?? [] : []
        )
        return RailwaySelectionLogic.filteredServiceStatuses(
            resolvedStatuses,
            visibleLineIDs: preferences.effectiveVisibleLineIDs
        )
    }

    var visibleCommunitySummaries: [CommunityReportSummary] {
        let visibleIDs = preferences.effectiveVisibleLineIDs
        return communityReportsResponse?.summaries
            .filter { visibleIDs.contains($0.lineId) }
            .sorted {
                if $0.status.severityPriority == $1.status.severityPriority {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.status.severityPriority > $1.status.severityPriority
            } ?? []
    }

    func loadCachedDataIfNeeded() async {
        guard !hasLoadedCache else {
            return
        }
        hasLoadedCache = true
        let cached = await repository.loadCachedData()

        if trainsResponse == nil, let trains = cached.trains {
            trainsResponse = trains
            trainsAreStale = true
        }
        if serviceStatusResponse == nil, let service = cached.serviceStatus {
            serviceStatusResponse = service
            serviceStatusIsStale = true
        }
        if railwaysResponse == nil, let railways = cached.railways {
            railwaysResponse = railways
            preferences.reconcile(with: railways.options)
        }
        if communityReportsResponse == nil,
           let community = cached.communityReports {
            communityReportsResponse = community
            communityReportsAreStale = true
        }
    }

    func activate() {
        guard !isActive else {
            return
        }
        isActive = true

        isOffline = connectivityMonitor.currentStatus == .offline
        connectivityTask = Task { [weak self, connectivityMonitor] in
            for await status in connectivityMonitor.statusUpdates() {
                guard !Task.isCancelled else {
                    return
                }
                self?.networkStatusDidChange(status)
            }
        }
        guard !isOffline else {
            markNetworkDataUnavailable()
            return
        }
        startNetworkTasks()
    }

    func deactivate() {
        isActive = false
        connectivityTask?.cancel()
        connectivityTask = nil
        cancelNetworkTasks()
    }

    private func cancelNetworkTasks() {
        trainPollingTask?.cancel()
        servicePollingTask?.cancel()
        communityPollingTask?.cancel()
        railwayTask?.cancel()
        trainPollingTask = nil
        servicePollingTask = nil
        communityPollingTask = nil
        railwayTask = nil
        nextTrainRefreshAt = nil
    }

    func retryAll() {
        guard isActive else {
            return
        }
        hasCompletedStartupRailwayRefresh = false
        deactivate()
        activate()
    }

    func refreshTrains() async {
        guard !isOffline else {
            return
        }
        let lineIDs = preferences.effectiveVisibleLineIDs
        guard !lineIDs.isEmpty else {
            isLoadingTrains = false
            trainErrorMessage = nil
            selectedTrainID = nil
            return
        }
        if let blocked = trainBadRequestLineIDs {
            guard blocked != lineIDs else {
                return
            }
            trainBadRequestLineIDs = nil
        }
        if let retryNotBefore = trainRetryNotBefore,
           retryNotBefore > .now {
            return
        }
        guard !isRefreshingTrains else {
            return
        }
        isRefreshingTrains = true
        defer { isRefreshingTrains = false }

        isLoadingTrains = trainsResponse == nil
        defer { isLoadingTrains = false }
        do {
            let response = try await repository.refreshTrains(lineIDs: lineIDs)
            guard !Task.isCancelled else {
                return
            }
            trainsResponse = response
            trainsAreStale = false
            trainErrorMessage = nil
            trainRetryNotBefore = nil
        } catch is CancellationError {
            return
        } catch {
            trainsAreStale = trainsResponse != nil
            trainErrorMessage = Self.message(for: error, resource: "列車位置")
            applyTrainRequestSuppression(for: error, lineIDs: lineIDs)
        }
    }

    func refreshServiceStatus() async {
        guard !isOffline else {
            return
        }
        let lineIDs = preferences.effectiveVisibleLineIDs
        guard !lineIDs.isEmpty else {
            serviceErrorMessage = nil
            return
        }
        if let blocked = serviceBadRequestLineIDs {
            guard blocked != lineIDs else {
                return
            }
            serviceBadRequestLineIDs = nil
        }
        if let retryNotBefore = serviceRetryNotBefore,
           retryNotBefore > .now {
            return
        }
        guard !isRefreshingServiceStatus else {
            return
        }
        isRefreshingServiceStatus = true
        defer { isRefreshingServiceStatus = false }

        do {
            let response = try await repository.refreshServiceStatus(
                lineIDs: lineIDs
            )
            guard !Task.isCancelled else {
                return
            }
            serviceStatusResponse = response
            serviceStatusIsStale = false
            serviceErrorMessage = nil
            serviceRetryNotBefore = nil
        } catch is CancellationError {
            return
        } catch {
            serviceStatusIsStale = serviceStatusResponse != nil
            serviceErrorMessage = Self.message(for: error, resource: "公式運行情報")
            applyServiceRequestSuppression(for: error, lineIDs: lineIDs)
        }
    }

    func refreshRailways() async {
        guard !isOffline else {
            return
        }
        guard !isRefreshingRailways else {
            return
        }
        isRefreshingRailways = true
        defer { isRefreshingRailways = false }

        isLoadingRailways = railwaysResponse == nil
        defer { isLoadingRailways = false }
        do {
            let response = try await repository.refreshRailways()
            guard !Task.isCancelled else {
                return
            }
            railwaysResponse = response
            railwayErrorMessage = nil
            preferences.reconcile(with: response.options)
            if hasCompletedStartupRailwayRefresh {
                startSelectedLinePollingTasks()
            }
        } catch is CancellationError {
            return
        } catch {
            railwayErrorMessage = Self.message(for: error, resource: "路線情報")
        }
    }

    func refreshCommunityReports() async {
        guard !isOffline else {
            return
        }
        guard !isRefreshingCommunityReports else {
            return
        }
        isRefreshingCommunityReports = true
        defer { isRefreshingCommunityReports = false }

        isLoadingCommunityReports = communityReportsResponse == nil
        defer { isLoadingCommunityReports = false }
        do {
            let response = try await repository.refreshCommunityReports()
            guard !Task.isCancelled else {
                return
            }
            communityReportsResponse = response
            communityReportsAreStale = false
            communityErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            communityReportsAreStale = communityReportsResponse != nil
            communityErrorMessage = Self.message(
                for: error,
                resource: "みんなの運行情報"
            )
        }
    }

    @discardableResult
    func submitCommunityReport(
        lineID: String,
        status: CommunityReportStatus,
        delayMinutes: Int?,
        isResumption: Bool = false
    ) async -> Bool {
        communitySuccessMessage = nil
        guard !isSubmittingCommunityReport else {
            communityErrorMessage = "投稿を送信中です。完了までお待ちください。"
            return false
        }
        guard !isOffline else {
            communityErrorMessage =
                "オフラインのため、接続が戻るまで投稿を送信しません。"
            return false
        }
        guard var vote = CommunityReportLogic.validatedVote(
            lineID: lineID,
            status: status,
            delayMinutes: delayMinutes
        ) else {
            communityErrorMessage = "投稿内容を確認してください。"
            return false
        }

        if isResumption && status == .onTime { vote.event = "resumed" }

        guard preferences.reporterIDIsSecurelyStored,
              CommunityReporterIDValidator.isValid(preferences.reporterID) else {
            communityErrorMessage =
                "匿名端末IDをKeychainへ安全に保存できないため、投稿を送信しません。"
            return false
        }

        let serverRetryRemaining = preferences.remainingCommunityRetry()
        guard serverRetryRemaining == 0 else {
            communityErrorMessage =
                "投稿が制限されています。あと\(serverRetryRemaining)秒は再送できません。"
            return false
        }

        let cooldown = communityReportsResponse?.cooldownSeconds ?? 60
        let remaining = preferences.remainingCommunityCooldown(
            lineID: lineID,
            cooldownSeconds: cooldown
        )
        guard remaining == 0 else {
            communityErrorMessage = "同じ路線には\(remaining)秒後に再投稿できます。"
            return false
        }

        isSubmittingCommunityReport = true
        defer { isSubmittingCommunityReport = false }
        do {
            let response = try await repository.submitCommunityReport(
                vote,
                reporterID: preferences.reporterID
            )
            communityReportsResponse = response.reportsResponse
            communityReportsAreStale = false
            communityErrorMessage = nil
            communitySuccessMessage = "投稿しました。みんなの情報として共有されます。"
            preferences.recordCommunitySubmission(lineID: lineID)
            return true
        } catch let APIClientError.rateLimited(retryAfter, message) {
            preferences.recordCommunityRetry(until: retryAfter)
            let remaining = preferences.remainingCommunityRetry()
            communityErrorMessage = remaining > 0
                ? "\(message) あと\(remaining)秒は再送しません。"
                : message
            return false
        } catch let APIClientError.serviceUnavailable(retryAfter, message) {
            preferences.recordCommunityRetry(until: retryAfter)
            let remaining = preferences.remainingCommunityRetry()
            communityErrorMessage = remaining > 0
                ? "\(message) あと\(remaining)秒は再送しません。"
                : message
            return false
        } catch {
            communityErrorMessage = Self.message(
                for: error,
                resource: "みんなの情報"
            )
            return false
        }
    }

    func clearCommunityFeedback() {
        communityErrorMessage = nil
        communitySuccessMessage = nil
    }

    private func runTrainPolling() async {
        while !Task.isCancelled {
            await refreshTrains()
            guard !Task.isCancelled else {
                return
            }
            let delay = trainPollingDelay()
            nextTrainRefreshAt = .now.addingTimeInterval(delay)
            do {
                try await Task.sleep(
                    for: .seconds(delay),
                    clock: .continuous
                )
            } catch {
                return
            }
        }
    }

    private func runServicePolling() async {
        while !Task.isCancelled {
            await refreshServiceStatus()
            guard !Task.isCancelled else {
                return
            }
            let delay = servicePollingDelay()
            do {
                try await Task.sleep(
                    for: .seconds(delay),
                    clock: .continuous
                )
            } catch {
                return
            }
        }
    }

    private func runCommunityPolling() async {
        while !Task.isCancelled {
            await refreshCommunityReports()
            guard !Task.isCancelled else {
                return
            }
            do {
                try await Task.sleep(
                    for: .seconds(Self.communityRefreshInterval),
                    clock: .continuous
                )
            } catch {
                return
            }
        }
    }

    private static func message(for error: Error, resource: String) -> String {
        let detail = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        return "\(resource)を更新できませんでした。\(detail)"
    }

    private func startNetworkTasks() {
        guard isActive, !isOffline else {
            return
        }
        if communityPollingTask == nil {
            communityPollingTask = Task { [weak self] in
                await self?.runCommunityPolling()
            }
        }

        // Cached railway metadata keeps the selector usable offline, but the
        // server response remains authoritative. Refresh it once per app
        // startup before the first selected-line request so renamed/removed
        // IDs cannot linger and trigger a second request after reconciliation.
        if !hasCompletedStartupRailwayRefresh, railwayTask == nil {
            railwayTask = Task { [weak self] in
                guard let self else {
                    return
                }
                while self.isRefreshingRailways {
                    do {
                        try await Task.sleep(for: .milliseconds(10))
                    } catch {
                        return
                    }
                }
                guard self.isActive, !self.isOffline, !Task.isCancelled else {
                    return
                }
                await self.refreshRailways()
                guard !Task.isCancelled else {
                    return
                }
                self.hasCompletedStartupRailwayRefresh = true
                self.railwayTask = nil
                self.startSelectedLinePollingTasks()
            }
            return
        }

        guard hasCompletedStartupRailwayRefresh else {
            return
        }

        guard railwaysResponse != nil else {
            return
        }
        startSelectedLinePollingTasks()
    }

    private func startSelectedLinePollingTasks() {
        guard isActive, !isOffline, railwaysResponse != nil else {
            return
        }
        if trainPollingTask == nil {
            trainPollingTask = Task { [weak self] in
                await self?.runTrainPolling()
            }
        }
        if servicePollingTask == nil {
            servicePollingTask = Task { [weak self] in
                await self?.runServicePolling()
            }
        }
    }

    private func networkStatusDidChange(_ status: NetworkConnectivityStatus) {
        guard status != .unknown else {
            return
        }
        let nowOffline = status == .offline
        guard nowOffline != isOffline else {
            return
        }
        isOffline = nowOffline
        if nowOffline {
            markNetworkDataUnavailable()
            cancelNetworkTasks()
        } else {
            startNetworkTasks()
        }
    }

    private func markNetworkDataUnavailable() {
        trainsAreStale = trainsResponse != nil
        serviceStatusIsStale = serviceStatusResponse != nil
        communityReportsAreStale = communityReportsResponse != nil
        selectedTrainID = nil
        nextTrainRefreshAt = nil
    }

    private func applyTrainRequestSuppression(
        for error: Error,
        lineIDs: Set<String>
    ) {
        switch error as? APIClientError {
        case .badRequest, .invalidLineIDs:
            trainBadRequestLineIDs = lineIDs
        case let .rateLimited(retryAfter, _),
             let .serviceUnavailable(retryAfter, _):
            trainRetryNotBefore = retryAfter
        default:
            break
        }
    }

    private func applyServiceRequestSuppression(
        for error: Error,
        lineIDs: Set<String>
    ) {
        switch error as? APIClientError {
        case .badRequest, .invalidLineIDs:
            serviceBadRequestLineIDs = lineIDs
        case let .rateLimited(retryAfter, _),
             let .serviceUnavailable(retryAfter, _):
            serviceRetryNotBefore = retryAfter
        default:
            break
        }
    }

    private func trainPollingDelay(now: Date = .now) -> TimeInterval {
        guard let trainRetryNotBefore, trainRetryNotBefore > now else {
            return Self.trainRefreshInterval
        }
        return max(
            Self.trainRefreshInterval,
            trainRetryNotBefore.timeIntervalSince(now)
        )
    }

    private func servicePollingDelay(now: Date = .now) -> TimeInterval {
        guard let serviceRetryNotBefore, serviceRetryNotBefore > now else {
            return Self.serviceRefreshInterval
        }
        return max(
            Self.serviceRefreshInterval,
            serviceRetryNotBefore.timeIntervalSince(now)
        )
    }
}
