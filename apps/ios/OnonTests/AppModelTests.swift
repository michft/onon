import CoreLocation
import SQLite3
import XCTest
@testable import Onon

@MainActor
final class AppModelTests: XCTestCase {
    func testPauseAndFinishRacesDoNotReportStorageFailure() async throws {
        for state in [RecordingState.paused, .finished] {
            let (model, database, _, id) = try await fixture()
            defer { model.locationRecorder.stopCapture() }
            try await database.setState(recordingID: id, from: .active, to: state)

            await model.commit(fix())

            XCTAssertNil(model.alertMessage)
            XCTAssertNil(model.captureFailure)
            let snapshot = try await database.recording(id: id)
            XCTAssertEqual(snapshot?.summary.state, state)
            XCTAssertTrue(snapshot?.samples.isEmpty == true)
        }
    }

    func testSaveFailurePausesAndResumeCanCommitAgain() async throws {
        let (model, database, file, id) = try await fixture()
        defer { model.locationRecorder.stopCapture() }
        try execute("CREATE TRIGGER fail_test_sample BEFORE INSERT ON samples BEGIN SELECT RAISE(ABORT, 'test write failure'); END", at: file)

        await model.commit(fix())

        XCTAssertFalse(model.locationRecorder.isCapturing)
        XCTAssertNotNil(model.captureFailure)
        XCTAssertEqual(model.currentRecording?.summary.state, .paused)
        let paused = try await database.recording(id: id)
        XCTAssertEqual(paused?.summary.state, .paused)
        try execute("DROP TRIGGER fail_test_sample", at: file)
        await model.resume()
        await model.commit(fix())

        XCTAssertNil(model.captureFailure)
        XCTAssertTrue(model.locationRecorder.isCapturing)
        XCTAssertEqual(model.currentRecording?.summary.sampleCount, 1)
        XCTAssertEqual(model.recordings.first?.sampleCount, 1)
    }

    func testFailedPauseWriteExposesStoppedCaptureAndCanRetry() async throws {
        let (model, database, file, id) = try await fixture()
        defer { model.locationRecorder.stopCapture() }
        try execute("""
            CREATE TRIGGER fail_test_sample BEFORE INSERT ON samples BEGIN SELECT RAISE(ABORT, 'test write failure'); END;
            CREATE TRIGGER fail_test_pause BEFORE UPDATE OF state ON recordings WHEN NEW.state='paused'
            BEGIN SELECT RAISE(ABORT, 'test pause failure'); END;
            """, at: file)

        await model.commit(fix())

        XCTAssertFalse(model.locationRecorder.isCapturing)
        XCTAssertNotNil(model.captureFailure)
        let stopped = try await database.recording(id: id)
        XCTAssertEqual(stopped?.summary.state, .active)
        XCTAssertEqual(stopped?.summary.sampleCount, 0)
        try execute("DROP TRIGGER fail_test_sample; DROP TRIGGER fail_test_pause", at: file)
        await model.resume()
        await model.commit(fix())

        XCTAssertNil(model.captureFailure)
        XCTAssertTrue(model.locationRecorder.isCapturing)
        XCTAssertEqual(model.currentRecording?.summary.state, .active)
        XCTAssertEqual(model.currentRecording?.summary.sampleCount, 1)
    }

    func testResumeRetriesWhenTransitionSucceedsButReadFails() async throws {
        var failActiveRead = false
        let (model, database, _, id) = try await fixture { database, id in
            let snapshot = try await database.recording(id: id)
            if failActiveRead && snapshot?.summary.state == .active {
                failActiveRead = false
                throw RecordingError.storage("test read failure")
            }
            return snapshot
        }
        defer { model.locationRecorder.stopCapture() }
        await model.pause()
        failActiveRead = true

        await model.resume()

        let persisted = try await database.recording(id: id)
        XCTAssertEqual(persisted?.summary.state, .active)
        XCTAssertEqual(model.currentRecording?.summary.state, .paused)
        XCTAssertFalse(model.locationRecorder.isCapturing)
        XCTAssertNotNil(model.captureFailure)
        await model.resume()
        await model.commit(fix())

        XCTAssertNil(model.captureFailure)
        XCTAssertTrue(model.locationRecorder.isCapturing)
        XCTAssertEqual(model.currentRecording?.summary.state, .active)
        XCTAssertEqual(model.currentRecording?.summary.sampleCount, 1)
    }

