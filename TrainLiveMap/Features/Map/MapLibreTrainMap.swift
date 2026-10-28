import CoreLocation
import MapLibre
import SwiftUI
import UIKit

enum MapLocationEvent: Equatable, Sendable {
    case requesting
    case centered
    case cancelled
    case failed(String)
}

struct MapLibreTrainMap: UIViewRepresentable {
    let trains: [TrainLocation]
    let railwayLines: [RailwayMapLine]
    let selectedTrainID: String?
    let isActive: Bool
    let reduceMotion: Bool
    let locationRequestID: Int
    let onSelectTrain: (String) -> Void
    let onLocationEvent: (MapLocationEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectTrain: onSelectTrain,
            onLocationEvent: onLocationEvent,
            initialLocationRequestID: locationRequestID
        )
    }

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = URL(string: "https://tiles.openfreemap.org/styles/positron")!
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.backgroundColor = UIColor(hex: "#E8EAED")
        mapView.delegate = context.coordinator
        // Current location is used only for one-shot camera movement after a tap.
        // Keeping this off avoids continuous tracking and location persistence.
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
        context.coordinator.onLocationEvent = onLocationEvent
        context.coordinator.update(
            mapView: mapView,
            trains: trains,
            railwayLines: railwayLines,
            selectedTrainID: selectedTrainID,
            isActive: isActive,
            reduceMotion: reduceMotion,
            locationRequestID: locationRequestID
        )
    }

    static func dismantleUIView(
        _ uiView: MLNMapView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
        uiView.delegate = nil
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, CLLocationManagerDelegate {
        var onSelectTrain: (String) -> Void
        var onLocationEvent: (MapLocationEvent) -> Void

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
        private var lastLocationRequestID: Int
        private var locationRequestInFlight = false
        private var oneShotLocationRequested = false
        private var locationManager: CLLocationManager?
        private var usingFallbackStyle = false
        private var locationTimeoutTask: Task<Void, Never>?

        init(
            onSelectTrain: @escaping (String) -> Void,
            onLocationEvent: @escaping (MapLocationEvent) -> Void,
            initialLocationRequestID: Int
        ) {
            self.onSelectTrain = onSelectTrain
            self.onLocationEvent = onLocationEvent
            lastLocationRequestID = initialLocationRequestID
            super.init()
        }

        func attach(to mapView: MLNMapView) {
            self.mapView = mapView
            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(tick)
            )
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 20)
            displayLink.add(to: .main, forMode: .common)
            displayLink.isPaused = true
            self.displayLink = displayLink
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
            locationTimeoutTask?.cancel()
            locationTimeoutTask = nil
            locationManager?.stopUpdatingLocation()
            locationManager?.delegate = nil
            locationManager = nil
            locationRequestInFlight = false
            oneShotLocationRequested = false
            mapView = nil
        }

        func update(
            mapView: MLNMapView,
            trains: [TrainLocation],
            railwayLines: [RailwayMapLine],
            selectedTrainID: String?,
            isActive: Bool,
            reduceMotion: Bool,
            locationRequestID: Int
        ) {
            if self.isActive != isActive {
                self.isActive = isActive
                if !isActive {
                    motionEngine.freeze(at: .now)
                    displayLink?.isPaused = true
                    cancelLocationRequestForBackground()
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
            if selectionChanged {
                focusOnSelectedTrain(on: mapView)
            }
            displayLink?.isPaused = !isActive
                || reduceMotion
                || !motionEngine.hasActiveMotion(at: .now)

            if locationRequestID != lastLocationRequestID {
                lastLocationRequestID = locationRequestID
                requestCurrentLocation()
            }
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
            focusOnSelectedTrain(on: mapView)
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            guard !usingFallbackStyle else { return }
            usingFallbackStyle = true
            mapView.styleURL = Bundle.main.url(forResource: "MapStyle", withExtension: "json")
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
            let peers = displayedTrains.filter {
                abs($0.latitude - train.latitude) < 0.0002 && abs($0.longitude - train.longitude) < 0.0002
            }.sorted { $0.id < $1.id }
            let index = peers.firstIndex(where: { $0.id == train.id }) ?? 0
            annotationView.centerOffset = CGVector(
                dx: peers.count > 1 ? (CGFloat(index % 5) - CGFloat(min(peers.count, 5) - 1) / 2) * 46 : 0,
                dy: -36 - CGFloat(index / 5) * 50
            )
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

            renderStations(on: style)
            if viewportNeedsUpdate {
                fitViewportToDisplayedRailways(on: mapView)
            }
        }

        private func renderStations(on style: MLNStyle) {
            var seen = Set<String>()
            let stations = displayedRailways.flatMap { $0.stations ?? [] }
                .filter { $0.position.isFinite && seen.insert($0.id).inserted }
            let features: [MLNPointFeature] = stations.enumerated().map { index, station in
                let imageID = "station-image-\(index)"
                style.setImage(Self.stationImage(name: station.name), forName: imageID)
                routeImageIdentifiers.append(imageID)
                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: station.position.latitude, longitude: station.position.longitude)
                feature.attributes = ["image": imageID]
                return feature
            }
            guard !features.isEmpty else { return }
            let source = MLNShapeSource(identifier: "selected-stations", features: features, options: nil)
            style.addSource(source)
            let layer = MLNSymbolStyleLayer(identifier: "selected-station-labels", source: source)
            layer.iconImageName = NSExpression(forKeyPath: "image")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: false)
            layer.minimumZoomLevel = 10
            style.addLayer(layer)
            routeSourceIdentifiers.append(source.identifier)
            routeLayerIdentifiers.append(layer.identifier)
        }

        private static func stationImage(name: String) -> UIImage {
            let font = UIFont.systemFont(ofSize: 12, weight: .bold)
            let size = (name as NSString).size(withAttributes: [.font: font])
            return UIGraphicsImageRenderer(size: CGSize(width: max(44, size.width + 10), height: 47)).image { _ in
                let width = max(44, size.width + 10)
                UIColor(hex: "#FFF8E9").setFill()
                UIColor(hex: "#493020").setStroke()
                let house = UIBezierPath(roundedRect: CGRect(x: width / 2 - 12, y: 9, width: 24, height: 18), cornerRadius: 3)
                house.lineWidth = 2; house.fill(); house.stroke()
                let roof = UIBezierPath(); roof.move(to: CGPoint(x: width / 2 - 16, y: 10)); roof.addLine(to: CGPoint(x: width / 2, y: 1)); roof.addLine(to: CGPoint(x: width / 2 + 16, y: 10)); roof.close(); roof.fill(); roof.stroke()
                UIColor(hex: "#83B8C0").setFill()
                UIBezierPath(roundedRect: CGRect(x: width / 2 - 8, y: 14, width: 16, height: 8), cornerRadius: 2).fill()
                UIColor.white.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 29, width: width, height: 18), cornerRadius: 4).fill()
                (name as NSString).draw(at: CGPoint(x: (width - size.width) / 2, y: 30), withAttributes: [.font: font, .foregroundColor: UIColor(hex: "#493020")])
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

            // Several through services span well beyond the metropolitan area.
            // Fitting every vertex makes the initial map unreadable; start in
            // central Tokyo and let the user pan to the rest of the routes.
            if maximumLatitude - minimumLatitude > 1.5 || maximumLongitude - minimumLongitude > 2 {
                mapView.setCenter(
                    CLLocationCoordinate2D(latitude: 35.69, longitude: 139.75),
                    zoomLevel: 12,
                    animated: hasSetViewport && !reduceMotion
                )
                hasSetViewport = true
                viewportNeedsUpdate = false
                return
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

        private func requestCurrentLocation() {
            guard isActive else {
                emitLocationEvent(.cancelled)
                return
            }
            guard !locationRequestInFlight else {
                return
            }
            guard CLLocationManager.locationServicesEnabled() else {
                emitLocationEvent(
                    .failed(
                        "位置情報サービスがオフです。設定で位置情報サービスを有効にしてください。"
                    )
                )
                return
            }

            locationRequestInFlight = true
            oneShotLocationRequested = false
            emitLocationEvent(.requesting)

            let manager = locationManager ?? makeLocationManager()
            locationManager = manager
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                requestOneLocation(using: manager)
            case .denied:
                finishLocationRequest(
                    with: .failed(
                        "位置情報の利用が許可されていません。設定からこのアプリの位置情報を許可してください。"
                    )
                )
            case .restricted:
                finishLocationRequest(
                    with: .failed(
                        "この端末では位置情報の利用が制限されています。"
                    )
                )
            @unknown default:
                finishLocationRequest(
                    with: .failed("現在地を利用できません。")
                )
            }
        }

        private func makeLocationManager() -> CLLocationManager {
            let manager = CLLocationManager()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.activityType = .other
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            return manager
        }

        private func requestOneLocation(using manager: CLLocationManager) {
            guard locationRequestInFlight, !oneShotLocationRequested else {
                return
            }
            oneShotLocationRequested = true
            locationTimeoutTask?.cancel()
            locationTimeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
                guard let self, self.locationRequestInFlight else {
                    return
                }
                self.finishLocationRequest(
                    with: .failed(
                        "現在地を取得できませんでした。電波状況を確認して、もう一度お試しください。"
                    )
                )
            }
            manager.requestLocation()
        }

        func locationManagerDidChangeAuthorization(
            _ manager: CLLocationManager
        ) {
            guard locationRequestInFlight else {
                return
            }
            guard isActive else {
                cancelLocationRequestForBackground()
                return
            }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                requestOneLocation(using: manager)
            case .denied:
                finishLocationRequest(
                    with: .failed(
                        "位置情報の利用が許可されていません。設定からこのアプリの位置情報を許可してください。"
                    )
                )
            case .restricted:
                finishLocationRequest(
                    with: .failed(
                        "この端末では位置情報の利用が制限されています。"
                    )
                )
            case .notDetermined:
                break
            @unknown default:
                finishLocationRequest(
                    with: .failed("現在地を利用できません。")
                )
            }
        }

        func locationManager(
            _ manager: CLLocationManager,
            didUpdateLocations locations: [CLLocation]
        ) {
            guard locationRequestInFlight else {
                return
            }
            guard isActive else {
                cancelLocationRequestForBackground()
                return
            }
            let newestAcceptableLocation = locations.reversed().first {
                location in
                let coordinate = location.coordinate
                return location.horizontalAccuracy >= 0
                    && abs(location.timestamp.timeIntervalSinceNow) <= 120
                    && coordinate.latitude.isFinite
                    && coordinate.longitude.isFinite
                    && (-90...90).contains(coordinate.latitude)
                    && (-180...180).contains(coordinate.longitude)
            }
            guard let location = newestAcceptableLocation,
                  let mapView else {
                finishLocationRequest(
                    with: .failed(
                        "現在地を取得できませんでした。電波状況を確認して、もう一度お試しください。"
                    )
                )
                return
            }

            mapView.setCenter(
                location.coordinate,
                zoomLevel: max(mapView.zoomLevel, 14),
                animated: hasSetViewport && !reduceMotion
            )
            hasSetViewport = true
            finishLocationRequest(with: .centered)
        }

        func locationManager(
            _ manager: CLLocationManager,
            didFailWithError error: Error
        ) {
            guard locationRequestInFlight else {
                return
            }
            guard isActive else {
                cancelLocationRequestForBackground()
                return
            }
            if let locationError = error as? CLError,
               locationError.code == .denied {
                finishLocationRequest(
                    with: .failed(
                        "位置情報の利用が許可されていません。設定からこのアプリの位置情報を許可してください。"
                    )
                )
            } else {
                finishLocationRequest(
                    with: .failed(
                        "現在地を取得できませんでした。電波状況を確認して、もう一度お試しください。"
                    )
                )
            }
        }

        private func finishLocationRequest(with event: MapLocationEvent) {
            locationTimeoutTask?.cancel()
            locationTimeoutTask = nil
            locationRequestInFlight = false
            oneShotLocationRequested = false
            emitLocationEvent(event)
        }

        private func cancelLocationRequestForBackground() {
            guard locationRequestInFlight else {
                return
            }
            locationTimeoutTask?.cancel()
            locationTimeoutTask = nil
            locationManager?.stopUpdatingLocation()
            locationRequestInFlight = false
            oneShotLocationRequested = false
            emitLocationEvent(.cancelled)
        }

        private func emitLocationEvent(_ event: MapLocationEvent) {
            DispatchQueue.main.async { [weak self] in
                self?.onLocationEvent(event)
            }
        }

        private func focusOnSelectedTrain(on mapView: MLNMapView) {
            guard let selectedTrainID,
                  trainsByID[selectedTrainID] != nil,
                  let position = motionEngine.positions(at: .now)[selectedTrainID]
            else {
                return
            }
            let coordinate = CLLocationCoordinate2D(
                latitude: position.latitude,
                longitude: position.longitude
            )
            mapView.setCenter(
                coordinate,
                zoomLevel: max(mapView.zoomLevel, 13),
                animated: hasSetViewport && !reduceMotion
            )
            hasSetViewport = true
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
