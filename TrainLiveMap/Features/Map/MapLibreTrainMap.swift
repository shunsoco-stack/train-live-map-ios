import MapLibre
import SwiftUI
import UIKit

struct MapLibreTrainMap: UIViewRepresentable {
    let trains: [TrainLocation]
    let railwayLines: [RailwayMapLine]
    let selectedTrainID: String?
    let isActive: Bool
    let reduceMotion: Bool
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
        mapView.logoViewMargins = CGPoint(x: 10, y: 72)
        mapView.attributionButtonPosition = .topRight
        mapView.attributionButtonMargins = CGPoint(x: 10, y: 72)
        context.coordinator.attach(to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onSelectTrain = onSelectTrain
        context.coordinator.update(
            mapView: mapView,
            trains: trains,
            railwayLines: railwayLines,
            selectedTrainID: selectedTrainID,
            isActive: isActive,
            reduceMotion: reduceMotion
        )
    }

    static func dismantleUIView(
        _ uiView: MLNMapView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
        uiView.delegate = nil
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onSelectTrain: (String) -> Void

        private weak var mapView: MLNMapView?
        private var trainAnnotations: [String: TrainPointAnnotation] = [:]
        private var trainsByID: [String: TrainLocation] = [:]
        private var routeLayerIdentifiers: [String] = []
        private var routeSourceIdentifiers: [String] = []
        private var routeImageIdentifiers: [String] = []
        private var displayedRailways: [RailwayMapLine] = []
        private var displayedTrains: [TrainLocation] = []
        private var selectedTrainID: String?
        private let motionEngine = TrainMotionEngine()
        private var displayLink: CADisplayLink?
        private var isActive = true
        private var reduceMotion = false
        private var hasSetViewport = false
        private var viewportNeedsUpdate = true

        init(onSelectTrain: @escaping (String) -> Void) {
            self.onSelectTrain = onSelectTrain
            super.init()
        }

        func attach(to mapView: MLNMapView) {
            self.mapView = mapView
            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(tick)
            )
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
            selectedTrainID: String?,
            isActive: Bool,
            reduceMotion: Bool
        ) {
            if self.isActive != isActive {
                self.isActive = isActive
                if !isActive {
                    motionEngine.freeze(at: .now)
                    displayLink?.isPaused = true
                }
            }

            let railwaysChanged = displayedRailways != railwayLines
            let trainsChanged = displayedTrains != trains
            let motionPreferenceChanged = self.reduceMotion != reduceMotion
            let selectionChanged = self.selectedTrainID != selectedTrainID
            self.reduceMotion = reduceMotion
            self.selectedTrainID = selectedTrainID

            if railwaysChanged {
                displayedRailways = railwayLines
                viewportNeedsUpdate = true
                renderRailways(on: mapView)
            }

            if trainsChanged || railwaysChanged || motionPreferenceChanged {
                displayedTrains = trains
                trainsByID = Dictionary(
                    uniqueKeysWithValues: trains.map { ($0.id, $0) }
                )
                motionEngine.ingest(
                    trains: trains,
                    railwayLines: railwayLines,
                    at: .now,
                    motionEnabled: !reduceMotion && isActive
                )
                reconcileTrainAnnotations(on: mapView)
            } else if selectionChanged {
                updateTrainMarkerSelection(on: mapView)
            }

            updateAnnotationCoordinates(at: .now)
            displayLink?.isPaused = !isActive
                || reduceMotion
                || !motionEngine.hasActiveMotion(at: .now)
        }

        func mapView(
            _ mapView: MLNMapView,
            didFinishLoading style: MLNStyle
        ) {
            routeLayerIdentifiers.removeAll()
            routeSourceIdentifiers.removeAll()
            routeImageIdentifiers.removeAll()
            renderRailways(on: mapView)
            reconcileTrainAnnotations(on: mapView)

            if displayedRailways.isEmpty {
                setDefaultViewport(on: mapView)
            } else {
                fitViewportToDisplayedRailways(on: mapView)
            }
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
            annotationView.configure(
                with: train,
                isSelected: train.id == selectedTrainID
            )
            return annotationView
        }

        func mapView(
            _ mapView: MLNMapView,
            didSelect annotation: MLNAnnotation
        ) {
            guard let trainAnnotation = annotation as? TrainPointAnnotation else {
                return
            }
            selectedTrainID = trainAnnotation.trainID
            updateTrainMarkerSelection(on: mapView)
            onSelectTrain(trainAnnotation.trainID)
            mapView.deselectAnnotation(annotation, animated: false)
        }