    func testResumeReconcilesPauseWhenRecoveryReadFails() async throws {
        var failNextRead = false
        let (model, database, file, id) = try await fixture { database, id in
            if failNextRead {
                failNextRead = false
                throw RecordingError.storage("test read failure")
            }
            return try await database.recording(id: id)
        }
        defer { model.locationRecorder.stopCapture() }
        try execute("CREATE TRIGGER fail_test_sample BEFORE INSERT ON samples BEGIN SELECT RAISE(ABORT, 'test write failure'); END", at: file)
        failNextRead = true

        await model.commit(fix())

        let persisted = try await database.recording(id: id)
        XCTAssertEqual(persisted?.summary.state, .paused)
        XCTAssertEqual(model.currentRecording?.summary.state, .active)
        XCTAssertFalse(model.locationRecorder.isCapturing)
        XCTAssertNotNil(model.captureFailure)
        try execute("DROP TRIGGER fail_test_sample", at: file)
        await model.resume()
        await model.commit(fix())

        XCTAssertNil(model.captureFailure)
        XCTAssertTrue(model.locationRecorder.isCapturing)
        XCTAssertEqual(model.currentRecording?.summary.state, .active)
        XCTAssertEqual(model.currentRecording?.summary.sampleCount, 1)
    }

    func testPauseReadFailureExposesStoppedCaptureAndResumeWorks() async throws {
        var failNextRead = false
        let (model, database, _, id) = try await fixture { database, id in
            if failNextRead {
                failNextRead = false
                throw RecordingError.storage("test pause read failure")
            }
            return try await database.recording(id: id)
        }
        defer { model.locationRecorder.stopCapture() }
        failNextRead = true

        await model.pause()

        let persisted = try await database.recording(id: id)
        XCTAssertEqual(persisted?.summary.state, .paused)
        XCTAssertEqual(model.currentRecording?.summary.state, .active)
        XCTAssertFalse(model.locationRecorder.isCapturing)
        XCTAssertNotNil(model.captureFailure)
        await model.resume()
        await model.commit(fix())

        XCTAssertNil(model.captureFailure)
        XCTAssertTrue(model.locationRecorder.isCapturing)
        XCTAssertEqual(model.currentRecording?.summary.sampleCount, 1)
    }

    func testFinishReadFailureStaysStoppedAndRetryPreservesRawData() async throws {
        var failNextRead = false
        let (model, database, _, id) = try await fixture(readSummaries: { database in
            if failNextRead {
                failNextRead = false
                throw RecordingError.storage("test finish read failure")
            }
            return try await database.recordings()
        })
        defer { model.locationRecorder.stopCapture() }
        await model.commit(fix())
        failNextRead = true

        await model.finish()

        let persisted = try await database.recording(id: id)
        XCTAssertEqual(persisted?.summary.state, .finished)
        XCTAssertEqual(persisted?.summary.sampleCount, 1)
        XCTAssertFalse(model.locationRecorder.isCapturing)
        XCTAssertNotNil(model.captureFailure)
        XCTAssertTrue(model.finishNeedsRetry)
        // A concurrent Saved/sync refresh can observe the committed Finish.
        try await model.reload()
        XCTAssertNil(model.currentRecording)
        XCTAssertEqual(model.finishingRecordingID, id)
        await model.resume()
        XCTAssertFalse(model.locationRecorder.isCapturing)
        await model.finish()

        XCTAssertNil(model.captureFailure)
        XCTAssertFalse(model.finishNeedsRetry)
        XCTAssertNil(model.currentRecording)
        XCTAssertFalse(model.locationRecorder.isCapturing)
        XCTAssertEqual(model.recordings.first?.state, .finished)
        XCTAssertEqual(model.recordings.first?.sampleCount, 1)
    }

