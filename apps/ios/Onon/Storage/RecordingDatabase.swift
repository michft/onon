import Foundation
import SQLite3

actor RecordingDatabase {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(fileURL: URL? = nil) throws {
        let resolvedURL: URL
        if let fileURL {
            resolvedURL = fileURL
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appending(path: "Onon", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            resolvedURL = directory.appending(path: "recordings.sqlite")
        }

        guard sqlite3_open_v2(
            resolvedURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw RecordingError.storage("Could not open the database")
        }
        try Self.execute("PRAGMA journal_mode=WAL", database: database)
        try Self.execute("PRAGMA synchronous=FULL", database: database)
        try Self.execute("PRAGMA foreign_keys=ON", database: database)
        try Self.migrate(database: database)
    }

    deinit {
        sqlite3_close(database)
    }

    func startRecording(id: UUID = UUID(), at date: Date = Date()) throws -> UUID {
        if try unfinishedRecording() != nil {
            throw RecordingError.sessionAlreadyActive
        }
        try run(
            "INSERT INTO recordings(id, started_at, state, sync_state, updated_at) VALUES(?, ?, 'active', 'local', ?)",
            [.text(id.uuidString), .double(date.timeIntervalSince1970), .double(date.timeIntervalSince1970)]
        )
        return id
    }

    func setState(recordingID: UUID, from expected: RecordingState, to next: RecordingState, at date: Date = Date()) throws {
        guard allowedTransition(from: expected, to: next) else {
            throw RecordingError.invalidTransition
        }
        if next == .finished {
            try run(
                "UPDATE recordings SET state = ?, finished_at = ?, updated_at = ? WHERE id = ? AND state = ?",
                [.text(next.rawValue), .double(date.timeIntervalSince1970), .double(date.timeIntervalSince1970), .text(recordingID.uuidString), .text(expected.rawValue)]
            )
        } else {
            try run(
                "UPDATE recordings SET state = ?, updated_at = ? WHERE id = ? AND state = ?",
                [.text(next.rawValue), .double(date.timeIntervalSince1970), .text(recordingID.uuidString), .text(expected.rawValue)]
            )
        }
        guard sqlite3_changes(database) == 1 else {
            throw RecordingError.invalidTransition
        }
    }

    func appendSample(recordingID: UUID, locationSample: RawSample) throws {
        let sequence = try nextSequence(recordingID: recordingID)
        try run(
            """
            INSERT INTO samples(
                recording_id, sequence, recorded_at, latitude, longitude,
                horizontal_accuracy, altitude, vertical_accuracy, speed, course
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(recordingID.uuidString), .int(sequence),
                .double(locationSample.recordedAt.timeIntervalSince1970),
                .double(locationSample.latitude), .double(locationSample.longitude),
                .double(locationSample.horizontalAccuracy), .optionalDouble(locationSample.altitude),
                .optionalDouble(locationSample.verticalAccuracy), .optionalDouble(locationSample.speed),
                .optionalDouble(locationSample.course),
            ]
        )
    }

    private func nextSequence(recordingID: UUID) throws -> Int {
        let statement = try prepare(
            "SELECT COALESCE(MAX(sequence), -1) + 1 FROM samples WHERE recording_id = ?",
            bindings: [.text(recordingID.uuidString)]
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func appendWaypoint(recordingID: UUID, waypoint: WaypointObservation) throws {
        try run(
            "INSERT INTO waypoint_observations(id, recording_id, recorded_at, latitude, longitude, horizontal_accuracy) VALUES(?, ?, ?, ?, ?, ?)",
            [
                .text(waypoint.id.uuidString), .text(recordingID.uuidString),
                .double(waypoint.recordedAt.timeIntervalSince1970), .double(waypoint.latitude),
                .double(waypoint.longitude), .double(waypoint.horizontalAccuracy),
            ]
        )
    }

    func unfinishedRecording() throws -> RecordingSummary? {
        try summaries(whereClause: "WHERE r.state != 'finished' ORDER BY r.started_at DESC LIMIT 1").first
    }

    func recording(id: UUID) throws -> RecordingSnapshot? {
        guard let summary = try summaries(whereClause: "WHERE r.id = ?", bindings: [.text(id.uuidString)]).first else {
            return nil
        }
        return RecordingSnapshot(summary: summary, samples: try samples(id), waypoints: try waypoints(id))
    }

    func recordings() throws -> [RecordingSummary] {
        try summaries(whereClause: "ORDER BY r.started_at DESC")
    }

    func pendingRecordingIDs() throws -> [UUID] {
        let statement = try prepare("SELECT id FROM recordings WHERE state = 'finished' AND sync_state != 'confirmed' ORDER BY started_at")
        defer { sqlite3_finalize(statement) }
        var ids: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = UUID(uuidString: textColumn(statement, 0)) { ids.append(id) }
        }
        return ids
    }

    func setSyncState(recordingID: UUID, state: SyncState, serverRecordingID: String? = nil) throws {
        try run(
            "UPDATE recordings SET sync_state = ?, server_recording_id = COALESCE(?, server_recording_id), updated_at = ? WHERE id = ? AND state = 'finished'",
            [.text(state.rawValue), .optionalText(serverRecordingID), .double(Date().timeIntervalSince1970), .text(recordingID.uuidString)]
        )
    }

    private static func migrate(database: OpaquePointer?) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS recordings(
                id TEXT PRIMARY KEY,
                started_at REAL NOT NULL,
                finished_at REAL,
                state TEXT NOT NULL CHECK(state IN ('active','paused','finished')),
                sync_state TEXT NOT NULL CHECK(sync_state IN ('local','uploading','confirmed','failed')),
                server_recording_id TEXT,
                updated_at REAL NOT NULL
            );
            CREATE UNIQUE INDEX IF NOT EXISTS one_unfinished_recording
                ON recordings((1)) WHERE state != 'finished';
            CREATE TABLE IF NOT EXISTS samples(
                recording_id TEXT NOT NULL REFERENCES recordings(id),
                sequence INTEGER NOT NULL,
                recorded_at REAL NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                horizontal_accuracy REAL NOT NULL,
                altitude REAL,
                vertical_accuracy REAL,
                speed REAL,
                course REAL,
                PRIMARY KEY(recording_id, sequence)
            );
            CREATE TABLE IF NOT EXISTS waypoint_observations(
                id TEXT PRIMARY KEY,
                recording_id TEXT NOT NULL REFERENCES recordings(id),
                recorded_at REAL NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                horizontal_accuracy REAL NOT NULL
            );
            CREATE TRIGGER IF NOT EXISTS samples_are_immutable_update
                BEFORE UPDATE ON samples BEGIN SELECT RAISE(ABORT, 'raw samples are immutable'); END;
            CREATE TRIGGER IF NOT EXISTS samples_are_immutable_delete
                BEFORE DELETE ON samples BEGIN SELECT RAISE(ABORT, 'raw samples are immutable'); END;
            CREATE TRIGGER IF NOT EXISTS waypoints_are_immutable_update
                BEFORE UPDATE ON waypoint_observations BEGIN SELECT RAISE(ABORT, 'waypoint observations are immutable'); END;
            CREATE TRIGGER IF NOT EXISTS waypoints_are_immutable_delete
                BEFORE DELETE ON waypoint_observations BEGIN SELECT RAISE(ABORT, 'waypoint observations are immutable'); END;
            CREATE TRIGGER IF NOT EXISTS no_samples_after_finish
                BEFORE INSERT ON samples
                WHEN (SELECT state FROM recordings WHERE id = NEW.recording_id) = 'finished'
                BEGIN SELECT RAISE(ABORT, 'recording is finished'); END;
            CREATE TRIGGER IF NOT EXISTS no_waypoints_after_finish
                BEFORE INSERT ON waypoint_observations
                WHEN (SELECT state FROM recordings WHERE id = NEW.recording_id) = 'finished'
                BEGIN SELECT RAISE(ABORT, 'recording is finished'); END;
            CREATE TRIGGER IF NOT EXISTS samples_require_active_recording
                BEFORE INSERT ON samples
                WHEN COALESCE((SELECT state FROM recordings WHERE id = NEW.recording_id), '') != 'active'
                BEGIN SELECT RAISE(ABORT, 'recording is not active'); END;
            CREATE TRIGGER IF NOT EXISTS waypoints_require_active_recording
                BEFORE INSERT ON waypoint_observations
                WHEN COALESCE((SELECT state FROM recordings WHERE id = NEW.recording_id), '') != 'active'
                BEGIN SELECT RAISE(ABORT, 'recording is not active'); END;
            PRAGMA user_version=2;
            """,
            database: database
        )
    }

    private func allowedTransition(from: RecordingState, to: RecordingState) -> Bool {
        switch (from, to) {
        case (.active, .paused), (.paused, .active), (.active, .finished), (.paused, .finished): true
        default: false
        }
    }

    private func samples(_ id: UUID) throws -> [RawSample] {
        let statement = try prepare(
            "SELECT sequence, recorded_at, latitude, longitude, horizontal_accuracy, altitude, vertical_accuracy, speed, course FROM samples WHERE recording_id = ? ORDER BY sequence",
            bindings: [.text(id.uuidString)]
        )
        defer { sqlite3_finalize(statement) }
        var values: [RawSample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(RawSample(
                id: Int(sqlite3_column_int64(statement, 0)),
                recordedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                latitude: sqlite3_column_double(statement, 2), longitude: sqlite3_column_double(statement, 3),
                horizontalAccuracy: sqlite3_column_double(statement, 4), altitude: optionalDoubleColumn(statement, 5),
                verticalAccuracy: optionalDoubleColumn(statement, 6), speed: optionalDoubleColumn(statement, 7),
                course: optionalDoubleColumn(statement, 8)
            ))
        }
        return values
    }

    private func waypoints(_ id: UUID) throws -> [WaypointObservation] {
        let statement = try prepare(
            "SELECT id, recorded_at, latitude, longitude, horizontal_accuracy FROM waypoint_observations WHERE recording_id = ? ORDER BY recorded_at",
            bindings: [.text(id.uuidString)]
        )
        defer { sqlite3_finalize(statement) }
        var values: [WaypointObservation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let waypointID = UUID(uuidString: textColumn(statement, 0)) else { continue }
            values.append(WaypointObservation(
                id: waypointID, recordedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                latitude: sqlite3_column_double(statement, 2), longitude: sqlite3_column_double(statement, 3),
                horizontalAccuracy: sqlite3_column_double(statement, 4)
            ))
        }
        return values
    }

    private func summaries(whereClause: String, bindings: [Binding] = []) throws -> [RecordingSummary] {
        let statement = try prepare(
            """
            SELECT r.id, r.started_at, r.finished_at, r.state, r.sync_state,
                   (SELECT COUNT(*) FROM samples s WHERE s.recording_id = r.id),
                   (SELECT COUNT(*) FROM waypoint_observations w WHERE w.recording_id = r.id)
            FROM recordings r \(whereClause)
            """,
            bindings: bindings
        )
        defer { sqlite3_finalize(statement) }
        var values: [RecordingSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = UUID(uuidString: textColumn(statement, 0)),
                let state = RecordingState(rawValue: textColumn(statement, 3)),
                let syncState = SyncState(rawValue: textColumn(statement, 4))
            else { continue }
            values.append(RecordingSummary(
                id: id, startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                finishedAt: optionalDateColumn(statement, 2), state: state, syncState: syncState,
                sampleCount: Int(sqlite3_column_int64(statement, 5)), waypointCount: Int(sqlite3_column_int64(statement, 6))
            ))
        }
        return values
    }

    private enum Binding {
        case text(String)
        case optionalText(String?)
        case int(Int)
        case double(Double)
        case optionalDouble(Double?)
    }

    private func prepare(_ sql: String, bindings: [Binding] = []) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        do {
            for (offset, binding) in bindings.enumerated() {
                try bind(binding, at: Int32(offset + 1), to: statement)
            }
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
        return statement
    }

    private func run(_ sql: String, _ bindings: [Binding]) throws {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private static func execute(_ sql: String, database: OpaquePointer?) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(message)
            throw RecordingError.storage(detail)
        }
    }

    private func bind(_ binding: Binding, at index: Int32, to statement: OpaquePointer?) throws {
        let result: Int32
        switch binding {
        case let .text(value): result = sqlite3_bind_text(statement, index, value, -1, transient)
        case let .optionalText(value):
            result = value.map { sqlite3_bind_text(statement, index, $0, -1, transient) } ?? sqlite3_bind_null(statement, index)
        case let .int(value): result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case let .double(value): result = sqlite3_bind_double(statement, index, value)
        case let .optionalDouble(value): result = value.map { sqlite3_bind_double(statement, index, $0) } ?? sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw lastError() }
    }

    private func textColumn(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalDoubleColumn(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }

    private func optionalDateColumn(_ statement: OpaquePointer?, _ index: Int32) -> Date? {
        optionalDoubleColumn(statement, index).map(Date.init(timeIntervalSince1970:))
    }

    private func lastError() -> RecordingError {
        RecordingError.storage(String(cString: sqlite3_errmsg(database)))
    }
}
