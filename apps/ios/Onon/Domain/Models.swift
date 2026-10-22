import CoreLocation
import Foundation

enum RecordingState: String, Codable, Sendable {
    case active
    case paused
    case finished
}

enum SyncState: String, Codable, Sendable {
    case local
    case uploading
    case confirmed
    case failed
}

struct RawSample: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let recordedAt: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double?
    let verticalAccuracy: Double?
    let speed: Double?
    let course: Double?

    init(sequence: Int, location: CLLocation) {
        id = sequence
        recordedAt = location.timestamp
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
        verticalAccuracy = location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
        speed = location.speed >= 0 ? location.speed : nil
        course = location.course >= 0 ? location.course : nil
    }

    init(
        id: Int,
        recordedAt: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        altitude: Double?,
        verticalAccuracy: Double?,
        speed: Double?,
        course: Double?
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct WaypointObservation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let recordedAt: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double

    init(id: UUID = UUID(), location: CLLocation) {
        self.id = id
        recordedAt = location.timestamp
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
    }

    init(id: UUID, recordedAt: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double) {
        self.id = id
        self.recordedAt = recordedAt
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
    }
}

struct RecordingSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date?
    let state: RecordingState
    let syncState: SyncState
    let sampleCount: Int
    let waypointCount: Int
}

struct RecordingSnapshot: Equatable, Sendable {
    let summary: RecordingSummary
    let samples: [RawSample]
    let waypoints: [WaypointObservation]

    /// Applies a committed sample without re-reading the whole recording from storage.
    func appending(_ sample: RawSample) -> RecordingSnapshot {
        RecordingSnapshot(
            summary: RecordingSummary(
                id: summary.id, startedAt: summary.startedAt, finishedAt: summary.finishedAt,
                state: summary.state, syncState: summary.syncState,
                sampleCount: summary.sampleCount + 1, waypointCount: summary.waypointCount
            ),
            samples: samples + [sample],
            waypoints: waypoints
        )
    }
}

struct PairingQRCode: Decodable, Equatable, Sendable {
    let serverURL: URL
    let pairingCode: String
}

struct PairingRequest: Encodable, Sendable {
    let code: String
    let deviceId: UUID
    let deviceName: String
}

struct PairingResponse: Decodable, Sendable {
    let deviceToken: String
    let deviceId: UUID
}

struct RecordingUpload: Encodable, Sendable {
    struct Sample: Encodable, Sendable {
        let sequence: Int
        let recordedAt: String
        let latitude: Double
        let longitude: Double
        let horizontalAccuracy: Double
        let altitude: Double?
        let verticalAccuracy: Double?
        let speed: Double?
        let course: Double?
    }

    struct Waypoint: Encodable, Sendable {
        let id: UUID
        let recordedAt: String
        let latitude: Double
        let longitude: Double
        let horizontalAccuracy: Double
    }

    let id: UUID
    let startedAt: String
    let finishedAt: String
    let samples: [Sample]
    let waypoints: [Waypoint]

    init(snapshot: RecordingSnapshot) throws {
        guard let finishedAt = snapshot.summary.finishedAt else {
            throw RecordingError.sessionNotFinished
        }
        id = snapshot.summary.id
        startedAt = APIJSON.dateString(snapshot.summary.startedAt)
        self.finishedAt = APIJSON.dateString(finishedAt)
        samples = snapshot.samples.map {
            Sample(
                sequence: $0.id,
                recordedAt: APIJSON.dateString($0.recordedAt),
                latitude: $0.latitude,
                longitude: $0.longitude,
                horizontalAccuracy: $0.horizontalAccuracy,
                altitude: $0.altitude,
                verticalAccuracy: $0.verticalAccuracy,
                speed: $0.speed,
                course: $0.course
            )
        }
        waypoints = snapshot.waypoints.map {
            Waypoint(
                id: $0.id,
                recordedAt: APIJSON.dateString($0.recordedAt),
                latitude: $0.latitude,
                longitude: $0.longitude,
                horizontalAccuracy: $0.horizontalAccuracy
            )
        }
    }
}

enum RecordingError: LocalizedError, Equatable {
    case noActiveSession
    case sessionAlreadyActive
    case invalidTransition
    case noUsableLocation
    case sessionNotFinished
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .noActiveSession: "No recording is active."
        case .sessionAlreadyActive: "A recording is already active."
        case .invalidTransition: "That recording transition is not allowed."
        case .noUsableLocation: "No accurate location is available yet."
        case .sessionNotFinished: "Only finished recordings can sync."
        case let .storage(message): "Recording storage error: \(message)"
        }
    }
}

/// How old the last accepted fix may be when placing a waypoint. While standing still iOS sends
/// no new fixes (2 m distance filter), so the last fix is usually still where the phone is.
enum WaypointFixAge {
    static let key = "waypointMaximumFixAge"
    static let options: [TimeInterval] = [15, 30, 60, 120, 300]
    static let defaultValue: TimeInterval = 120

    static var current: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? min(max(stored, options[0]), options[options.count - 1]) : defaultValue
    }

    static func label(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds)) seconds" : seconds == 60 ? "1 minute" : "\(Int(seconds / 60)) minutes"
    }
}

enum APIJSON {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
