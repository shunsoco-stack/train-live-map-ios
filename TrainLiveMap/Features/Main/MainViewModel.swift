import Foundation

@MainActor
final class MainViewModel: ObservableObject {
    static let trainRefreshInterval: TimeInterval = 7
    static let serviceRefreshInterval: TimeInterval = 30

    @Published private(set) var trainsResponse: TrainsAPIResponse?
    @Published private(set) var serviceStatusResponse: ServiceStatusAPIResponse?
    @Published private(set) var railwaysResponse: RailwaysAPIResponse?
    @Published private(set) var trainsAreStale = false
    @Published private(set) var serviceStatusIsStale = false
    @Published private(set) var trainErrorMessage: String?
    @Published private(set) var serviceErrorMessage: String?
    @Published private(set) var railwayErrorMessage: String?
    @Published private(set) var isLoadingTrains = false
    @Published private(set) var isLoadingRailways = false
    @Published private(set) var nextTrainRefreshAt: Date?
    @Published var selectedFilter: TrainFilter = .all
    @Published var selectedTrainID: String?

    let preferences: UserPreferences

    private let api: TrainAPIService
    private let cache: ResponseCaching
    private var trainPollingTask: Task<Void, Never>?
    private var servicePollingTask: Task<Void, Never>?
    private var railwayTask: Task<Void, Never>?
    private var isActive = false
    private var hasLoadedCache = false

    init(
        api: TrainAPIService,
        cache: ResponseCaching,
        preferences: UserPreferences
    ) {
        self.api = api
        self.cache = cache
        self.preferences = preferences
    }

    convenience init(configuration: AppConfiguration = .current) {
        self.init(
            api: URLSessionTrainAPIService(baseURL: configuration.apiBaseURL),
            cache: FileResponseCache(),
            preferences: UserPreferences()
        )
    }

    var selectedTrain: TrainLocation? {
        guard let selectedTrainID else {
            return nil
        }
        return trainsResponse?.trains.first { $0.id == selectedTrainID }
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

    func loadCachedDataIfNeeded() async {
        guard !hasLoadedCache else {
            return
        }
        hasLoadedCache = true

        async let trains = cache.loadTrains()
        async let service = cache.loadServiceStatus()
        async let railways = cache.loadRailways()
        let cached = await (trains, service, railways)

        if trainsResponse == nil, let cachedTrains = cached.0 {
            trainsResponse = cachedTrains
            trainsAreStale = true
        }
        if serviceStatusResponse == nil, let cachedService = cached.1 {
            serviceStatusResponse = cachedService
            serviceStatusIsStale = true
        }
        if railwaysResponse == nil, let cachedRailways = cached.2 {
            railwaysResponse = cachedRailways
            preferences.reconcile(with: cachedRailways.options)
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
        railwayTask?.cancel()
        trainPollingTask = nil
        servicePollingTask = nil
        railwayTask = nil
        nextTrainRefreshAt = nil
    }

    func retryAll() {
        guard isActive else {
            return
        }
        trainPollingTask?.cancel()
        servicePollingTask?.cancel()
        railwayTask?.cancel()
        trainPollingTask = Task { [weak self] in
            await self?.runTrainPolling()
        }
        servicePollingTask = Task { [weak self] in
            await self?.runServicePolling()
        }
        railwayTask = Task { [weak self] in
            await self?.refreshRailways()
        }
    }

    func refreshTrains() async {
        isLoadingTrains = trainsResponse == nil
        defer { isLoadingTrains = false }
        do {
            let response = try await api.fetchTrains()
            guard !Task.isCancelled else {
                return
            }
            trainsResponse = response
            trainsAreStale = false
            trainErrorMessage = nil
            await cache.saveTrains(response)
        } catch is CancellationError {
            return
        } catch {
            trainsAreStale = trainsResponse != nil
            trainErrorMessage = Self.message(for: error, resource: "列車位置")
            if trainsResponse == nil, let cached = await cache.loadTrains() {
                trainsResponse = cached
                trainsAreStale = true
            }
        }
    }

    func refreshServiceStatus() async {
        do {
            let response = try await api.fetchServiceStatus()
            guard !Task.isCancelled else {
                return
            }
            serviceStatusResponse = response
            serviceStatusIsStale = false
            serviceErrorMessage = nil
            await cache.saveServiceStatus(response)
        } catch is CancellationError {
            return
        } catch {
            serviceStatusIsStale = serviceStatusResponse != nil
            serviceErrorMessage = Self.message(for: error, resource: "運行情報")
            if serviceStatusResponse == nil, let cached = await cache.loadServiceStatus() {
                serviceStatusResponse = cached
                serviceStatusIsStale = true
            }
        }
    }

    func refreshRailways() async {
        isLoadingRailways = railwaysResponse == nil
        defer { isLoadingRailways = false }
        do {
            let response = try await api.fetchRailways()
            guard !Task.isCancelled else {
                return
            }
            railwaysResponse = response
            railwayErrorMessage = nil
            preferences.reconcile(with: response.options)
            await cache.saveRailways(response)
        } catch is CancellationError {
            return
        } catch {
            railwayErrorMessage = Self.message(for: error, resource: "路線情報")
            if railwaysResponse == nil, let cached = await cache.loadRailways() {
                railwaysResponse = cached
                preferences.reconcile(with: cached.options)
            }
        }
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

    private static func message(for error: Error, resource: String) -> String {
        let detail = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        return "\(resource)を更新できませんでした。\(detail)"
    }
}
