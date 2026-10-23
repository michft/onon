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
        let (model, database, _, id) = try await fixture(readRecording: { database, id in
            let snapshot = try await database.recording(id: id)
            if failActiveRead && snapshot?.summary.state == .active {
                failActiveRead = false
                throw RecordingError.storage("test read failure")
            }
            return snapshot
        })
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
        let (model, database, file, id) = try await fixture(readRecording: { database, id in
            if failNextRead {
                failNextRead = false
                throw RecordingError.storage("test read failure")
            }
            return try await database.recording(id: id)
        })
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
        let (model, database, _, id) = try await fixture(readRecording: { database, id in
            if failNextRead {
                failNextRead = false
                throw RecordingError.storage("test pause read failure")
            }
            return try await database.recording(id: id)
        })
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
            func drainResume() async {
                suspendNextRead = false
                releaseReload?.resume()
                releaseReload = nil
                await resume.value
            }
            do {
                await fulfillment(of: [suspended], timeout: 5)
                guard releaseReload != nil else {
                    throw RecordingError.storage("Resume did not suspend in reload")
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
                await drainResume()

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
            } catch {
                await drainResume()
                throw error
            }
        }
    }

    func testBackgroundReloadCannotRestorePausedStateAfterResume() async throws {
        var holdResume = false
        var holdBackground = false
        var releaseResume: CheckedContinuation<Void, Never>?
        var releaseBackground: CheckedContinuation<Void, Never>?
        let resumeRead = expectation(description: "Resume read paused state")
        let backgroundRead = expectation(description: "Background read paused snapshot")
        let (model, _, _, _) = try await fixture(readRecording: { database, id in
            let snapshot = try await database.recording(id: id)
            if holdResume {
                holdResume = false
                resumeRead.fulfill()
                await withCheckedContinuation { releaseResume = $0 }
            } else if holdBackground {
                holdBackground = false
                backgroundRead.fulfill()
                await withCheckedContinuation { releaseBackground = $0 }
            }
            return snapshot
        })
        defer { model.locationRecorder.stopCapture() }
        await model.pause()
        holdResume = true
        let resume = Task { await model.resume() }
        var background: Task<Void, Error>?
        func drainTasks() async {
            holdResume = false
            holdBackground = false
            releaseResume?.resume()
            releaseResume = nil
            releaseBackground?.resume()
            releaseBackground = nil
            await resume.value
            _ = try? await background?.value
        }
        do {
            await fulfillment(of: [resumeRead], timeout: 5)
            guard releaseResume != nil else { throw RecordingError.storage("Resume read did not suspend") }
            holdBackground = true
            background = Task { try await model.reload() }
            await fulfillment(of: [backgroundRead], timeout: 5)
            guard releaseBackground != nil else { throw RecordingError.storage("Background read did not suspend") }
            releaseResume?.resume()
            releaseResume = nil
            await resume.value
            XCTAssertTrue(model.locationRecorder.isCapturing)
            XCTAssertEqual(model.currentRecording?.summary.state, .active)
            releaseBackground?.resume()
            releaseBackground = nil
            try await background?.value

            XCTAssertTrue(model.locationRecorder.isCapturing)
            XCTAssertEqual(model.currentRecording?.summary.state, .active)
            await model.commit(fix())
            XCTAssertEqual(model.currentRecording?.summary.sampleCount, 1)
        } catch {
            await drainTasks()
            throw error
        }
        await drainTasks()
    }

    func testSupersededSampleRecoveryPreservesFinishRetryAlert() async throws {
        var holdRecovery = false
        var releaseRecovery: CheckedContinuation<Void, Never>?
        let recoveryRead = expectation(description: "Sample recovery reload suspended")
        let (model, database, file, id) = try await fixture(readSummaries: { database in
            let summaries = try await database.recordings()
            if holdRecovery {
                holdRecovery = false
                recoveryRead.fulfill()
                await withCheckedContinuation { releaseRecovery = $0 }
            }
            return summaries
        })
        defer { model.locationRecorder.stopCapture() }
        try execute("""
            CREATE TRIGGER fail_test_sample BEFORE INSERT ON samples BEGIN SELECT RAISE(ABORT, 'test sample write failure'); END;
            CREATE TRIGGER fail_test_finish BEFORE UPDATE OF state ON recordings WHEN NEW.state='finished'
            BEGIN SELECT RAISE(ABORT, 'test finish write failure'); END;
            """, at: file)
        holdRecovery = true
        let recovery = Task { await model.commit(fix()) }
        func drainRecovery() async {
            holdRecovery = false
            releaseRecovery?.resume()
            releaseRecovery = nil
            await recovery.value
        }
        do {
            await fulfillment(of: [recoveryRead], timeout: 5)
            guard releaseRecovery != nil else { throw RecordingError.storage("Recovery read did not suspend") }
            await model.finish()
            let finishAlert = model.alertMessage
            XCTAssertTrue(finishAlert?.contains("Tap Retry finish") == true)
            await drainRecovery()

            XCTAssertEqual(model.alertMessage, finishAlert)
            XCTAssertTrue(model.finishNeedsRetry)
            XCTAssertFalse(model.locationRecorder.isCapturing)
            let persisted = try await database.recording(id: id)
            XCTAssertEqual(persisted?.summary.sampleCount, 0)
            try execute("DROP TRIGGER fail_test_sample; DROP TRIGGER fail_test_finish", at: file)
            await model.finish()
            XCTAssertNil(model.currentRecording)
        } catch {
            await drainRecovery()
            throw error
        }
        await drainRecovery()
    }

    func testStartupRecoveryStartsCaptureBeforeSyncCanRefresh() async throws {
        let previousURL = ServerConfiguration.serverURL
        let previousApproval = UserDefaults.standard.string(forKey: "approved-pairing-origin")
        ServerConfiguration.serverURL = nil
        defer {
            ServerConfiguration.serverURL = previousURL
            UserDefaults.standard.set(previousApproval, forKey: "approved-pairing-origin")
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let database = try RecordingDatabase(fileURL: folder.appending(path: "test.sqlite"))
        _ = try await database.startRecording()
        var holdInitialRead = true
        var holdSyncRead = true
        var syncReadSuspended = false
        var releaseInitial: CheckedContinuation<Void, Never>?
        var releaseSync: CheckedContinuation<Void, Never>?
        let initialRead = expectation(description: "Startup read active recording")
        let syncAttempt = expectation(description: "Early sync completed or suspended its refresh")
        let model = AppModel(database: database, readRecording: { database, id in
            let snapshot = try await database.recording(id: id)
            if holdInitialRead {
                holdInitialRead = false
                initialRead.fulfill()
                await withCheckedContinuation { releaseInitial = $0 }
            } else if holdSyncRead {
                holdSyncRead = false
                syncReadSuspended = true
                syncAttempt.fulfill()
                await withCheckedContinuation { releaseSync = $0 }
            }
            return snapshot
        }, pairingExchange: { _ in })
        defer { model.locationRecorder.stopCapture() }
        let startup = Task { await model.prepare() }
        var pairing: Task<Void, Never>?
        func drainTasks() async {
            holdInitialRead = false
            holdSyncRead = false
            releaseInitial?.resume()
            releaseInitial = nil
            releaseSync?.resume()
            releaseSync = nil
            await startup.value
            await pairing?.value
        }
        do {
            await fulfillment(of: [initialRead], timeout: 5)
            guard releaseInitial != nil else { throw RecordingError.storage("Startup did not suspend") }
            model.receivePairing(payload: "onon://pair?server=http%3A%2F%2Fonon.local%3A3000&code=test")
            pairing = Task {
                await model.confirmPairing()
                if !syncReadSuspended { syncAttempt.fulfill() }
            }
            await fulfillment(of: [syncAttempt], timeout: 5)
            holdSyncRead = false
            releaseInitial?.resume()
            releaseInitial = nil
            await startup.value
            releaseSync?.resume()
            releaseSync = nil
            await pairing?.value

            XCTAssertTrue(model.isReady)
            XCTAssertTrue(model.isPaired)
            XCTAssertEqual(model.currentRecording?.summary.state, .active)
            XCTAssertTrue(model.locationRecorder.isCapturing)
            await model.commit(fix())
            XCTAssertEqual(model.currentRecording?.summary.sampleCount, 1)
        } catch {
            await drainTasks()
            throw error
        }
        await drainTasks()
    }

    func testTransitionsRetryRefreshInvalidatedByConcurrentSync() async throws {
        enum Transition: CaseIterable { case pause, resume, finish }
        let previousURL = ServerConfiguration.serverURL
        let previousApproval = UserDefaults.standard.string(forKey: "approved-pairing-origin")
        ServerConfiguration.serverURL = nil
        defer {
            ServerConfiguration.serverURL = previousURL
            UserDefaults.standard.set(previousApproval, forKey: "approved-pairing-origin")
        }
        for transition in Transition.allCases {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
            let database = try RecordingDatabase(fileURL: folder.appending(path: "test.sqlite"))
            _ = try await database.startRecording()
            var holdTransition = false
            var holdSync = false
            var releaseTransition: CheckedContinuation<Void, Never>?
            var releaseSync: CheckedContinuation<Void, Never>?
            let transitionRead = expectation(description: "Transition refresh suspended")
            let syncRead = expectation(description: "Sync refresh suspended")
            let model = AppModel(database: database, readSummaries: { database in
                let summaries = try await database.recordings()
                if holdTransition {
                    holdTransition = false
                    transitionRead.fulfill()
                    await withCheckedContinuation { releaseTransition = $0 }
                } else if holdSync {
                    holdSync = false
                    syncRead.fulfill()
                    await withCheckedContinuation { releaseSync = $0 }
                }
                return summaries
            }, pairingExchange: { _ in })
            defer { model.locationRecorder.stopCapture() }
            await model.prepare()
            model.receivePairing(payload: "onon://pair?server=http%3A%2F%2Fonon.local%3A3000&code=test")
            await model.confirmPairing()
            if transition == .resume { await model.pause() }
            holdTransition = true
            let operation = Task {
                switch transition {
                case .pause: await model.pause()
                case .resume: await model.resume()
                case .finish: await model.finish()
                }
            }
            var sync: Task<Void, Never>?
            func drainTasks() async {
                holdTransition = false
                holdSync = false
                releaseTransition?.resume()
                releaseTransition = nil
                releaseSync?.resume()
                releaseSync = nil
                await operation.value
                await sync?.value
            }
            do {
                await fulfillment(of: [transitionRead], timeout: 5)
                guard releaseTransition != nil else { throw RecordingError.storage("Transition did not suspend") }
                holdSync = true
                sync = Task { await model.syncNow() }
                await fulfillment(of: [syncRead], timeout: 5)
                guard releaseSync != nil else { throw RecordingError.storage("Sync did not suspend") }
                releaseTransition?.resume()
                releaseTransition = nil
                await operation.value
                releaseSync?.resume()
                releaseSync = nil
                await sync?.value

                XCTAssertNil(model.captureFailure)
                XCTAssertNil(model.alertMessage)
                switch transition {
                case .pause:
                    XCTAssertEqual(model.currentRecording?.summary.state, .paused)
                    XCTAssertFalse(model.locationRecorder.isCapturing)
                case .resume:
                    XCTAssertEqual(model.currentRecording?.summary.state, .active)
                    XCTAssertTrue(model.locationRecorder.isCapturing)
                case .finish:
                    XCTAssertNil(model.currentRecording)
                    XCTAssertFalse(model.finishNeedsRetry)
                    XCTAssertFalse(model.locationRecorder.isCapturing)
                }
            } catch {
                await drainTasks()
                throw error
            }
            await drainTasks()
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