        private func renderRailways(on mapView: MLNMapView) {
            guard let style = mapView.style else {
                return
            }
            removeRouteLayers(from: style)

            for (index, line) in displayedRailways.enumerated() {
                let suffix = "\(index)-\(safeIdentifier(line.id))"
                let sourceIdentifier = "selected-railway-source-\(suffix)"
                let casingIdentifier = "selected-railway-casing-\(suffix)"
                let lineIdentifier = "selected-railway-line-\(suffix)"
                let labelIdentifier = "selected-railway-label-\(suffix)"
                let imageIdentifier = "selected-railway-image-\(suffix)"

                let features: [MLNPolylineFeature] = line.coordinates.compactMap {
                    part in
                    guard part.count >= 2 else {
                        return nil
                    }
                    var coordinates = part.map {
                        CLLocationCoordinate2D(
                            latitude: $0.latitude,
                            longitude: $0.longitude
                        )
                    }
                    return MLNPolylineFeature(
                        coordinates: &coordinates,
                        count: UInt(coordinates.count)
                    )
                }
                guard !features.isEmpty else {
                    continue
                }

                let source = MLNShapeSource(
                    identifier: sourceIdentifier,
                    features: features,
                    options: nil
                )
                style.addSource(source)

                let casingLayer = MLNLineStyleLayer(
                    identifier: casingIdentifier,
                    source: source
                )
                casingLayer.lineColor = NSExpression(
                    forConstantValue: UIColor(hex: "#24170d")
                )
                casingLayer.lineWidth = NSExpression(forConstantValue: 7)
                casingLayer.lineCap = NSExpression(forConstantValue: "round")
                casingLayer.lineJoin = NSExpression(forConstantValue: "round")
                style.addLayer(casingLayer)

                let colorLayer = MLNLineStyleLayer(
                    identifier: lineIdentifier,
                    source: source
                )
                colorLayer.lineColor = NSExpression(
                    forConstantValue: UIColor(hex: line.color)
                )
                colorLayer.lineWidth = NSExpression(forConstantValue: 4)
                colorLayer.lineCap = NSExpression(forConstantValue: "round")
                colorLayer.lineJoin = NSExpression(forConstantValue: "round")
                style.addLayer(colorLayer)

                let labelImage = Self.routeLabelImage(
                    text: Self.shortRouteName(line.name),
                    lineColor: UIColor(hex: line.color)
                )
                style.setImage(labelImage, forName: imageIdentifier)

                let labelLayer = MLNSymbolStyleLayer(
                    identifier: labelIdentifier,
                    source: source
                )
                labelLayer.iconImageName = NSExpression(
                    forConstantValue: imageIdentifier
                )
                labelLayer.symbolPlacement = NSExpression(
                    forConstantValue: "line"
                )
                labelLayer.symbolSpacing = NSExpression(
                    forConstantValue: 280
                )
                labelLayer.iconRotationAlignment = NSExpression(
                    forConstantValue: "map"
                )
                labelLayer.keepsIconUpright = NSExpression(
                    forConstantValue: true
                )
                labelLayer.iconAllowsOverlap = NSExpression(
                    forConstantValue: false
                )
                labelLayer.iconIgnoresPlacement = NSExpression(
                    forConstantValue: false
                )
                labelLayer.minimumZoomLevel = 7
                style.addLayer(labelLayer)

                routeSourceIdentifiers.append(sourceIdentifier)
                routeLayerIdentifiers.append(contentsOf: [
                    casingIdentifier,
                    lineIdentifier,
                    labelIdentifier
                ])
                routeImageIdentifiers.append(imageIdentifier)
            }

            if viewportNeedsUpdate {
                fitViewportToDisplayedRailways(on: mapView)
            }
        }

        private func removeRouteLayers(from style: MLNStyle) {
            for identifier in routeLayerIdentifiers.reversed() {
                if let layer = style.layer(withIdentifier: identifier) {
                    style.removeLayer(layer)
                }
            }
            for identifier in routeSourceIdentifiers.reversed() {
                if let source = style.source(withIdentifier: identifier) {
                    style.removeSource(source)
                }
            }
            for identifier in routeImageIdentifiers {
                style.removeImage(forName: identifier)
            }
            routeLayerIdentifiers.removeAll()
            routeSourceIdentifiers.removeAll()
            routeImageIdentifiers.removeAll()
        }

