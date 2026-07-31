import Foundation

enum ServiceStatusLogic {
    static let trainFallbackMaximumAge: TimeInterval = 2 * 60
    static let trainTimestampFutureTolerance: TimeInterval = 30

    /// Web版と同じ優先順位で公式文面を解釈する。
    /// 運転再開の文脈を先に判定し、過去の見合わせを現在の見合わせと誤認しない。
    static func classifySeverity(from text: String) -> ServiceSeverity {
        switch textSignal(in: text) {
        case .resumed, .delay:
            .minor
        case .currentlySuspended:
            .major
        case .normal, .unknown:
            .normal
        }
    }

    /// APIの明示的な情報を優先しつつ、再開・現在見合わせの文脈だけを補正する。
    static func normalizedOfficialStatus(_ status: ServiceStatus) -> ServiceStatus {
        let normalizedSeverity: ServiceSeverity
        switch textSignal(in: status.message) {
        case .resumed:
            normalizedSeverity = .minor
        case .delay:
            // ODPTまたはWebバックエンドが明示した重大度は弱めない。
            normalizedSeverity = status.severity == .major ? .major : .minor
        case .currentlySuspended:
            normalizedSeverity = .major
        case .normal:
            normalizedSeverity = .normal
        case .unknown:
            // 未知の公式文面をクライアント側の推測で弱めない。
            normalizedSeverity = status.severity
        }

        guard normalizedSeverity != status.severity else {
            return status
        }
        return replacing(status, severity: normalizedSeverity)
    }

    static func resolvedStatuses(
        _ statuses: [ServiceStatus],
        trains: [TrainLocation],
        now: Date = .now
    ) -> [ServiceStatus] {
        statuses.map {
            statusWithTrainDelayFallback($0, trains: trains, now: now)
        }
    }

    /// 公式情報が平常または空相当でも、新鮮な列車情報に遅れがあれば平常と断定しない。
    /// 列車遅延から運転見合わせを推測することはない。
    static func statusWithTrainDelayFallback(
        _ status: ServiceStatus,
        trains: [TrainLocation],
        now: Date = .now
    ) -> ServiceStatus {
        let official = normalizedOfficialStatus(status)
        guard official.severity == .normal else {
            return official
        }

        let recentLineTrains = trains.filter { train in
            guard train.lineId == official.lineId else {
                return false
            }
            let age = now.timeIntervalSince(train.lastUpdatedAt)
            return age >= -trainTimestampFutureTolerance
                && age <= trainFallbackMaximumAge
        }
        guard !recentLineTrains.isEmpty else {
            return official
        }

        let delayedTrains = recentLineTrains.filter {
            $0.status == .delayed || $0.delayMinutes > 0
        }
        guard !delayedTrains.isEmpty else {
            return official
        }

        let maxDelayMinutes = delayedTrains
            .map { max(0, $0.delayMinutes) }
            .max() ?? 0
        let fifteenMinuteDelayCount = recentLineTrains.filter {
            $0.delayMinutes >= 15
        }.count
        let isMajorDelay = maxDelayMinutes >= 30
            || fifteenMinuteDelayCount * 2 >= recentLineTrains.count
        let latestTrainUpdate = delayedTrains
            .map(\.lastUpdatedAt)
            .max() ?? official.updatedAt

        let message: String
        if isMajorDelay {
            message = "列車位置情報では最大\(maxDelayMinutes)分の大幅な遅れが確認されています。公式の運行情報もあわせてご確認ください。"
        } else if maxDelayMinutes > 0 {
            message = "列車位置情報では最大\(maxDelayMinutes)分程度の遅れが確認されています。"
        } else {
            message = "列車位置情報で遅れが確認されています。公式の運行情報もあわせてご確認ください。"
        }

        return ServiceStatus(
            lineId: official.lineId,
            lineName: official.lineName,
            severity: isMajorDelay ? .major : .minor,
            message: message,
            updatedAt: latestTrainUpdate,
            dataAccuracy: .estimated
        )
    }

    private enum TextSignal {
        case resumed
        case currentlySuspended
        case delay
        case normal
        case unknown
    }

    private static func textSignal(in text: String) -> TextSignal {
        let compact = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")

        if containsAny(
            compact,
            phrases: [
                "運転再開", "運転を再開", "運転が再開", "再開し",
                "見合わせていましたが", "見合わせておりましたが"
            ]
        ) {
            return .resumed
        }

        if containsAny(
            compact,
            phrases: [
                "運転を見合わせています", "運転を見合わせております",
                "運転を見合せています", "運転を見合せております",
                "運転見合わせています", "運転見合わせております"
            ]
        ) {
            return .currentlySuspended
        }

        if containsAny(
            compact,
            phrases: [
                "遅れ", "遅延", "運休", "直通運転を中止", "一部列車",
                "運転変更", "運転見合わせ", "運転を見合"
            ]
        ) {
            return .delay
        }

        if containsAny(
            compact,
            phrases: ["平常", "通常どおり", "通常通り"]
        ) {
            return .normal
        }
        return .unknown
    }

    private static func containsAny(
        _ text: String,
        phrases: [String]
    ) -> Bool {
        phrases.contains(where: text.contains)
    }

    private static func replacing(
        _ status: ServiceStatus,
        severity: ServiceSeverity
    ) -> ServiceStatus {
        ServiceStatus(
            lineId: status.lineId,
            lineName: status.lineName,
            severity: severity,
            message: status.message,
            updatedAt: status.updatedAt,
            dataAccuracy: status.dataAccuracy
        )
    }
}
