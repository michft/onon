@preconcurrency import CoreLocation
import Foundation

@MainActor
final class LocationRecorder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var lastError: String?

    var onAcceptedLocation: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    private(set) var isCapturing = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startCapture() {
        isCapturing = true
        requestPermission()
        if [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) {
            manager.startUpdatingLocation()
        } else if [.denied, .restricted].contains(manager.authorizationStatus) {
            isCapturing = false
            lastError = "Location access is blocked. Enable Always access in Settings."
        }
    }

    func stopCapture() {
        isCapturing = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        if isCapturing, [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) {
            manager.startUpdatingLocation()
        } else if [.denied, .restricted].contains(manager.authorizationStatus) {
            isCapturing = false
            lastError = "Location access is blocked. Enable Always access in Settings."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where isUsable(location) {
            lastLocation = location
            onAcceptedLocation?(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown { return }
        lastError = error.localizedDescription
    }

    private func isUsable(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0 &&
            location.horizontalAccuracy <= 50 &&
            abs(location.timestamp.timeIntervalSinceNow) < 120
    }
}
