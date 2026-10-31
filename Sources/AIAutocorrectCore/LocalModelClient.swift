import Foundation

public enum ModelClientError: Error, LocalizedError {
    case invalidLocalURL
    case requestTooLarge
    case responseTooLarge
    case invalidResponse
    case modelRequired
    case protectedTextChanged

    public var errorDescription: String? {
        switch self {
        case .invalidLocalURL: return "Use an HTTP API on this Mac, such as http://127.0.0.1:1234/v1."
        case .requestTooLarge: return "That text is too long for one local rewrite."
        case .responseTooLarge: return "The local model sent a response that was too large."
        case .invalidResponse: return "The local model returned an unreadable response."
        case .modelRequired: return "Choose a model before rewriting text."
        case .protectedTextChanged: return "Rewrite refused: it changed protected text. Your original remains editable."
        }
    }
}

private final class BoundedHTTP: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    private let limit: Int
    private var data = Data()
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var response: HTTPURLResponse?
    private var failed = false

    init(limit: Int) { self.limit = limit }

    func run(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 40
            configuration.timeoutIntervalForResource = 45
            configuration.httpMaximumConnectionsPerHost = 1
            configuration.connectionProxyDictionary = [:]
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              http.expectedContentLength < 0 || http.expectedContentLength <= Int64(limit) else {
            failed = true
            completionHandler(.cancel)
            return
        }
        self.response = http
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard data.count + chunk.count <= limit else {
            failed = true
            dataTask.cancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        guard let continuation else { return }
        self.continuation = nil
        if failed { continuation.resume(throwing: ModelClientError.responseTooLarge) }
        else if let error { continuation.resume(throwing: error) }
        else if let response { continuation.resume(returning: (data, response)) }
        else { continuation.resume(throwing: ModelClientError.invalidResponse) }
    }
}

public enum LocalModelClient {
    public static func isAllowedBaseURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1"].contains(host),
              url.path.count <= 120, !url.path.contains(".."),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        return true
    }

    public static func models(at raw: String) async throws -> [String] {
        let url = try endpoint(raw, suffix: "models")
        var request = URLRequest(url: url); request.httpMethod = "GET"
        let (data, response) = try await BoundedHTTP(limit: 1_000_000).run(request)
        guard (200..<300).contains(response.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { throw ModelClientError.invalidResponse }
        return items.compactMap { $0["id"] as? String }.filter { $0.count <= 160 }.sorted()
    }

    public static func rewrite(_ text: String, baseURL: String, model: String, tinySlip: Bool) async throws -> (String, StyleSignal) {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelClientError.modelRequired }
        guard text.utf8.count <= 32_000 else { throw ModelClientError.requestTooLarge }
        let url = try endpoint(baseURL, suffix: "chat/completions")
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "max_tokens": 3000,
            "messages": [
                ["role": "system", "content": HumanizerLogic.prompt],
                ["role": "user", "content": text]
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        guard body.count <= 48_000 else { throw ModelClientError.requestTooLarge }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await BoundedHTTP(limit: 1_000_000).run(request)
        guard (200..<300).contains(response.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              content.utf8.count <= 32_000 else { throw ModelClientError.invalidResponse }
        guard HumanizerLogic.preservesProtectedFragments(original: text, rewritten: content) else {
            throw ModelClientError.protectedTextChanged
        }
        let rewritten = HumanizerLogic.tinySlip(content, enabled: tinySlip)
        return (rewritten, HumanizerLogic.styleSignal(for: rewritten))
    }

    private static func endpoint(_ raw: String, suffix: String) throws -> URL {
        guard isAllowedBaseURL(raw), var components = URLComponents(string: raw) else { throw ModelClientError.invalidLocalURL }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").reduce(into: "") { partial, piece in partial += "/" + piece }
        components.path += "/" + suffix
        guard let url = components.url else { throw ModelClientError.invalidLocalURL }
        return url
    }
}
