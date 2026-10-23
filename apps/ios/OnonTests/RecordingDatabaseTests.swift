import CoreLocation
import SQLite3
import XCTest
@testable import Onon

final class RecordingDatabaseTests: XCTestCase {
    func testReadErrorsAreNotReportedAsEndOfRows() throws {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(":memory:", &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_create_function_v2(connection, "fail_read", 0, SQLITE_UTF8, nil, { context, _, _ in
            sqlite3_result_error_code(context, SQLITE_IOERR)
        }, nil, nil, nil), SQLITE_OK)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(connection, "SELECT fail_read()", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        XCTAssertThrowsError(try RecordingDatabase.readRow(statement)) { error in
            guard case RecordingError.storage = error else { return XCTFail("Read error was misclassified: \(error)") }
        }
    }

    func testUnfinishedRecordingRecoversWithCommittedSamplesAndWaypoint() async throws {
        let database = try temporaryDatabase()
        let id = try await database.startRecording(at: Date(timeIntervalSince1970: 100))
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),
            altitude: 12,
            horizontalAccuracy: 4,
            verticalAccuracy: 6,
            course: 90,
            speed: 1.2,
            timestamp: Date(timeIntervalSince1970: 101)
        )
        try await database.appendSample(recordingID: id, locationSample: RawSample(sequence: 0, location: location))
        try await database.appendWaypoint(recordingID: id, waypoint: WaypointObservation(location: location))

        let recovered = try await database.unfinishedRecording()
        let snapshot = try await database.recording(id: id)

        XCTAssertEqual(recovered?.id, id)
        XCTAssertEqual(recovered?.state, .active)
        XCTAssertEqual(snapshot?.samples.count, 1)
        XCTAssertEqual(snapshot?.waypoints.count, 1)
    }

    func testAllowedRecordingStateTransitions() async throws {
        let database = try temporaryDatabase()
        let id = try await database.startRecording()
        try await database.setState(recordingID: id, from: .active, to: .paused)
        try await database.setState(recordingID: id, from: .paused, to: .active)
        try await database.setState(recordingID: id, from: .active, to: .finished)

        let value = try await database.recording(id: id)
        let snapshot = try XCTUnwrap(value)
        XCTAssertEqual(snapshot.summary.state, .finished)
        XCTAssertNotNil(snapshot.summary.finishedAt)

        do {
            try await database.setState(recordingID: id, from: .finished, to: .active)
            XCTFail("Finished raw recording became mutable")
        } catch {
            XCTAssertEqual(error as? RecordingError, .invalidTransition)
        }
    }

    func testPausedRecordingRejectsNewRawObservations() async throws {
        let database = try temporaryDatabase()
        let id = try await database.startRecording()
        try await database.setState(recordingID: id, from: .active, to: .paused)
        let location = CLLocation(latitude: -33.8688, longitude: 151.2093)

        do {
            try await database.appendSample(recordingID: id, locationSample: RawSample(sequence: 0, location: location))
            XCTFail("Expected a paused recording to reject samples")
        } catch {
            XCTAssertEqual(error as? RecordingError, .noActiveSession)
        }
        await XCTAssertThrowsErrorAsync {
            try await database.appendWaypoint(
                recordingID: id,
                waypoint: WaypointObservation(location: location)
            )
        }

        let value = try await database.recording(id: id)
        let snapshot = try XCTUnwrap(value)
        XCTAssertTrue(snapshot.samples.isEmpty)
        XCTAssertTrue(snapshot.waypoints.isEmpty)
    }

    func testFinishedRecordingCreatesStableOrderedUpload() async throws {
        let database = try temporaryDatabase()
        let id = try await database.startRecording(at: Date(timeIntervalSince1970: 10))
        for sequence in 0..<2 {
            let location = CLLocation(latitude: -33.86 + Double(sequence) / 100, longitude: 151.20 + Double(sequence) / 100)
            // Caller sequence is deliberately duplicated; storage owns ordering.
            try await database.appendSample(recordingID: id, locationSample: RawSample(sequence: 0, location: location))
        }
        try await database.setState(recordingID: id, from: .active, to: .finished, at: Date(timeIntervalSince1970: 20))
        let value = try await database.recording(id: id)
        let upload = try RecordingUpload(snapshot: XCTUnwrap(value))
        let first = try APIJSON.encoder.encode(upload)
        let second = try APIJSON.encoder.encode(upload)
        let pendingIDs = try await database.pendingRecordingIDs()

        XCTAssertEqual(first, second)
        XCTAssertEqual(upload.samples.map(\.sequence), [0, 1])
        XCTAssertEqual(pendingIDs, [id])
    }

    func testAppendedSamplesMatchStoredRecordingWithoutReload() async throws {
        let database = try temporaryDatabase()
        let id = try await database.startRecording()
        let started = try await database.recording(id: id)
        var snapshot = try XCTUnwrap(started)
        for offset in 0..<3 {
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: -33.8688 + Double(offset) * 0.0001, longitude: 151.2093),
                altitude: 12, horizontalAccuracy: 4, verticalAccuracy: 6, course: 90, speed: 1.2,
                timestamp: Date(timeIntervalSince1970: 100 + Double(offset))
            )
            // A stale caller-supplied sequence must not leak into the stored or returned sample.
            let sample = try await database.appendSample(recordingID: id, locationSample: RawSample(sequence: 99, location: location))
            XCTAssertEqual(sample.id, offset)
            snapshot = snapshot.appending(sample)
        }

        let stored = try await database.recording(id: id)
        XCTAssertEqual(snapshot, stored)
    }

    private func temporaryDatabase() throws -> RecordingDatabase {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try RecordingDatabase(fileURL: directory.appending(path: "test.sqlite"))
    }

    private func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {}
    }
}
