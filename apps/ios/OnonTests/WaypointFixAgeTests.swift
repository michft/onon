import XCTest
@testable import Onon

final class WaypointFixAgeTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: WaypointFixAge.key)
        super.tearDown()
    }

    func testDefaultsToTwoMinutesAndClampsStoredValuesToRange() {
        UserDefaults.standard.removeObject(forKey: WaypointFixAge.key)
        XCTAssertEqual(WaypointFixAge.current, 120)
        UserDefaults.standard.set(5, forKey: WaypointFixAge.key)
        XCTAssertEqual(WaypointFixAge.current, 15)
        UserDefaults.standard.set(900, forKey: WaypointFixAge.key)
        XCTAssertEqual(WaypointFixAge.current, 300)
        UserDefaults.standard.set(60, forKey: WaypointFixAge.key)
        XCTAssertEqual(WaypointFixAge.current, 60)
    }

    func testLabels() {
        XCTAssertEqual(WaypointFixAge.options.map(WaypointFixAge.label), ["15 seconds", "30 seconds", "1 minute", "2 minutes", "5 minutes"])
    }
}
