import CoreLocation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var recordings: [RecordingSummary] = []
    @Published private(set) var currentRecording: RecordingSnapshot?
    @Published private(set) var isReady = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isPaired = false
    @Published var alertMessage: String?

    let locationRecorder = LocationRecorder()
    let offlineMaps = OfflineMapManager()

    private var database: RecordingDatabase?
    private var syncService: SyncService?
    private var reachability: ReachabilitySyncTrigger?
    private var periodicSync: Task<Void, Never>?

    deinit { periodicSync?.cancel() }

    func prepare() async {
        guard !isReady else { return }
        do {
            let database = try RecordingDatabase()
            self.database = database
            syncService = SyncService(database: database)
            isPaired = (try DeviceTokenStore.load()) != nil && ServerConfiguration.serverURL != nil
            if let cachedManifest = MapManifestStore.load() { configureMap(cachedManifest) }
            locationRecorder.onAcceptedLocation = { [weak self] location in
                Task { @MainActor [weak self] in await self?.commit(location) }
            }
            reachability = ReachabilitySyncTrigger { [weak self] in
                Task { @MainActor [weak self] in await self?.syncNow() }
            }
            periodicSync = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    await self?.syncNow()
                }
            }
            try await reload()
            if currentRecording?.summary.state == .active {
                locationRecorder.startCapture()
            }
            if isPaired {
                await loadMapManifest()
                await syncNow()
            }
            isReady = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func start() async {
        guard let database else { return }
        guard locationRecorder.authorizationStatus == .authorizedAlways else {
            locationRecorder.requestPermission()
            if [.denied, .restricted].contains(locationRecorder.authorizationStatus) {
                alertMessage = "Location access is blocked. Enable Always access in Settings before starting."
            } else {
                alertMessage = "Allow Always location access, then tap Start recording again. No recording has been created yet."
            }
            return
        }
        do {
            let id = try await database.startRecording()
            currentRecording = try await database.recording(id: id)
            locationRecorder.startCapture()
            try await reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func pause() async {
        guard let database, let currentRecording else { return }
        do {
            try await database.setState(recordingID: currentRecording.summary.id, from: .active, to: .paused)
            locationRecorder.stopCapture()
            try await reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func resume() async {
        guard let database, let currentRecording else { return }
        do {
            try await database.setState(recordingID: currentRecording.summary.id, from: .paused, to: .active)
            locationRecorder.startCapture()
            try await reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func finish() async {
        guard let database, let currentRecording else { return }
        locationRecorder.stopCapture()
        do {
            try await database.setState(
                recordingID: currentRecording.summary.id,
                from: currentRecording.summary.state,
                to: .finished
            )
            try await reload()
            await syncNow()
        } catch {
            if currentRecording.summary.state == .active { locationRecorder.startCapture() }
            alertMessage = error.localizedDescription
        }
    }

    func addWaypoint() async {
        guard
            let database,
            let currentRecording,
            currentRecording.summary.state == .active,
            let location = locationRecorder.lastLocation,
            abs(location.timestamp.timeIntervalSinceNow) < 30
        else {
            alertMessage = RecordingError.noUsableLocation.localizedDescription
            return
        }
        do {
            try await database.appendWaypoint(recordingID: currentRecording.summary.id, waypoint: WaypointObservation(location: location))
            try await reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func completePairing(payload: String) async {
        do {
            let service = PairingService()
            let qr = try service.decode(payload: payload)
            try await service.pair(qrCode: qr)
            isPaired = true
            await loadMapManifest()
            await syncNow()
        } catch { alertMessage = error.localizedDescription }
    }

    func unpair() {
        do {
            try DeviceTokenStore.remove()
            ServerConfiguration.serverURL = nil
            isPaired = false
        } catch { alertMessage = error.localizedDescription }
    }

    func syncNow() async {
        guard let syncService, isPaired, !isSyncing else { return }
        isSyncing = true
        await syncService.syncPending()
        try? await reload()
        isSyncing = false
    }

    func loadMapManifest() async {
        guard let serverURL = ServerConfiguration.serverURL else { return }
        do {
            let manifest = try await MapManifestService().fetch()
            MapManifestStore.save(manifest)
            configureMap(manifest, serverURL: serverURL)
        } catch {
            alertMessage = "Paired, but map manifest failed: \(error.localizedDescription)"
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

    private func commit(_ location: CLLocation) async {
        guard let database, let snapshot = currentRecording, snapshot.summary.state == .active else { return }
        do {
            let sample = RawSample(sequence: snapshot.summary.sampleCount, location: location)
            try await database.appendSample(recordingID: snapshot.summary.id, locationSample: sample)
            currentRecording = try await database.recording(id: snapshot.summary.id)
        } catch {
            if let stored = try? await database.recording(id: snapshot.summary.id), stored.summary.state == .finished {
                return
            }
            locationRecorder.stopCapture()
            alertMessage = "Recording stopped to protect data: \(error.localizedDescription)"
        }
    }

    private func reload() async throws {
        guard let database else { return }
        recordings = try await database.recordings()
        if let unfinished = try await database.unfinishedRecording() {
            currentRecording = try await database.recording(id: unfinished.id)
        } else {
            currentRecording = nil
        }
    }
}
