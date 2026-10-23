import MapLibre
import SwiftUI
import UIKit

struct MapCanvas: UIViewRepresentable {
    let styleURL: URL?
    let recording: RecordingSnapshot?
    @Binding var visibleBounds: OfflineBounds?
    var initialZoomLevel: Double = 11
    var recenterRequest = 0

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.logoView.isHidden = false
        map.attributionButton.isHidden = false
        map.maximumZoomLevel = 19
        map.setCenter(CLLocationCoordinate2D(latitude: -33.8685, longitude: 151.2024), zoomLevel: initialZoomLevel, animated: false)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        if map.styleURL != styleURL, let styleURL { map.styleURL = styleURL }
        if context.coordinator.lastRecenterRequest != recenterRequest {
            context.coordinator.lastRecenterRequest = recenterRequest
            map.userTrackingMode = .follow
        }
        context.coordinator.render(recording, on: map)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapCanvas
        var lastRecenterRequest = 0

        private var renderedRecordingID: UUID?
        private var track: MLNPolyline?
        private var renderedSampleCount = 0
        private var renderedWaypointIDs: Set<UUID> = []

        init(parent: MapCanvas) { self.parent = parent }

        /// Extends the drawn track and waypoints in place; rebuilding them per GPS fix grows with recording length.
        func render(_ recording: RecordingSnapshot?, on map: MLNMapView) {
            if recording?.summary.id != renderedRecordingID || (recording?.samples.count ?? 0) < renderedSampleCount {
                let prior = map.annotations ?? []
                if !prior.isEmpty { map.removeAnnotations(prior) }
                renderedRecordingID = recording?.summary.id
                track = nil
                renderedSampleCount = 0
                renderedWaypointIDs = []
            }
            guard let recording else { return }

            let samples = recording.samples
            if samples.count > renderedSampleCount {
                if let track {
                    var added = samples[renderedSampleCount...].map(\.coordinate)
                    track.appendCoordinates(&added, count: UInt(added.count))
                    renderedSampleCount = samples.count
                } else if samples.count > 1 {
                    var coordinates = samples.map(\.coordinate)
                    let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                    map.addAnnotation(line)
                    track = line
                    renderedSampleCount = samples.count
                }
            }

            let newWaypoints = recording.waypoints.filter { !renderedWaypointIDs.contains($0.id) }
            guard !newWaypoints.isEmpty else { return }
            map.addAnnotations(newWaypoints.map { waypoint in
                let marker = WaypointAnnotation()
                marker.coordinate = CLLocationCoordinate2D(latitude: waypoint.latitude, longitude: waypoint.longitude)
                return marker
            })
            renderedWaypointIDs.formUnion(newWaypoints.map(\.id))
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            let value = mapView.visibleCoordinateBounds
            parent.visibleBounds = OfflineBounds(
                west: value.sw.longitude, south: value.sw.latitude,
                east: value.ne.longitude, north: value.ne.latitude
            )
        }

        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            guard annotation is WaypointAnnotation else { return nil }
            let identifier = "waypoint-circle-dot"
            if let reused = mapView.dequeueReusableAnnotationImage(withIdentifier: identifier) { return reused }
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28))
            let image = renderer.image { context in
                UIColor.white.withAlphaComponent(0.85).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: 24, height: 24))
                UIColor.black.setStroke()
                context.cgContext.setLineWidth(3)
                context.cgContext.strokeEllipse(in: CGRect(x: 2, y: 2, width: 24, height: 24))
                UIColor.black.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 10, y: 10, width: 8, height: 8))
            }
            return MLNAnnotationImage(image: image, reuseIdentifier: identifier)
        }

        func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat { 1 }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            UIColor.systemOrange
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat { 5 }
    }
}

private final class WaypointAnnotation: MLNPointAnnotation {}