    func testFinishWriteFailureStaysStoppedUntilRetry() async throws {
        let (model, database, file, id) = try await fixture()
        defer { model.locationRecorder.stopCapture() }
        try execute("CREATE TRIGGER fail_test_finish BEFORE UPDATE OF state ON recordings WHEN NEW.state='finished' BEGIN SELECT RAISE(ABORT, 'test finish write failure'); END", at: file)

        await model.finish()

        let persisted = try await database.recording(id: id)
        XCTAssertEqual(persisted?.summary.state, .active)
        XCTAssertFalse(model.locationRecorder.isCapturing)
        XCTAssertNotNil(model.captureFailure)
        XCTAssertTrue(model.finishNeedsRetry)
        await model.resume()
        XCTAssertFalse(model.locationRecorder.isCapturing)
        try execute("DROP TRIGGER fail_test_finish", at: file)
        await model.finish()

        XCTAssertNil(model.captureFailure)
        XCTAssertFalse(model.finishNeedsRetry)
        XCTAssertNil(model.currentRecording)
        XCTAssertEqual(model.recordings.first?.state, .finished)
    }

    func testLaterPauseOrFinishInvalidatesSuspendedResume() async throws {
        enum Interruption: CaseIterable { case pause, finish, failedFinish }
        for interruption in Interruption.allCases {
            var suspendNextRead = false
            var releaseReload: CheckedContinuation<Void, Never>?
            let suspended = expectation(description: "Resume reload suspended")
            let (model, database, file, id) = try await fixture(readSummaries: { database in
                let summaries = try await database.recordings()
                if suspendNextRead {
                    suspendNextRead = false
                    suspended.fulfill()
                    await withCheckedContinuation { releaseReload = $0 }
                }
                return summaries
            })
            defer { model.locationRecorder.stopCapture() }
            await model.pause()
            suspendNextRead = true
            let resume = Task { await model.resume() }
            await fulfillment(of: [suspended], timeout: 5)
            guard let release = releaseReload else {
                XCTFail("Resume did not suspend in reload")
                return
            }

            if interruption == .failedFinish {
                try execute("CREATE TRIGGER fail_test_finish BEFORE UPDATE OF state ON recordings WHEN NEW.state='finished' BEGIN SELECT RAISE(ABORT, 'test finish write failure'); END", at: file)
            }
            if interruption == .pause {
                await model.pause()
            } else {
                await model.finish()
            }
            let failure = model.captureFailure
            release.resume()
            releaseReload = nil
            await resume.value

            XCTAssertFalse(model.locationRecorder.isCapturing)
            XCTAssertEqual(model.captureFailure, failure)
            switch interruption {
            case .pause:
                XCTAssertNil(model.captureFailure)
                XCTAssertEqual(model.currentRecording?.summary.state, .paused)
            case .finish:
                XCTAssertNil(model.captureFailure)
                XCTAssertNil(model.currentRecording)
            case .failedFinish:
                XCTAssertNotNil(model.captureFailure)
                XCTAssertTrue(model.finishNeedsRetry)
                await model.commit(fix())
                let persisted = try await database.recording(id: id)
                XCTAssertEqual(persisted?.summary.sampleCount, 0)
                try execute("DROP TRIGGER fail_test_finish", at: file)
                await model.finish()
                XCTAssertNil(model.currentRecording)
            }
        }
    }

    private func fixture(readSummaries: @escaping @MainActor (RecordingDatabase) async throws -> [RecordingSummary] = { try await $0.recordings() }, readRecording: @escaping @MainActor (RecordingDatabase, UUID) async throws -> RecordingSnapshot? = { try await $0.recording(id: $1) }) async throws -> (AppModel, RecordingDatabase, URL, UUID) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "test.sqlite")
        let database = try RecordingDatabase(fileURL: file)
        let id = try await database.startRecording()
        let model = AppModel(database: database, readSummaries: readSummaries, readRecording: readRecording)
        await model.prepare()
        XCTAssertTrue(model.isReady)
        return (model, database, file, id)
    }

    private func fix() -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),
                   altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: Date())
    }

    private func execute(_ sql: String, at file: URL) throws {
        var connection: OpaquePointer?
        guard sqlite3_open(file.path, &connection) == SQLITE_OK else { throw RecordingError.storage("Test database open failed") }
        defer { sqlite3_close(connection) }
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw RecordingError.storage(String(cString: sqlite3_errmsg(connection)))
        }
    }
}