        private func fitViewportToDisplayedRailways(on mapView: MLNMapView) {
            let coordinates = displayedRailways.flatMap {
                $0.coordinates.flatMap { $0 }
            }
            guard let first = coordinates.first else {
                viewportNeedsUpdate = false
                if !hasSetViewport {
                    setDefaultViewport(on: mapView)
                }
                return
            }

            var minimumLatitude = first.latitude
            var maximumLatitude = first.latitude
            var minimumLongitude = first.longitude
            var maximumLongitude = first.longitude
            for coordinate in coordinates.dropFirst() {
                minimumLatitude = min(minimumLatitude, coordinate.latitude)
                maximumLatitude = max(maximumLatitude, coordinate.latitude)
                minimumLongitude = min(minimumLongitude, coordinate.longitude)
                maximumLongitude = max(maximumLongitude, coordinate.longitude)
            }

            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(
                    latitude: minimumLatitude,
                    longitude: minimumLongitude
                ),
                ne: CLLocationCoordinate2D(
                    latitude: maximumLatitude,
                    longitude: maximumLongitude
                )
            )
            mapView.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(
                    top: 125,
                    left: 38,
                    bottom: 145,
                    right: 72
                ),
                animated: hasSetViewport && !reduceMotion,
                completionHandler: nil
            )
            hasSetViewport = true
            viewportNeedsUpdate = false
        }

        private func setDefaultViewport(on mapView: MLNMapView) {
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(
                    latitude: 34.75,
                    longitude: 138.45
                ),
                ne: CLLocationCoordinate2D(
                    latitude: 36.95,
                    longitude: 141.0
                )
            )
            mapView.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(
                    top: 72,
                    left: 36,
                    bottom: 110,
                    right: 36
                ),
                animated: false,
                completionHandler: nil
            )
            hasSetViewport = true
            viewportNeedsUpdate = false
        }

        private func reconcileTrainAnnotations(on mapView: MLNMapView) {
            let incomingIDs = Set(trainsByID.keys)
            let removedIDs = Set(trainAnnotations.keys)
                .subtracting(incomingIDs)
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
                    annotationView.configure(
                        with: train,
                        isSelected: train.id == selectedTrainID
                    )
                }
            }

            if !addedAnnotations.isEmpty {
                mapView.addAnnotations(addedAnnotations)
            }
        }

        private func updateTrainMarkerSelection(on mapView: MLNMapView) {
            for (trainID, annotation) in trainAnnotations {
                guard let train = trainsByID[trainID],
                      let view = mapView.view(
                        for: annotation
                      ) as? TrainMarkerAnnotationView else {
                    continue
                }
                view.configure(
                    with: train,
                    isSelected: trainID == selectedTrainID
                )
            }
        }

        @objc
        private func tick() {
            guard isActive, !reduceMotion else {
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

        private func safeIdentifier(_ value: String) -> String {
            value.unicodeScalars.map {
                CharacterSet.alphanumerics.contains($0) ? String($0) : "-"
            }
            .joined()
        }

        private static func shortRouteName(_ name: String) -> String {
            let candidates = ["（", "("]
            let index = candidates.compactMap {
                name.range(of: $0)?.lowerBound
            }
            .min()
            guard let index else {
                return name
            }
            return String(name[..<index])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func routeLabelImage(
            text: String,
            lineColor: UIColor
        ) -> UIImage {
            let font = RailFont.uiExtraBold(size: 12)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let size = CGSize(
                width: ceil(textSize.width) + 18,
                height: 25
            )
            let format = UIGraphicsImageRendererFormat()
            format.opaque = false
            format.scale = UIScreen.main.scale
            return UIGraphicsImageRenderer(
                size: size,
                format: format
            ).image { _ in
                let rect = CGRect(origin: .zero, size: size).insetBy(
                    dx: 1.5,
                    dy: 1.5
                )
                let path = UIBezierPath(
                    roundedRect: rect,
                    cornerRadius: 7
                )
                UIColor(hex: "#24170d").setFill()
                path.fill()
                lineColor.setStroke()
                path.lineWidth = 2.5
                path.stroke()

                let textRect = CGRect(
                    x: 9,
                    y: (size.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                (text as NSString).draw(
                    in: textRect,
                    withAttributes: attributes
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
        frame = CGRect(x: 0, y: 0, width: 88, height: 96)
        centerOffset = CGVector(dx: 0, dy: -36)
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

    func configure(with train: TrainLocation, isSelected: Bool) {
        hostingController.rootView = TrainIconView(
            train: train,
            isSelected: isSelected
        )
        isAccessibilityElement = true
        accessibilityLabel = TrainPresentation.accessibilityLabel(for: train)
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        accessibilityHint = "ダブルタップで列車の詳細を表示します"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessibilityLabel = nil
        accessibilityTraits = .button
    }
}

extension UIColor {
    convenience init(hex: String) {
        let sanitized = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
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
        latitude: 35.68,
        longitude: 139.76,
        delayMinutes: 0,
        speedKmh: 0,
        status: .stopped,
        lastUpdatedAt: .distantPast,
        stoppedSince: nil,
        dataAccuracy: .estimated,
        routeSegment: nil
    )
}
