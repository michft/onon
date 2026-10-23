import CoreLocation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var recordings: [RecordingSummary] = []
    @Published private(set) var currentRecording: RecordingSnapshot?
    @Published private(set) var isReady = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isPaired = false
    @Published private(set) var serverReachable = false
    @Published private(set) var captureFailure: String?
    @Published private(set) var finishingRecordingID: UUID?
    var finishNeedsRetry: Bool { finishingRecordingID != nil }
    @Published private(set) var pendingPairing: PairingQRCode?
    @Published private(set) var isPairing = false
    @Published var alertMessage: String? {
        didSet { if let alertMessage { Log.recording.error("Alert shown: \(alertMessage, privacy: .public)") } }
    }

    let locationRecorder = LocationRecorder()
    let offlineMaps = OfflineMapManager()

    private var database: RecordingDatabase?
    private var syncService: SyncService?
    private var reachability: ReachabilitySyncTrigger?
    private var periodicSync: Task<Void, Never>?
    private var isFinishing = false
    private var captureIntent = UUID()
    // A completed storage mutation invalidates snapshots fetched before it.
    private var recordingRevision = UUID()
    private let readSummaries: @MainActor (RecordingDatabase) async throws -> [RecordingSummary]
    private let readRecording: @MainActor (RecordingDatabase, UUID) async throws -> RecordingSnapshot?
    private let pairingExchange: @MainActor (PairingQRCode) async throws -> Void

    init(database: RecordingDatabase? = nil,
         readSummaries: @escaping @MainActor (RecordingDatabase) async throws -> [RecordingSummary] = { try await $0.recordings() },
         readRecording: @escaping @MainActor (RecordingDatabase, UUID) async throws -> RecordingSnapshot? = { try await $0.recording(id: $1) },
         pairingExchange: @escaping @MainActor (PairingQRCode) async throws -> Void = { try await PairingService().pair(qrCode: $0) }) {
        self.database = database
        self.readSummaries = readSummaries
        self.readRecording = readRecording
        self.pairingExchange = pairingExchange
    }

    deinit { periodicSync?.cancel() }

    func prepare() async {
        guard !isReady else { return }
        do {
            let database = try self.database ?? RecordingDatabase()
            self.database = database
            syncService = SyncService(database: database)
            isPaired = (try DeviceTokenStore.load()) != nil && ServerConfiguration.approvedServerURL != nil
            locationRecorder.onAcceptedLocation = { [weak self] location in
                Task { @MainActor [weak self] in await self?.commit(location) }
            }
            try await reload()
            if let summary = currentRecording?.summary {
                Log.recording.notice("Recovered \(summary.state.rawValue, privacy: .public) recording \(summary.id, privacy: .public) with \(summary.sampleCount) samples")
            }
            if currentRecording?.summary.state == .active {
                locationRecorder.startCapture()
            }
            isReady = true
            reachability = ReachabilitySyncTrigger { [weak self] in
                Task { @MainActor [weak self] in await self?.syncNow() }
            }
            periodicSync?.cancel()
            periodicSync = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    await self?.syncNow()
                }
            }
        } catch {
            Log.storage.fault("Startup failed: \(error.localizedDescription, privacy: .public)")
            alertMessage = error.localizedDescription
        }
    }

    func start() async {
        guard let database, !finishNeedsRetry else { return }
        guard locationRecorder.authorizationStatus == .authorizedAlways else {
            locationRecorder.requestPermission()
            if [.denied, .restricted].contains(locationRecorder.authorizationStatus) {
                alertMessage = "Location access is blocked. Enable Always access in Settings before starting."
            } else if locationRecorder.authorizationStatus == .authorizedWhenInUse {
                // iOS shows the Always prompt only once; after that only Settings can grant it.
                alertMessage = "Onon needs Always location access to keep recording while the phone is locked. If no prompt appears, open Settings › Onon › Location and choose Always."
            } else {
                alertMessage = "Allow Always location access, then tap Start recording again. No recording has been created yet."
            }
            return
        }
        do {
            let id = try await database.startRecording()
            recordingRevision = UUID()
            Log.recording.notice("Started recording \(id, privacy: .public)")
            currentRecording = try await database.recording(id: id)
            captureFailure = nil
            locationRecorder.startCapture()
            try await reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func pause() async {
        guard let database, let currentRecording, !finishNeedsRetry else { return }
        let intent = UUID()
        captureIntent = intent
        do {
            try await database.setState(recordingID: currentRecording.summary.id, from: .active, to: .paused)
            recordingRevision = UUID()
            guard intent == captureIntent else { return }
            Log.recording.notice("Paused recording \(currentRecording.summary.id, privacy: .public)")
            locationRecorder.stopCapture()
            try await reload()
            guard intent == captureIntent else { return }
            guard self.currentRecording?.summary.id == currentRecording.summary.id,
                  self.currentRecording?.summary.state == .paused else {
                throw RecordingError.storage("Paused recording could not be refreshed")
            }
        } catch {
            guard intent == captureIntent else { return }
            captureFailure = error.localizedDescription
            locationRecorder.stopCapture()
            alertMessage = "Capture remains stopped: \(error.localizedDescription) Tap Resume to try again."
        }
    }

    func resume() async {
        guard let database, let currentRecording, !finishNeedsRetry else { return }
        let intent = UUID()
        captureIntent = intent
        do {
            guard let persisted = try await readRecording(database, currentRecording.summary.id) else {
                throw RecordingError.noActiveSession
            }
            guard intent == captureIntent, !finishNeedsRetry else { return }
            switch persisted.summary.state {
            case .paused:
                try await database.setState(recordingID: persisted.summary.id, from: .paused, to: .active)
                recordingRevision = UUID()
            case .active:
                break // A previous Resume may have committed before its reload failed.
            case .finished:
                throw RecordingError.invalidTransition
            }
            guard intent == captureIntent, !finishNeedsRetry else { return }
            try await reload()
            guard intent == captureIntent, !finishNeedsRetry else { return }
            guard self.currentRecording?.summary.id == persisted.summary.id,
                  self.currentRecording?.summary.state == .active else {
                throw RecordingError.invalidTransition
            }
            captureFailure = nil
            Log.recording.notice("Resumed recording \(persisted.summary.id, privacy: .public)")
            locationRecorder.startCapture()
        } catch {
            guard intent == captureIntent, !finishNeedsRetry else { return }
            captureFailure = error.localizedDescription
            locationRecorder.stopCapture()
            alertMessage = "Capture remains stopped: \(error.localizedDescription) Tap Resume to try again."
        }
    }

    func finish() async {
        guard let database, !isFinishing,
              let recordingID = finishingRecordingID ?? currentRecording?.summary.id else { return }
        isFinishing = true
        captureIntent = UUID()
        finishingRecordingID = recordingID
        locationRecorder.stopCapture()
        defer { isFinishing = false }
        do {
            guard let persisted = try await readRecording(database, recordingID) else {
                throw RecordingError.noActiveSession
            }
            if persisted.summary.state != .finished {
                try await database.setState(
                    recordingID: persisted.summary.id,
                    from: persisted.summary.state,
                    to: .finished
                )
                recordingRevision = UUID()
            }
            try await reload()
            guard self.currentRecording?.summary.id != recordingID,
                  recordings.contains(where: { $0.id == recordingID && $0.state == .finished }) else {
                throw RecordingError.storage("Finished recording could not be refreshed")
            }
            captureFailure = nil
            finishingRecordingID = nil
            Log.recording.notice("Finished recording \(persisted.summary.id, privacy: .public) with \(persisted.summary.sampleCount) samples, \(persisted.summary.waypointCount) waypoints")
            await syncNow()
        } catch {
            captureFailure = error.localizedDescription
            locationRecorder.stopCapture()
            alertMessage = "Capture remains stopped: \(error.localizedDescription) Tap Retry finish to finish saving."
        }
    }

    func addWaypoint() async {
        let maximumAge = WaypointFixAge.current
        guard
            let database,
            captureFailure == nil,
            let currentRecording,
            currentRecording.summary.state == .active,
            let location = locationRecorder.lastLocation,
            abs(location.timestamp.timeIntervalSinceNow) <= maximumAge
        else {
            Log.recording.notice("Waypoint refused: no fix newer than \(Int(maximumAge))s while active")
            alertMessage = "No accurate location from the last \(WaypointFixAge.label(maximumAge)). Move a few metres or wait for a fix, or allow older fixes in the waypoint menu."
            return
        }
        do {
            try await database.appendWaypoint(recordingID: currentRecording.summary.id, waypoint: WaypointObservation(location: location))
            recordingRevision = UUID()
            Log.recording.notice("Added waypoint to \(currentRecording.summary.id, privacy: .public) at ±\(location.horizontalAccuracy, format: .fixed(precision: 0))m")
            try await reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func receivePairing(payload: String) {
        guard pendingPairing == nil, !isPairing else { return }
        do { pendingPairing = try PairingService().decode(payload: payload) }
        catch { alertMessage = error.localizedDescription }
    }

    func cancelPairing() { pendingPairing = nil }

    func confirmPairing() async {
        guard let qr = pendingPairing, !isPairing, !isSyncing else { return }
        pendingPairing = nil
        isPairing = true
        do {
            try await pairingExchange(qr)
            isPaired = true
            await loadMapManifest(showError: true)
            isPairing = false
            await syncNow()
        } catch {
            isPairing = false
            alertMessage = error.localizedDescription
        }
    }

    func unpair() {
        do {
            try DeviceTokenStore.remove()
            ServerConfiguration.serverURL = nil
            isPaired = false
            serverReachable = false
        } catch { alertMessage = error.localizedDescription }
    }

    func syncNow() async {
        guard isReady, let syncService, isPaired, !isSyncing, !isPairing, pendingPairing == nil else { return }
        isSyncing = true
        await syncService.syncPending()
        recordingRevision = UUID()
        do { try await reload() } catch { Log.storage.error("Reload after sync failed: \(error.localizedDescription, privacy: .public)") }
        isSyncing = false
    }

    func loadMapManifest(showError: Bool = false) async {
        guard let serverURL = ServerConfiguration.approvedServerURL else { return }
        do {
            let manifest = try await MapManifestService().fetch()
            MapManifestStore.save(manifest)
            configureMap(manifest, serverURL: serverURL)
            serverReachable = true
        } catch {
            serverReachable = false
            if showError { alertMessage = "Onon server unreachable. Recording remains available offline." }
        }
    }

    private func configureMap(_ manifest: MapManifest, serverURL: URL? = ServerConfiguration.serverURL) {
        guard
            let serverURL,
            let bounds = manifest.coordinateBounds,
            let styleURL = manifest.screenStyleURL(relativeTo: serverURL)
        else { return }
        offlineMaps.configure(
            styleURL: styleURL,
            serviceBounds: bounds,
            overviewMaxZoom: manifest.overviewMaxZoom,
            detailMaxZoom: manifest.detailMaxZoom
        )
    }

    func commit(_ location: CLLocation) async {
        guard captureFailure == nil, let database, let snapshot = currentRecording, snapshot.summary.state == .active else { return }
        let recordingID = snapshot.summary.id
        let intent = captureIntent
        do {
            let sample = try await database.appendSample(
                recordingID: recordingID,
                locationSample: RawSample(sequence: snapshot.summary.sampleCount, location: location)
            )
            recordingRevision = UUID()
            // State may have moved on while awaiting storage; append only when this is the next sample.
            if let current = currentRecording, current.summary.id == recordingID, current.summary.sampleCount == sample.id {
                currentRecording = current.appending(sample)
            } else if currentRecording?.summary.id == recordingID {
                let revision = recordingRevision
                let refreshed = try await database.recording(id: recordingID)
                guard revision == recordingRevision, currentRecording?.summary.id == recordingID else { return }
                currentRecording = refreshed
            }
            // Keep the Saved tab's counts current without re-querying every recording.
            if let summary = currentRecording?.summary, let index = recordings.firstIndex(where: { $0.id == summary.id }) {
                recordings[index] = summary
            }
        } catch RecordingError.noActiveSession {
            // A pause or finish that raced this fix; expected, not data loss.
            Log.storage.debug("Dropped a fix that raced a pause or finish")
        } catch {
            Log.storage.fault("Sample save failed for \(recordingID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            guard intent == captureIntent, !finishNeedsRetry else { return }
            captureFailure = error.localizedDescription
            locationRecorder.stopCapture()
            do {
                try await database.setState(recordingID: recordingID, from: .active, to: .paused)
                recordingRevision = UUID()
                try await reload()
            } catch {
                Log.storage.fault("Could not pause after sample save failure: \(error.localizedDescription, privacy: .public)")
            }
            guard intent == captureIntent, !finishNeedsRetry else { return }
            alertMessage = "Capture stopped to protect data: \(error.localizedDescription) Tap Resume to try again."
        }
    }

    func reload() async throws {
        guard let database else { return }
        let intent = captureIntent
        let revision = recordingRevision
        let summaries = try await readSummaries(database)
        let unfinished = summaries.first { $0.state != .finished }
        let snapshot: RecordingSnapshot?
        if let unfinished {
            snapshot = try await readRecording(database, unfinished.id)
        } else {
            snapshot = nil
        }
        guard intent == captureIntent, revision == recordingRevision else { return }
        recordings = summaries
        currentRecording = snapshot
    }
}
