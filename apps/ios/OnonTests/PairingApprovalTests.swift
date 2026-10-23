import XCTest
@testable import Onon

@MainActor
final class PairingApprovalTests: XCTestCase {
    func testReceivingCancellingAndInvalidLinksNeverExchangeCredentials() async {
        var exchanges = 0
        let model = AppModel(pairingExchange: { _ in exchanges += 1; throw PairingError.invalidCode })
        model.receivePairing(payload: "onon://pair?server=https%3A%2F%2Fexample.com&code=test")
        XCTAssertNil(model.pendingPairing)
        await model.confirmPairing()
        model.receivePairing(payload: "onon://pair?server=http%3A%2F%2Fonon.local%3A3000&code=test")
        XCTAssertEqual(model.pendingPairing?.serverURL.absoluteString, "http://onon.local:3000")
        model.cancelPairing()
        await model.confirmPairing()
        XCTAssertEqual(exchanges, 0)
    }

    func testExplicitApprovalExchangesOnlyDisplayedCandidateOnce() async {
        var exchanged: [PairingQRCode] = []
        let model = AppModel(pairingExchange: { value in exchanged.append(value); throw PairingError.invalidCode })
        model.receivePairing(payload: "onon://pair?server=http%3A%2F%2Fonon.local%3A3000&code=original")
        let displayed = model.pendingPairing
        model.receivePairing(payload: "onon://pair?server=http%3A%2F%2Fother.local%3A3000&code=replacement")
        XCTAssertEqual(model.pendingPairing, displayed)
        XCTAssertTrue(exchanged.isEmpty)
        await model.confirmPairing()
        await model.confirmPairing()
        XCTAssertEqual(exchanged, displayed.map { [$0] } ?? [])
        XCTAssertNil(model.pendingPairing)
        XCTAssertFalse(model.isPairing)
    }

    func testStoredServerWithoutMatchingApprovalCannotUpload() async throws {
        let previousURL = ServerConfiguration.serverURL
        let previousApproval = UserDefaults.standard.string(forKey: "approved-pairing-origin")
        defer {
            ServerConfiguration.serverURL = previousURL
            UserDefaults.standard.set(previousApproval, forKey: "approved-pairing-origin")
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try RecordingDatabase(fileURL: folder.appending(path: "test.sqlite"))
        let id = try await database.startRecording()
        try await database.setState(recordingID: id, from: .active, to: .finished)
        let approved = URL(string: "http://onon.local:3000")!
        ServerConfiguration.approve(approved)
        XCTAssertNotNil(ServerConfiguration.endpoint("api/v1/recordings"))
        ServerConfiguration.serverURL = URL(string: "http://other.local:3000")!
        XCTAssertNil(ServerConfiguration.endpoint("api/v1/recordings"))
        await SyncService(database: database).syncPending()
        let snapshot = try await database.recording(id: id)
        XCTAssertEqual(snapshot?.summary.syncState, .local)
        ServerConfiguration.serverURL = URL(string: "https://example.com")!
        XCTAssertNil(ServerConfiguration.endpoint("api/v1/recordings"))
        ServerConfiguration.serverURL = nil
        ServerConfiguration.serverURL = approved
        XCTAssertNil(ServerConfiguration.endpoint("api/v1/recordings"))
    }
}
