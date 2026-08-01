import Foundation

@MainActor
final class MainViewModel: ObservableObject {
    static let trainRefreshInterval: TimeInterval = 7
    static let serviceRefreshInterval: TimeInterval = 30
    static let communityRefreshInterval: TimeInterval = 20

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

    @Published var selectedFilter: TrainFilter = .all
    @Published var selectedTrainID: String?

    let preferences: UserPreferences

    private let repository: TrainRepository
    private var trainPollingTask: Task<Void, Never>?
    private var servicePollingTask: Task<Void, Never>?
    private var communityPollingTask: Task<Void, Never>?
    private var railwayTask: Task<Void, Never>?
    private var isActive = false
    private var hasLoadedCache = false

    init(
        repository: TrainRepository,
        preferences: UserPreferences
    ) {
        self.repository = repository
        self.preferences = preferences
    }

    convenience init(configuration: AppConfiguration = .current) {
        self.init(
            repository: LiveTrainRepository(configuration: configuration),
            preferences: UserPreferences()
        )
    }

    convenience init(
        api: TrainAPIService,
        cache: ResponseCaching,
        preferences: UserPreferences
    ) {
        self.init(
            repository: LiveTrainRepository(api: api, cache: cache),
            preferences: preferences
        )
    }

    var selectedTrain: TrainLocation? {
        guard let selectedTrainID else {
            return nil
        }
        return trainsResponse?.trains.first { $0.id == selectedTrainID }
    }

    var selectableRailwayOptions: [RailwayFilterOption] {
        railwaysResponse?.selectableOptions ?? []
    }

    var visibleRailwayLines: [RailwayMapLine] {
        let visibleIDs = preferences.effectiveVisibleLineIDs
        return railwaysResponse?.lines.filter { visibleIDs.contains($0.id) } ?? []
    }

    var filteredTrains: [TrainLocation] {
        let visibleIDs = preferences.effectiveVisibleLineIDs
        return trainsResponse?.trains.filter {
            visibleIDs.contains($0.lineId) && selectedFilter.matches($0)
        } ?? []
    }

    var visibleServiceStatuses: [ServiceStatus] {
        let statuses = serviceStatusResponse?.allStatuses ?? []
        let canUseODPTTrainFallback = serviceStatusResponse?.source == .odpt
            && serviceStatusResponse?.isMock == false
            && serviceStatusResponse?.fallback == false
            && trainsResponse?.source == .odpt
            && trainsResponse?.isMock == false
            && trainsResponse?.fallback == false
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

        trainPollingTask = Task { [weak self] in
            await self?.runTrainPolling()
        }
        servicePollingTask = Task { [weak self] in
            await self?.runServicePolling()
        }
        communityPollingTask = Task { [weak self] in
            await self?.runCommunityPolling()
        }
        if railwaysResponse == nil {
            railwayTask = Task { [weak self] in
                await self?.refreshRailways()
            }
        }
    }

    func deactivate() {
        isActive = false
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
        deactivate()
        activate()
        railwayTask = Task { [weak self] in
            await self?.refreshRailways()
        }
    }

    func refreshTrains() async {
        isLoadingTrains = trainsResponse == nil
        defer { isLoadingTrains = false }
        do {
            let response = try await repository.refreshTrains()
            guard !Task.isCancelled else {
                return
            }
            trainsResponse = response
            trainsAreStale = false
            trainErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            trainsAreStale = trainsResponse != nil
            trainErrorMessage = Self.message(for: error, resource: "列車位置")
        }
    }

    func refreshServiceStatus() async {
        do {
            let response = try await repository.refreshServiceStatus()
            guard !Task.isCancelled else {
                return
            }
            serviceStatusResponse = response
            serviceStatusIsStale = false
            serviceErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            serviceStatusIsStale = serviceStatusResponse != nil
            serviceErrorMessage = Self.message(for: error, resource: "公式運行情報")
        }
    }

    func refreshRailways() async {
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
        } catch is CancellationError {
            return
        } catch {
            railwayErrorMessage = Self.message(for: error, resource: "路線情報")
        }
    }

    func refreshCommunityReports() async {
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
        delayMinutes: Int?
    ) async -> Bool {
        communitySuccessMessage = nil
        guard let vote = CommunityReportLogic.validatedVote(
            lineID: lineID,
            status: status,
            delayMinutes: delayMinutes
        ) else {
            communityErrorMessage = "投稿内容を確認してください。"
            return false
        }

        guard preferences.reporterIDIsSecurelyStored else {
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
            nextTrainRefreshAt = .now.addingTimeInterval(Self.trainRefreshInterval)
            do {
                try await Task.sleep(
                    for: .seconds(Self.trainRefreshInterval),
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
            do {
                try await Task.sleep(
                    for: .seconds(Self.serviceRefreshInterval),
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
}
