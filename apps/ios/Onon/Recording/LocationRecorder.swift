@preconcurrency import CoreLocation
import Foundation
import UIKit

/// How Onon has treated the fixes iOS delivered during the current capture.
struct CaptureStats: Equatable, Sendable {
    var delivered = 0
    var accepted = 0
    var rejectedInaccurate = 0
    var rejectedStale = 0
    var lastDeliveredAt: Date?
    var lastAccuracy: Double?
    var longestGap: TimeInterval = 0
}

@MainActor
final class LocationRecorder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let maximumAccuracy: CLLocationAccuracy = 50
    static let maximumAge: TimeInterval = 120
    /// Delivery pauses longer than this are logged: either the phone stayed within the distance filter or iOS suspended updates.
    private static let reportedGap: TimeInterval = 30
    private static let summaryInterval = 100

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var lastError: String? {
        didSet { if let lastError { Log.location.error("\(lastError, privacy: .public)") } }
    }
    @Published private(set) var stats = CaptureStats()

    var onAcceptedLocation: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    private(set) var isCapturing = false

    private enum Rejection: String {
        case inaccurate
        case stale
    }

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
        stats = CaptureStats()
        lastError = nil
        requestPermission()
        if [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) {
            manager.startUpdatingLocation()
            Log.location.notice("Capture started (authorization \(self.authorizationDescription, privacy: .public))")
        } else if [.denied, .restricted].contains(manager.authorizationStatus) {
            // Capture stays requested so re-enabling access in Settings resumes it.
            lastError = "Location access is blocked. Enable Always access in Settings."
        } else {
            Log.location.notice("Capture waiting for location permission")
        }
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        manager.stopUpdatingLocation()
        Log.location.notice("Capture stopped; \(self.statsSummary, privacy: .public)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        Log.location.notice("Authorization changed to \(self.authorizationDescription, privacy: .public)")
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        if isCapturing, [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) {
            lastError = nil
            manager.startUpdatingLocation()
        } else if isCapturing, [.denied, .restricted].contains(manager.authorizationStatus) {
            lastError = "Location access is blocked. Enable Always access in Settings."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var next = stats
        let now = Date()
        if let previous = next.lastDeliveredAt {
            let gap = now.timeIntervalSince(previous)
            next.longestGap = max(next.longestGap, gap)
            if gap > Self.reportedGap {
                Log.location.notice("No fixes delivered for \(Int(gap))s: stationary or suspended (app state \(self.applicationStateDescription, privacy: .public))")
            }
        }
        next.lastDeliveredAt = now
        for location in locations {
            next.delivered += 1
            next.lastAccuracy = location.horizontalAccuracy
            if let rejection = rejection(for: location) {
                switch rejection {
                case .inaccurate: next.rejectedInaccurate += 1
                case .stale: next.rejectedStale += 1
                }
                Log.location.debug(
                    "Rejected \(rejection.rawValue, privacy: .public) fix: ±\(location.horizontalAccuracy, format: .fixed(precision: 0))m, age \(-location.timestamp.timeIntervalSinceNow, format: .fixed(precision: 1))s"
                )
                continue
            }
            next.accepted += 1
            lastLocation = location
            onAcceptedLocation?(location)
        }
        stats = next
        if next.delivered / Self.summaryInterval != (next.delivered - locations.count) / Self.summaryInterval {
            Log.location.notice("Capture progress; \(self.statsSummary, privacy: .public)")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown {
            Log.location.debug("Location temporarily unknown")
            return
        }
        lastError = error.localizedDescription
    }

    private func rejection(for location: CLLocation) -> Rejection? {
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > Self.maximumAccuracy { return .inaccurate }
        if abs(location.timestamp.timeIntervalSinceNow) >= Self.maximumAge { return .stale }
        return nil
    }

    private var statsSummary: String {
        "delivered \(stats.delivered), accepted \(stats.accepted), inaccurate \(stats.rejectedInaccurate), stale \(stats.rejectedStale), longest gap \(Int(stats.longestGap))s"
    }

    private var authorizationDescription: String {
        switch authorizationStatus {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "whenInUse"
        @unknown default: "unknown(\(authorizationStatus.rawValue))"
        }
    }

    private var applicationStateDescription: String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}
