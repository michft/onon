import Foundation

struct MapManifest: Codable, Sendable {
    struct Styles: Codable, Sendable {
        let screen: String
        let blueLightPrint: String
        let greyscalePrint: String
    }

    let version: String
    let bounds: [Double]
    let overviewMaxZoom: Double
    let detailMaxZoom: Double
    let styles: Styles

    var coordinateBounds: OfflineBounds? {
        guard bounds.count == 4 else { return nil }
        return OfflineBounds(west: bounds[0], south: bounds[1], east: bounds[2], north: bounds[3])
    }

    func screenStyleURL(relativeTo serverURL: URL) -> URL? {
        URL(string: styles.screen, relativeTo: serverURL)?.absoluteURL
    }
}

enum MapManifestStore {
    private static let key = "last-map-manifest"

    static func save(_ manifest: MapManifest) {
        if let data = try? JSONEncoder().encode(manifest) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> MapManifest? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MapManifest.self, from: data)
    }
}

struct MapManifestService: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetch() async throws -> MapManifest {
        guard let endpoint = ServerConfiguration.endpoint("api/v1/maps/manifest") else {
            throw PairingError.invalidServer
        }
        let (data, response) = try await session.data(from: endpoint)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.rejected((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(MapManifest.self, from: data)
    }
}
