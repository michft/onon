import Foundation

struct PairingService: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func decode(payload: String) throws -> PairingQRCode {
        guard
            let components = URLComponents(string: payload),
            components.scheme == "onon",
            components.host == "pair",
            let serverValue = components.queryItems?.first(where: { $0.name == "server" })?.value,
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            !code.isEmpty
        else { throw PairingError.invalidCode }
        guard let serverURL = URL(string: serverValue), ["http", "https"].contains(serverURL.scheme?.lowercased()) else {
            throw PairingError.invalidServer
        }
        return PairingQRCode(serverURL: serverURL, pairingCode: code)
    }

    @MainActor
    func pair(qrCode: PairingQRCode) async throws {
        let endpoint = qrCode.serverURL.appending(path: "api/v1/pairings/exchange")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let identity = DeviceIdentity()
        request.httpBody = try APIJSON.encoder.encode(PairingRequest(
            code: qrCode.pairingCode,
            deviceId: identity.id,
            deviceName: identity.displayName
        ))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PairingError.rejected((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let value = try JSONDecoder().decode(PairingResponse.self, from: data)
        guard value.deviceId == identity.id else { throw PairingError.invalidCode }
        try DeviceTokenStore.save(value.deviceToken)
        ServerConfiguration.serverURL = qrCode.serverURL
    }
}
