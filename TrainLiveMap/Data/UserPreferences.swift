import Foundation

@MainActor
final class UserPreferences: ObservableObject {
    private enum Key {
        static let visibleLineIDs = "train-live-map.visible-line-ids"
        static let favoriteLineIDs = "train-live-map.favorite-line-ids"
        static let favoritesOnly = "train-live-map.favorites-only"
        static let visibilityInitialized = "train-live-map.visibility-initialized"
    }

    @Published private(set) var visibleLineIDs: Set<String>
    @Published private(set) var favoriteLineIDs: Set<String>
    @Published private(set) var favoritesOnly: Bool

    private let defaults: UserDefaults
    private var visibilityInitialized: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        visibleLineIDs = Set(defaults.stringArray(forKey: Key.visibleLineIDs) ?? [])
        favoriteLineIDs = Set(defaults.stringArray(forKey: Key.favoriteLineIDs) ?? [])
        favoritesOnly = defaults.bool(forKey: Key.favoritesOnly)
        visibilityInitialized = defaults.bool(forKey: Key.visibilityInitialized)
    }

    var effectiveVisibleLineIDs: Set<String> {
        favoritesOnly
            ? visibleLineIDs.intersection(favoriteLineIDs)
            : visibleLineIDs
    }

    func reconcile(with options: [RailwayFilterOption]) {
        let knownIDs = Set(options.map(\.id))
        let availableIDs = Set(options.filter(\.available).map(\.id))

        favoriteLineIDs.formIntersection(knownIDs)
        if visibilityInitialized {
            visibleLineIDs.formIntersection(availableIDs)
        } else {
            let initialOption = options.first {
                $0.id == "tokaido" && $0.available
            } ?? options.first(where: \.available)
            visibleLineIDs = Set(initialOption.map { [$0.id] } ?? [])
            visibilityInitialized = true
            defaults.set(true, forKey: Key.visibilityInitialized)
        }
        persist()
    }

    func setVisibleLineIDs(_ ids: Set<String>) {
        visibleLineIDs = ids
        visibilityInitialized = true
        defaults.set(true, forKey: Key.visibilityInitialized)
        persist()
    }

    func toggleVisibility(for id: String) {
        if visibleLineIDs.contains(id) {
            visibleLineIDs.remove(id)
        } else {
            visibleLineIDs.insert(id)
        }
        visibilityInitialized = true
        defaults.set(true, forKey: Key.visibilityInitialized)
        persist()
    }

    func toggleFavorite(for id: String) {
        if favoriteLineIDs.contains(id) {
            favoriteLineIDs.remove(id)
        } else {
            favoriteLineIDs.insert(id)
        }
        persist()
    }

    func setFavoritesOnly(_ value: Bool) {
        favoritesOnly = value
        persist()
    }

    func showAll(_ options: [RailwayFilterOption]) {
        setVisibleLineIDs(Set(options.filter(\.available).map(\.id)))
    }

    func hideAll() {
        setVisibleLineIDs([])
    }

    private func persist() {
        defaults.set(visibleLineIDs.sorted(), forKey: Key.visibleLineIDs)
        defaults.set(favoriteLineIDs.sorted(), forKey: Key.favoriteLineIDs)
        defaults.set(favoritesOnly, forKey: Key.favoritesOnly)
    }
}
