import Foundation

enum TrainFace: Equatable {
    case smiling
    case troubled
    case sadWithTear
}

enum TrainPresentation {
    static func face(for train: TrainLocation) -> TrainFace {
        if train.status == .suspended {
            return .sadWithTear
        }
        if train.status == .delayed || train.delayMinutes > 0 {
            return .troubled
        }
        return .smiling
    }

    static func accessibilityLabel(for train: TrainLocation) -> String {
        var components = [
            train.lineName,
            train.direction.label,
            "行き先 \(train.destination)",
            train.status.label
        ]
        if train.delayMinutes > 0 {
            components.append("\(train.delayMinutes)分遅れ")
        }
        components.append(train.currentSegmentText)
        components.append(train.dataAccuracy.label)
        return components.joined(separator: "、")
    }

    static func delayBubbleText(for train: TrainLocation) -> String? {
        guard train.status != .suspended, train.delayMinutes > 0 else {
            return nil
        }
        return "+\(train.delayMinutes)分"
    }

    static func suspensionBadgeText(for train: TrainLocation) -> String? {
        train.status == .suspended ? "見合わせ" : nil
    }

    static func stoppedDurationText(for train: TrainLocation, now: Date = .now) -> String? {
        guard let stoppedSince = train.stoppedSince else {
            return nil
        }
        let seconds = max(0, Int(now.timeIntervalSince(stoppedSince)))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return minutes > 0 ? "\(minutes)分\(remainder)秒" : "\(remainder)秒"
    }
}

enum TrainFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case stopped
    case delayed
    case suspended

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "すべて"
        case .running: "走行中"
        case .stopped: "停車中"
        case .delayed: "遅延"
        case .suspended: "運転見合わせ"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "train.side.front.car"
        case .running: "arrow.forward.circle"
        case .stopped: "pause.circle"
        case .delayed: "exclamationmark.clock"
        case .suspended: "xmark.octagon"
        }
    }

    func matches(_ train: TrainLocation) -> Bool {
        switch self {
        case .all:
            true
        case .running:
            train.status == .running && train.delayMinutes == 0
        case .stopped:
            train.status == .stopped
        case .delayed:
            train.status == .delayed || (train.delayMinutes > 0 && train.status != .suspended)
        case .suspended:
            train.status == .suspended
        }
    }
}

struct DataSourcePresentation: Equatable {
    let title: String
    let detail: String?
    let isWarning: Bool

    init(response: TrainsAPIResponse) {
        if response.fallback {
            title = "モックデータ使用中"
            detail = response.notice ?? "ODPTライブを取得できないためモックデータを表示中"
            isWarning = true
        } else if response.isMock || response.source == .mock {
            title = "モックデータ使用中"
            detail = response.notice ?? "モックデータを表示中"
            isWarning = true
        } else if response.trains.contains(where: { $0.dataAccuracy == .estimated }) {
            title = "ODPTライブ（位置は駅間推定）"
            detail = "列車位置はGPS実測ではなく、駅間情報などからの推定です。"
            isWarning = false
        } else {
            title = "ODPTライブ（実データ）"
            detail = "APIが実データとして提供した位置です。"
            isWarning = false
        }
    }
}

enum RailwayFilterLogic {
    static func filtered(
        options: [RailwayFilterOption],
        query: String,
        favoritesOnly: Bool,
        favoriteIDs: Set<String>
    ) -> [RailwayFilterOption] {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return options.filter { option in
            guard option.isSelectable else {
                return false
            }
            if favoritesOnly && !favoriteIDs.contains(option.id) {
                return false
            }
            guard !normalized.isEmpty else {
                return true
            }
            let candidates = ([option.name, option.category] + option.aliases)
                .map {
                    $0.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    )
                }
            return candidates.contains {
                $0.localizedCaseInsensitiveContains(normalized)
            }
        }
    }
}
