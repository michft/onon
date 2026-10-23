import Foundation
import Network

actor SyncService {
    struct UploadResponse: Decodable {
        let recordingId: String
        let status: String
    }

    private let database: RecordingDatabase
    private let session: URLSession
    private var syncing = false

    init(database: RecordingDatabase, session: URLSession = .shared) {
        self.database = database
        self.session = session
    }

    func syncPending() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }

        guard let endpoint = ServerConfiguration.endpoint("api/v1/recordings") else {
            Log.sync.debug("Sync skipped: no paired server")
            return
        }
        let token: String
        do {
            guard let stored = try DeviceTokenStore.load() else {
                Log.sync.notice("Sync skipped: no device token")
                return
            }
            token = stored
        } catch {
            Log.sync.error("Sync skipped: \(error.localizedDescription, privacy: .public)")
            return
        }

        let ids: [UUID]
        do { ids = try await database.pendingRecordingIDs() } catch {
            Log.sync.error("Could not list pending recordings: \(error.localizedDescription, privacy: .public)")
            return
        }
        if !ids.isEmpty { Log.sync.notice("Uploading \(ids.count) pending recording(s)") }
        for id in ids {
            do {
                guard let snapshot = try await database.recording(id: id) else { continue }
                let upload = try RecordingUpload(snapshot: snapshot)
                try await database.setSyncState(recordingID: id, state: .uploading)
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue(id.uuidString, forHTTPHeaderField: "Idempotency-Key")
                request.httpBody = try APIJSON.encoder.encode(upload)
                let (data, response) = try await session.data(for: request, delegate: RejectServerRedirects())
                guard let http = response as? HTTPURLResponse, [200, 201].contains(http.statusCode) else {
                    throw SyncError.rejected((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                let receipt = try JSONDecoder().decode(UploadResponse.self, from: data)
                guard receipt.recordingId == id.uuidString, ["created", "existing"].contains(receipt.status) else {
                    throw SyncError.invalidReceipt
                }
                try await database.setSyncState(recordingID: id, state: .confirmed, serverRecordingID: receipt.recordingId)
                Log.sync.notice("Recording \(id, privacy: .public) confirmed (\(receipt.status, privacy: .public))")
            } catch {
                Log.sync.error("Recording \(id, privacy: .public) upload failed: \(error.localizedDescription, privacy: .public)")
                do { try await database.setSyncState(recordingID: id, state: .failed) } catch {
                    Log.storage.error("Could not mark \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

enum SyncError: LocalizedError {
    case rejected(Int)
    case invalidReceipt

    var errorDescription: String? {
        switch self {
        case let .rejected(status): "Sync failed (HTTP \(status))."
        case .invalidReceipt: "Server returned an invalid sync receipt."
        }
    }
}

@MainActor
final class ReachabilitySyncTrigger {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Onon.Reachability")
    private let onReachable: @Sendable () -> Void

    init(onReachable: @escaping @Sendable () -> Void) {
        self.onReachable = onReachable
        monitor.pathUpdateHandler = { [onReachable] path in
            guard path.status == .satisfied else { return }
            onReachable()
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
