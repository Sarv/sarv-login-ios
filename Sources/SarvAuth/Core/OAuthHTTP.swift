import Foundation

/// The token / revoke / userinfo calls. Sarv's token endpoint takes a JSON
/// body (not form-encoded) and answers errors as `{"detail": "..."}`.
struct OAuthHTTP {
    let configuration: SarvAuthConfiguration
    let session: URLSession

    func postJSON(_ path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: configuration.endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        return try await send(request)
    }

    func getJSON(_ path: String, bearer: String) async throws -> Data {
        var request = URLRequest(url: configuration.endpoint(path))
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SarvAuthError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SarvAuthError.invalidResponse("not an HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = Self.detail(from: data)
            if http.statusCode == 429 { throw SarvAuthError.rateLimited(detail: detail) }
            throw SarvAuthError.server(status: http.statusCode, detail: detail)
        }
        return data
    }

    /// `{"detail": "..."}` (what the server sends) or the RFC's `error_description`.
    static func detail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? String(text!.prefix(300)) : nil
        }
        if let detail = object["detail"] as? String { return detail }
        if let description = object["error_description"] as? String { return description }
        return object["error"] as? String
    }
}
