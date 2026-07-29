import MapLibre
import SwiftUI
import UIKit

struct MapLibreTrainMap: UIViewRepresentable {
    let trains: [TrainLocation]
    let railwayLines: [RailwayMapLine]
    let isActive: Bool
    let onSelectTrain: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectTrain: onSelectTrain)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = Bundle.main.url(
            forResource: "MapStyle",
            withExtension: "json"
        )
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.maximumZoomLevel = 18
        mapView.minimumZoomLevel = 5
        mapView.logoViewPosition = .topLeft
        mapView.logoViewMargins = CGPoint(x: 10, y: 76)
        mapView.attributionButtonPosition = .topRight
        mapView.attributionButtonMargins = CGPoint(x: 10, y: 76)
        context.coordinator.attach(to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onSelectTrain = onSelectTrain
        context.coordinator.update(
            mapView: mapView,
            trains: trains,
            railwayLines: railwayLines,
            isActive: isActive
        )
    }

    static func dismantleUIView(_ uiView: MLNMapView, coordinator: Coordinator) {
        coordinator.detach()
        uiView.delegate = nil
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onSelectTrain: (String) -> Void

        private weak var mapView: MLNMapView?
        private var trainAnnotations: [String: TrainPointAnnotation] = [:]
        private var trainsByID: [String: TrainLocation] = [:]
        private var railwayAnnotations: [MLNPolyline] = []
        private var railwayColors: [ObjectIdentifier: UIColor] = [:]
        private var displayedRailways: [RailwayMapLine] = []
        private var displayedTrains: [TrainLocation] = []
        private let motionEngine = TrainMotionEngine()
        private var displayLink: CADisplayLink?
        private var isActive = true
        private var hasSetInitialViewport = false

        init(onSelectTrain: @escaping (String) -> Void) {
            self.onSelectTrain = onSelectTrain
            super.init()
        }

        func attach(to mapView: MLNMapView) {
            self.mapView = mapView
            let displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink.add(to: .main, forMode: .common)
            displayLink.isPaused = true
            self.displayLink = displayLink
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
            mapView = nil
        }

        func update(
            mapView: MLNMapView,
            trains: [TrainLocation],
            railwayLines: [RailwayMapLine],
            isActive: Bool
        ) {
            if self.isActive != isActive {
                self.isActive = isActive
                if !isActive {
                    motionEngine.freeze(at: .now)
                    displayLink?.isPaused = true
                }
            }

            if displayedRailways != railwayLines {
                displayedRailways = railwayLines
                renderRailways(on: mapView)
            }

            if displayedTrains != trains {
                displayedTrains = trains
                trainsByID = Dictionary(uniqueKeysWithValues: trains.map { ($0.id, $0) })
                motionEngine.ingest(
                    trains: trains,
                    railwayLines: railwayLines,
                    at: .now
                )
                reconcileTrainAnnotations(on: mapView)
            }

            updateAnnotationCoordinates(at: .now)
            displayLink?.isPaused = !isActive || !motionEngine.hasActiveMotion(at: .now)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            renderRailways(on: mapView)
            reconcileTrainAnnotations(on: mapView)
            guard !hasSetInitialViewport else {
                return
            }
            hasSetInitialViewport = true
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: 34.75, longitude: 138.45),
                ne: CLLocationCoordinate2D(latitude: 36.95, longitude: 141.0)
            )
            mapView.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: 72, left: 36, bottom: 110, right: 36),
                animated: false,
                completionHandler: nil
            )
        }

        func mapView(
            _ mapView: MLNMapView,
            viewFor annotation: MLNAnnotation
        ) -> MLNAnnotationView? {
            guard let trainAnnotation = annotation as? TrainPointAnnotation,
                  let train = trainsByID[trainAnnotation.trainID] else {
                return nil
            }

            let reuseIdentifier = "train-marker"
            let annotationView: TrainMarkerAnnotationView
            if let reused = mapView.dequeueReusableAnnotationView(
                withIdentifier: reuseIdentifier
            ) as? TrainMarkerAnnotationView {
                annotationView = reused
            } else {
                annotationView = TrainMarkerAnnotationView(
                    reuseIdentifier: reuseIdentifier
                )
            }
            annotationView.annotation = annotation
            annotationView.configure(with: train)
            return annotationView
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let trainAnnotation = annotation as? TrainPointAnnotation else {
                return
            }
            onSelectTrain(trainAnnotation.trainID)
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(
            _ mapView: MLNMapView,
            strokeColorForShapeAnnotation annotation: MLNShape
        ) -> UIColor {
            railwayColors[ObjectIdentifier(annotation)] ?? .systemOrange
        }

        func mapView(
            _ mapView: MLNMapView,
            alphaForShapeAnnotation annotation: MLNShape
        ) -> CGFloat {
            0.92
        }

        func mapView(
            _ mapView: MLNMapView,
            lineWidthForPolylineAnnotation annotation: MLNPolyline
        ) -> CGFloat {
            4
        }

        private func renderRailways(on mapView: MLNMapView) {
            if !railwayAnnotations.isEmpty {
                mapView.removeAnnotations(railwayAnnotations)
            }
            railwayAnnotations.removeAll(keepingCapacity: true)
            railwayColors.removeAll(keepingCapacity: true)

            for line in displayedRailways {
                for part in line.coordinates where part.count >= 2 {
                    let coordinates = part.map {
                        CLLocationCoordinate2D(
                            latitude: $0.latitude,
                            longitude: $0.longitude
                        )
                    }
                    let polyline = MLNPolyline(
                        coordinates: coordinates,
                        count: UInt(coordinates.count)
                    )
                    railwayAnnotations.append(polyline)
                    railwayColors[ObjectIdentifier(polyline)] = UIColor(
                        hex: line.color
                    )
                }
            }

            if !railwayAnnotations.isEmpty {
                mapView.addAnnotations(railwayAnnotations)
            }
        }

        private func reconcileTrainAnnotations(on mapView: MLNMapView) {
            let incomingIDs = Set(trainsByID.keys)
            let removedIDs = Set(trainAnnotations.keys).subtracting(incomingIDs)
            let removedAnnotations = removedIDs.compactMap {
                trainAnnotations.removeValue(forKey: $0)
            }
            if !removedAnnotations.isEmpty {
                mapView.removeAnnotations(removedAnnotations)
            }

            let currentPositions = motionEngine.positions(at: .now)
            var addedAnnotations: [TrainPointAnnotation] = []
            for train in displayedTrains {
                let annotation: TrainPointAnnotation
                if let existing = trainAnnotations[train.id] {
                    annotation = existing
                } else {
                    annotation = TrainPointAnnotation(trainID: train.id)
                    trainAnnotations[train.id] = annotation
                    addedAnnotations.append(annotation)
                }

                let position = currentPositions[train.id] ?? train.coordinate
                annotation.coordinate = CLLocationCoordinate2D(
                    latitude: position.latitude,
                    longitude: position.longitude
                )
                if let annotationView = mapView.view(
                    for: annotation
                ) as? TrainMarkerAnnotationView {
                    annotationView.configure(with: train)
                }
            }

            if !addedAnnotations.isEmpty {
                mapView.addAnnotations(addedAnnotations)
            }
        }

        @objc
        private func tick() {
            guard isActive else {
                displayLink?.isPaused = true
                return
            }
            let now = Date()
            updateAnnotationCoordinates(at: now)
            if !motionEngine.hasActiveMotion(at: now) {
                displayLink?.isPaused = true
            }
        }

        private func updateAnnotationCoordinates(at date: Date) {
            let positions = motionEngine.positions(at: date)
            for (trainID, coordinate) in positions {
                trainAnnotations[trainID]?.coordinate = CLLocationCoordinate2D(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }
    }
}

private final class TrainPointAnnotation: MLNPointAnnotation {
    let trainID: String

    init(trainID: String) {
        self.trainID = trainID
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TrainMarkerAnnotationView: MLNAnnotationView {
    private let hostingController = UIHostingController(
        rootView: TrainIconView(train: .placeholder)
    )

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 72, height: 76)
        centerOffset = CGVector(dx: 0, dy: -30)
        isEnabled = true
        clipsToBounds = false
        backgroundColor = .clear

        let hostedView = hostingController.view!
        hostedView.frame = bounds
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostedView.backgroundColor = .clear
        hostedView.isUserInteractionEnabled = false
        addSubview(hostedView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with train: TrainLocation) {
        hostingController.rootView = TrainIconView(train: train)
        isAccessibilityElement = true
        accessibilityLabel = TrainPresentation.accessibilityLabel(for: train)
        accessibilityTraits = .button
        accessibilityHint = "ダブルタップで列車の詳細を表示します"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessibilityLabel = nil
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        if sanitized.count == 6 {
            self.init(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        } else {
            self.init(
                red: 0.965,
                green: 0.545,
                blue: 0.118,
                alpha: 1
            )
        }
    }
}

private extension TrainLocation {
    static let placeholder = TrainLocation(
        id: "placeholder",
        lineId: "placeholder",
        lineName: "路線",
        lineColor: "#f68b1e",
        trainNumber: nil,
        direction: .inbound,
        destination: "行き先",
        trainType: .local,
        latitude: 35.681,
        longitude: 139.767,
        delayMinutes: 0,
        speedKmh: 0,
        status: .running,
        lastUpdatedAt: .distantPast,
        stoppedSince: nil,
        dataAccuracy: .estimated,
        routeSegment: nil
    )
}
