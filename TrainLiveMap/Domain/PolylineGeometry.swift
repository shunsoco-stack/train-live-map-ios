import Foundation

struct PolylineGeometry: Equatable {
    let coordinates: [MapCoordinate]
    private let cumulativeMeters: [Double]
    let totalMeters: Double

    init(coordinates: [MapCoordinate]) {
        self.coordinates = coordinates.filter(\.isFinite)
        var cumulative = [0.0]
        if self.coordinates.count > 1 {
            for index in 1..<self.coordinates.count {
                cumulative.append(
                    cumulative[index - 1] + Self.distance(
                        self.coordinates[index - 1],
                        self.coordinates[index]
                    )
                )
            }
        }
        cumulativeMeters = cumulative
        totalMeters = cumulative.last ?? 0
    }

    static func clampUnit(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }

    func coordinate(at fraction: Double) -> MapCoordinate? {
        guard let first = coordinates.first else {
            return nil
        }
        guard coordinates.count > 1, totalMeters > 0 else {
            return first
        }

        let target = Self.clampUnit(fraction) * totalMeters
        let upperIndex = cumulativeMeters.firstIndex(where: { $0 >= target })
            ?? cumulativeMeters.index(before: cumulativeMeters.endIndex)
        guard upperIndex > 0 else {
            return first
        }

        let lowerIndex = upperIndex - 1
        let segmentLength = cumulativeMeters[upperIndex] - cumulativeMeters[lowerIndex]
        let progress = segmentLength > 0
            ? (target - cumulativeMeters[lowerIndex]) / segmentLength
            : 0
        let start = coordinates[lowerIndex]
        let end = coordinates[upperIndex]
        return MapCoordinate(
            longitude: start.longitude + (end.longitude - start.longitude) * progress,
            latitude: start.latitude + (end.latitude - start.latitude) * progress
        )
    }

    func fraction(closestTo target: MapCoordinate) -> Double {
        guard coordinates.count > 1, totalMeters > 0, target.isFinite else {
            return 0
        }

        var bestSquaredDistance = Double.greatestFiniteMagnitude
        var bestDistanceAlongLine = 0.0
        let latitudeScale = cos(target.latitude * .pi / 180)

        for index in 1..<coordinates.count {
            let start = coordinates[index - 1]
            let end = coordinates[index]
            let ax = start.longitude * latitudeScale
            let ay = start.latitude
            let bx = end.longitude * latitudeScale
            let by = end.latitude
            let px = target.longitude * latitudeScale
            let py = target.latitude
            let dx = bx - ax
            let dy = by - ay
            let denominator = dx * dx + dy * dy
            let rawProgress = denominator > 0
                ? ((px - ax) * dx + (py - ay) * dy) / denominator
                : 0
            let progress = Self.clampUnit(rawProgress)
            let nearestX = ax + dx * progress
            let nearestY = ay + dy * progress
            let squaredDistance = pow(px - nearestX, 2) + pow(py - nearestY, 2)
            if squaredDistance < bestSquaredDistance {
                bestSquaredDistance = squaredDistance
                let segmentMeters = cumulativeMeters[index] - cumulativeMeters[index - 1]
                bestDistanceAlongLine = cumulativeMeters[index - 1] + segmentMeters * progress
            }
        }

        return Self.clampUnit(bestDistanceAlongLine / totalMeters)
    }

    func clampedCoordinate(for target: MapCoordinate) -> MapCoordinate? {
        coordinate(at: fraction(closestTo: target))
    }

    static func interpolate(
        fromFraction: Double,
        toFraction: Double,
        progress: Double
    ) -> Double {
        let start = clampUnit(fromFraction)
        let end = clampUnit(toFraction)
        let amount = clampUnit(progress)
        return clampUnit(start + (end - start) * amount)
    }

    private static func distance(_ lhs: MapCoordinate, _ rhs: MapCoordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = lhs.latitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLongitude = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2)
            * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

final class TrainMotionEngine {
    private struct State {
        let geometry: PolylineGeometry
        let startFraction: Double
        let targetFraction: Double
        let startedAt: Date
        let duration: TimeInterval

        func coordinate(at date: Date) -> MapCoordinate? {
            guard duration > 0 else {
                return geometry.coordinate(at: targetFraction)
            }
            let linearProgress = PolylineGeometry.clampUnit(
                date.timeIntervalSince(startedAt) / duration
            )
            let eased = linearProgress * linearProgress * (3 - 2 * linearProgress)
            let fraction = PolylineGeometry.interpolate(
                fromFraction: startFraction,
                toFraction: targetFraction,
                progress: eased
            )
            return geometry.coordinate(at: fraction)
        }

        func isAnimating(at date: Date) -> Bool {
            date.timeIntervalSince(startedAt) < duration
        }
    }

    private var states: [String: State] = [:]

