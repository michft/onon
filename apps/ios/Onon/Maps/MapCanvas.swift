import MapLibre
import SwiftUI
import UIKit

struct MapCanvas: UIViewRepresentable {
    let styleURL: URL?
    let recording: RecordingSnapshot?
    @Binding var visibleBounds: OfflineBounds?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.logoView.isHidden = false
        map.attributionButton.isHidden = false
        map.setCenter(CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093), zoomLevel: 11, animated: false)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        if map.styleURL != styleURL, let styleURL { map.styleURL = styleURL }
        let prior = map.annotations ?? []
        if !prior.isEmpty { map.removeAnnotations(prior) }
        guard let recording else { return }
        if recording.samples.count > 1 {
            var coordinates = recording.samples.map(\.coordinate)
            let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
            map.addAnnotation(line)
        }
        for waypoint in recording.waypoints {
            let marker = WaypointAnnotation()
            marker.coordinate = CLLocationCoordinate2D(latitude: waypoint.latitude, longitude: waypoint.longitude)
            map.addAnnotation(marker)
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapCanvas

        init(parent: MapCanvas) { self.parent = parent }

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
