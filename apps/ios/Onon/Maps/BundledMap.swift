import Foundation

enum BundledMap {
    @MainActor private static var resolvedStyleURLs: [Bool: URL?] = [:]

    /// Resolves each flavor once per launch; views call this on every render.
    @MainActor static func cachedStyleURL(dark: Bool) -> URL? {
        if let cached = resolvedStyleURLs[dark] { return cached }
        let url = styleURL(dark: dark)
        resolvedStyleURLs[dark] = url
        return url
    }

    static func styleURL(dark: Bool, bundle: Bundle = .main) -> URL? {
        guard let resources = bundle.url(forResource: "Protomaps", withExtension: nil) else {
            Log.map.fault("Bundled map folder Protomaps is missing from the app")
            return nil
        }
        let flavor = dark ? "dark" : "light"
        let files = FileManager.default
        guard files.fileExists(atPath: resources.appending(path: "sydney.pmtiles").path) else {
            Log.map.fault("Bundled map archive sydney.pmtiles is missing")
            return nil
        }
        do {
            let template = try String(contentsOf: resources.appending(path: "\(flavor).json"), encoding: .utf8)
            let data = Data(resolvedStyle(template, resourceURL: resources).utf8)
            let directory = try files.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "OnonMaps", directoryHint: .isDirectory)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "\(flavor).json")
            if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
            return url
        } catch {
            Log.map.fault("Could not prepare \(flavor, privacy: .public) map style: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func resolvedStyle(_ template: String, resourceURL: URL) -> String {
        let value = resourceURL.absoluteString
        let root = value.hasSuffix("/") ? String(value.dropLast()) : value
        return template.replacingOccurrences(of: "__MAP_ROOT__", with: root)
    }
}
