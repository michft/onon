import XCTest
@testable import Onon

final class PairingServiceTests: XCTestCase {
    func testOnlyLocalServerOriginsAreAccepted() throws {
        for server in ["http://onon.local:3000", "https://ONON.local/", "http://192.168.1.2:3000", "http://10.0.0.2", "http://172.16.1.2", "http://localhost:3000", "http://[fd00::1]:3000"] {
            XCTAssertNoThrow(try PairingService().decode(payload: payload(server)))
        }
        for server in ["https://example.com", "http://8.8.8.8", "http://onon.local.evil.com", "http://user:password@onon.local", "http://onon.local/path", "http://onon.local?token=x", "http://onon.local#fragment", "http://192.168.001.2", "http://2130706433", "http://onon.local:0", "http://[2001:4860::1]"] {
            XCTAssertThrowsError(try PairingService().decode(payload: payload(server)), server)
        }
        XCTAssertThrowsError(try PairingService().decode(payload: payload("http://onon.local") + "&code=second"))
        XCTAssertThrowsError(try PairingService().decode(payload: payload("http://onon.local") + "&server=http%3A%2F%2Fevil.local"))
    }

    func testRedirectPolicyNeverForwardsCredentials() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let local = URL(string: "http://onon.local:3000")!
        let task = session.dataTask(with: local)
        let response = HTTPURLResponse(url: local, statusCode: 307, httpVersion: nil, headerFields: nil)!
        let redirect = URLRequest(url: URL(string: "https://example.com/collect")!)
        var called = false
        RejectServerRedirects().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirect) { request in
            called = true
            XCTAssertNil(request)
        }
        XCTAssertTrue(called)
        task.cancel()
    }

    private func payload(_ server: String) -> String {
        var parts = URLComponents(string: "onon://pair")!
        parts.queryItems = [URLQueryItem(name: "server", value: server), URLQueryItem(name: "code", value: "test-code")]
        return parts.string!
    }

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
