import XCTest
@testable import Onon

final class PairingServiceTests: XCTestCase {
    func testDecodesContractPairingURL() throws {
        let value = try PairingService().decode(
            payload: "onon://pair?server=http%3A%2F%2Fonon.local%3A3000&code=123456"
        )
        XCTAssertEqual(value.serverURL.absoluteString, "http://onon.local:3000")
        XCTAssertEqual(value.pairingCode, "123456")
    }

    func testRejectsNonOnonQRCode() {
        XCTAssertThrowsError(try PairingService().decode(payload: "https://example.com/pair?code=123456"))
    }
}