    func ingest(
        trains: [TrainLocation],
        railwayLines: [RailwayMapLine],
        at date: Date,
        motionEnabled: Bool = true
    ) {
        let linesByID = Dictionary(uniqueKeysWithValues: railwayLines.map { ($0.id, $0) })
        let incomingIDs = Set(trains.map(\.id))
        states = states.filter { incomingIDs.contains($0.key) }

        for train in trains {
            let geometry = geometry(for: train, line: linesByID[train.lineId])
            guard !geometry.coordinates.isEmpty else {
                continue
            }

            let observedFraction = geometry.fraction(closestTo: train.coordinate)
            let advancesWithinEstimate = shouldAdvanceEstimatedPosition(for: train)
            let targetFraction = targetFraction(
                observed: observedFraction,
                train: train,
                advancesWithinEstimate: advancesWithinEstimate
            )
            let previousCoordinate = states[train.id]?.coordinate(at: date)
            let projectedStart = previousCoordinate.map {
                geometry.fraction(closestTo: $0)
            } ?? (advancesWithinEstimate ? observedFraction : targetFraction)
            let startFraction = segmentConstrainedFraction(
                projectedStart,
                segment: advancesWithinEstimate ? train.routeSegment : nil
            )
            let startCoordinate = geometry.coordinate(at: startFraction) ?? train.coordinate
            let targetCoordinate = geometry.coordinate(at: targetFraction) ?? train.coordinate
            let distance = PolylineGeometry(coordinates: [startCoordinate, targetCoordinate])
                .totalMeters
            let metersPerSecond = max(1, train.speedKmh / 3.6)
            let duration = !motionEnabled || distance < 1
                ? 0
                : min(6.2, max(1.2, distance / metersPerSecond))

            states[train.id] = State(
                geometry: geometry,
                startFraction: startFraction,
                targetFraction: targetFraction,
                startedAt: date,
                duration: duration
            )
        }
    }

    func positions(at date: Date) -> [String: MapCoordinate] {
        states.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.coordinate(at: date)
        }
    }

    func hasActiveMotion(at date: Date) -> Bool {
        states.values.contains { $0.isAnimating(at: date) }
    }

    func freeze(at date: Date) {
        states = states.reduce(into: [:]) { result, entry in
            guard let coordinate = entry.value.coordinate(at: date) else {
                return
            }
            let fraction = entry.value.geometry.fraction(closestTo: coordinate)
            result[entry.key] = State(
                geometry: entry.value.geometry,
                startFraction: fraction,
                targetFraction: fraction,
                startedAt: date,
                duration: 0
            )
        }
    }

    private func geometry(
        for train: TrainLocation,
        line: RailwayMapLine?
    ) -> PolylineGeometry {
        if let coordinates = train.routeSegment?.coordinates, coordinates.count >= 2 {
            return PolylineGeometry(coordinates: coordinates)
        }

        let candidateGeometries = line?.coordinates
            .map(PolylineGeometry.init(coordinates:))
            .filter { !$0.coordinates.isEmpty } ?? []
        return candidateGeometries.min { lhs, rhs in
            let lhsClamped = lhs.clampedCoordinate(for: train.coordinate) ?? train.coordinate
            let rhsClamped = rhs.clampedCoordinate(for: train.coordinate) ?? train.coordinate
            return PolylineGeometry(coordinates: [lhsClamped, train.coordinate]).totalMeters
                < PolylineGeometry(coordinates: [rhsClamped, train.coordinate]).totalMeters
        } ?? PolylineGeometry(coordinates: [train.coordinate])
    }

    private func shouldAdvanceEstimatedPosition(for train: TrainLocation) -> Bool {
        guard let segment = train.routeSegment else {
            return false
        }
        return train.dataAccuracy == .estimated
            && train.status == .running
            && train.speedKmh > 0
            && segment.fromFraction != segment.toFraction
    }

    private func targetFraction(
        observed: Double,
        train: TrainLocation,
        advancesWithinEstimate: Bool
    ) -> Double {
        guard advancesWithinEstimate, let segment = train.routeSegment else {
            return PolylineGeometry.clampUnit(observed)
        }

        let start = PolylineGeometry.clampUnit(segment.fromFraction)
        let end = PolylineGeometry.clampUnit(segment.toFraction)
        return PolylineGeometry.interpolate(
            fromFraction: start,
            toFraction: end,
            progress: 0.88
        )
    }

    private func segmentConstrainedFraction(
        _ fraction: Double,
        segment: RouteSegmentEstimate?
    ) -> Double {
        guard let segment else {
            return PolylineGeometry.clampUnit(fraction)
        }
        let lower = min(segment.fromFraction, segment.toFraction)
        let upper = max(segment.fromFraction, segment.toFraction)
        return min(
            PolylineGeometry.clampUnit(upper),
            max(PolylineGeometry.clampUnit(lower), fraction)
        )
    }
}
