import CoreLocation
import Foundation
import MapLibre

struct OfflineBounds: Codable, Equatable, Sendable {
    let west: Double
    let south: Double
    let east: Double
    let north: Double

    var mapLibreBounds: MLNCoordinateBounds {
        MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: south, longitude: west),
            ne: CLLocationCoordinate2D(latitude: north, longitude: east)
        )
    }
}

struct OfflineArea: Identifiable, Equatable {
    enum State: String, Codable {
        case inactive
        case downloading
        case complete
        case failed
    }

    let id: UUID
    let name: String
    let bounds: OfflineBounds
    let minimumZoom: Double
    let maximumZoom: Double
    var completedResources: UInt64
    var expectedResources: UInt64
    var completedBytes: UInt64
    var state: State
    var error: String?

    var progress: Double {
        guard expectedResources > 0 else { return state == .complete ? 1 : 0 }
        return min(1, Double(completedResources) / Double(expectedResources))
    }
}

@MainActor
final class OfflineMapManager: ObservableObject {
    @Published private(set) var areas: [OfflineArea] = []
    @Published private(set) var styleURL: URL?
    @Published private(set) var serviceBounds: OfflineBounds?
    @Published private(set) var overviewMaxZoom: Double = 11
    @Published private(set) var detailMaxZoom: Double = 14
    @Published var lastError: String?

    private struct Context: Codable {
        let id: UUID
        let name: String
        let bounds: OfflineBounds
        let minimumZoom: Double
        let maximumZoom: Double
    }

    private var packs: [UUID: MLNOfflinePack] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.MLNOfflinePackProgressChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let pack = notification.object as? MLNOfflinePack else { return }
            Task { @MainActor [weak self] in self?.update(pack: pack) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.MLNOfflinePackError,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let pack = notification.object as? MLNOfflinePack else { return }
            Task { @MainActor [weak self] in self?.fail(pack: pack, message: "Offline download failed; retry when the map server is reachable.") }
        })
        restorePacks()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func configure(styleURL: URL, serviceBounds: OfflineBounds, overviewMaxZoom: Double, detailMaxZoom: Double) {
        self.styleURL = styleURL
        self.serviceBounds = serviceBounds
        self.overviewMaxZoom = overviewMaxZoom
        self.detailMaxZoom = detailMaxZoom
    }

    func downloadOverview() {
        guard let serviceBounds else { return }
        add(name: "Sydney overview", bounds: serviceBounds, minimumZoom: 7, maximumZoom: overviewMaxZoom)
    }

    func downloadDetail(name: String, bounds: OfflineBounds) {
        add(name: name, bounds: bounds, minimumZoom: max(10, overviewMaxZoom - 1), maximumZoom: detailMaxZoom)
    }

    func pause(_ id: UUID) {
        packs[id]?.suspend()
        setState(id, .inactive)
    }

    func resume(_ id: UUID) {
        packs[id]?.resume()
        setState(id, .downloading)
    }

    func remove(_ id: UUID) {
        guard let pack = packs[id] else { return }
        pack.suspend()
        MLNOfflineStorage.shared.removePack(pack) { [weak self] error in
            Task { @MainActor [weak self] in
                if let error { self?.lastError = error.localizedDescription; return }
                self?.packs[id] = nil
                self?.areas.removeAll { $0.id == id }
            }
        }
    }

    func estimatedBytes(bounds: OfflineBounds, minimumZoom: Double, maximumZoom: Double) -> Int64 {
        let tileCount = (Int(minimumZoom.rounded(.down))...Int(maximumZoom.rounded(.down))).reduce(0.0) { total, zoom in
            let side = pow(2, Double(zoom))
            let westX = (bounds.west + 180) / 360 * side
            let eastX = (bounds.east + 180) / 360 * side
            func y(_ latitude: Double) -> Double {
                let radians = latitude * .pi / 180
                return (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2 * side
            }
            return total + max(1, eastX - westX) * max(1, y(bounds.south) - y(bounds.north))
        }
        // Planning estimate only: vector tile size varies greatly with feature density.
        return Int64(tileCount * 18_000 * 1.15)
    }

    private func add(name: String, bounds: OfflineBounds, minimumZoom: Double, maximumZoom: Double) {
        guard let styleURL else { lastError = "Pair first to load the local map style."; return }
        let id = UUID()
        let context = Context(id: id, name: name, bounds: bounds, minimumZoom: minimumZoom, maximumZoom: maximumZoom)
        guard let data = try? JSONEncoder().encode(context) else { return }
        let region = MLNTilePyramidOfflineRegion(
            styleURL: styleURL,
            bounds: bounds.mapLibreBounds,
            fromZoomLevel: minimumZoom,
            toZoomLevel: maximumZoom
        )
        MLNOfflineStorage.shared.addPack(for: region, withContext: data) { [weak self] pack, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let pack else { self.lastError = error?.localizedDescription ?? "Could not create offline area"; return }
                self.packs[id] = pack
                self.areas.append(OfflineArea(
                    id: id, name: name, bounds: bounds, minimumZoom: minimumZoom, maximumZoom: maximumZoom,
                    completedResources: 0, expectedResources: 0, completedBytes: 0, state: .downloading, error: nil
                ))
                pack.resume()
            }
        }
    }

    private func restorePacks() {
        for pack in MLNOfflineStorage.shared.packs ?? [] {
            guard let context = try? JSONDecoder().decode(Context.self, from: pack.context) else { continue }
            packs[context.id] = pack
            areas.append(area(context: context, pack: pack))
            pack.requestProgress()
        }
    }

    private func update(pack: MLNOfflinePack) {
        guard let context = try? JSONDecoder().decode(Context.self, from: pack.context) else { return }
        packs[context.id] = pack
        let value = area(context: context, pack: pack)
        if let index = areas.firstIndex(where: { $0.id == context.id }) { areas[index] = value } else { areas.append(value) }
    }

    private func fail(pack: MLNOfflinePack, message: String) {
        guard let context = try? JSONDecoder().decode(Context.self, from: pack.context),
              let index = areas.firstIndex(where: { $0.id == context.id }) else { return }
        areas[index].state = .failed
        areas[index].error = message
    }

    private func area(context: Context, pack: MLNOfflinePack) -> OfflineArea {
        let progress = pack.progress
        let complete = progress.countOfResourcesExpected > 0 && progress.countOfResourcesCompleted >= progress.countOfResourcesExpected
        let state: OfflineArea.State = complete ? .complete : (pack.state == .active ? .downloading : .inactive)
        return OfflineArea(
            id: context.id, name: context.name, bounds: context.bounds,
            minimumZoom: context.minimumZoom, maximumZoom: context.maximumZoom,
            completedResources: progress.countOfResourcesCompleted,
            expectedResources: progress.countOfResourcesExpected,
            completedBytes: progress.countOfBytesCompleted,
            state: state, error: nil
        )
    }

    private func setState(_ id: UUID, _ state: OfflineArea.State) {
        guard let index = areas.firstIndex(where: { $0.id == id }) else { return }
        areas[index].state = state
    }
}
