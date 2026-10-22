import Foundation
import Network

enum LocalServer {
    static func origin(_ url: URL) throws -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              var host = parts.host?.lowercased(),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port.map({ (1...65535).contains($0) }) ?? true
        else { throw PairingError.invalidServer }
        if host.hasSuffix(".") { host.removeLast() }
        guard isLocalHost(host) else { throw PairingError.invalidServer }
        parts.scheme = scheme
        parts.host = host
        parts.path = ""
        guard let origin = parts.url else { throw PairingError.invalidServer }
        return origin
    }

    private static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" { return true }
        if host.hasSuffix(".local") {
            return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
                !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
                label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
            }
        }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        if octets.count == 4 {
            let bytes = octets.compactMap { part -> UInt8? in
                guard let value = UInt8(part), String(value) == part else { return nil }
                return value
            }
            if bytes.count == 4 {
                return bytes[0] == 10 || bytes[0] == 127 ||
                    (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
                    (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254)
            }
        }
        let literal = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        guard !literal.contains("%"), let address = IPv6Address(literal) else { return false }
        let bytes = Array(address.rawValue)
        return bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) ||
            (bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1)
    }
}

/// Credentials and raw samples must never follow a redirect away from the approved origin.
final class RejectServerRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
