import Foundation

enum RailwaySelectionLogic {
    /// Matches the Web app: first available option in each API-provided category.
    static func defaultVisibleIDs(
        from options: [RailwayFilterOption]
    ) -> Set<String> {
        var selectedCategories = Set<String>()
        var selectedIDs = Set<String>()

        for option in options where option.isSelectable {
            guard selectedCategories.insert(option.category).inserted else {
                continue
            }
            selectedIDs.insert(option.id)
        }
        return selectedIDs
    }

    static func filteredServiceStatuses(
        _ statuses: [ServiceStatus],
        visibleLineIDs: Set<String>
    ) -> [ServiceStatus] {
        guard !visibleLineIDs.isEmpty else {
            return []
        }
        return statuses
            .filter { visibleLineIDs.contains($0.lineId) }
            .sorted {
                if $0.severity.priority == $1.severity.priority {
                    return $0.lineName.localizedStandardCompare($1.lineName)
                        == .orderedAscending
                }
                return $0.severity.priority > $1.severity.priority
            }
    }
}

extension ServiceSeverity {
    var priority: Int {
        switch self {
        case .normal: 0
        case .minor: 1
        case .major: 2
        }
    }
}
