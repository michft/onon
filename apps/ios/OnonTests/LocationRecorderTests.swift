import CoreLocation
import XCTest
@testable import Onon

@MainActor
final class LocationRecorderTests: XCTestCase {
    func testCountsAcceptedAndRejectedFixesAndForwardsOnlyAccepted() {
        let recorder = LocationRecorder()
        var forwarded: [CLLocation] = []
        recorder.onAcceptedLocation = { forwarded.append($0) }

        let good = fix(accuracy: 5, age: 1)
        recorder.locationManager(CLLocationManager(), didUpdateLocations: [
            good,
            fix(accuracy: 80, age: 1),
            fix(accuracy: -1, age: 1),
            fix(accuracy: 5, age: 300),
        ])

        XCTAssertEqual(forwarded, [good])
        XCTAssertEqual(recorder.lastLocation, good)
        XCTAssertEqual(recorder.stats.delivered, 4)
        XCTAssertEqual(recorder.stats.accepted, 1)
        XCTAssertEqual(recorder.stats.rejectedInaccurate, 2)
        XCTAssertEqual(recorder.stats.rejectedStale, 1)
        XCTAssertNotNil(recorder.stats.lastDeliveredAt)
    }

    private func fix(accuracy: CLLocationAccuracy, age: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1,
            timestamp: Date().addingTimeInterval(-age)
        )
    }
}
