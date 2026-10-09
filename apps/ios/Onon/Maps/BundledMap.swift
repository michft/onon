import Foundation

enum BundledMap {
    static func styleURL(dark: Bool, bundle: Bundle = .main) -> URL? {
        guard let resources = bundle.url(forResource: "Protomaps", withExtension: nil) else { return nil }
        let flavor = dark ? "dark" : "light"
        let files = FileManager.default
        guard files.fileExists(atPath: resources.appending(path: "sydney.pmtiles").path) else { return nil }
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
            return nil
        }
    }

    static func resolvedStyle(_ template: String, resourceURL: URL) -> String {
        let value = resourceURL.absoluteString
        let root = value.hasSuffix("/") ? String(value.dropLast()) : value
        return template.replacingOccurrences(of: "__MAP_ROOT__", with: root)
    }
}
