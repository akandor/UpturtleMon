import Foundation

// MARK: - Wire models matching upturtle-server JSON

struct APISnapshot: Decodable {
    let config: APIMonitorConfig
    let status: String
    let lastChecked: Date
    let lastLatencyNanos: Int64
    let lastMessage: String
    let lastChange: Date
    let history: [APICheckResult]

    enum CodingKeys: String, CodingKey {
        case config = "Config"
        case status = "Status"
        case lastChecked = "LastChecked"
        case lastLatencyNanos = "LastLatency"
        case lastMessage = "LastMessage"
        case lastChange = "LastChange"
        case history = "History"
    }
}

struct APIMonitorConfig: Decodable {
    let id: String
    let name: String
    let type: String
    let target: String
    let intervalNanos: Int64
    let timeoutNanos: Int64
    let enabled: Bool
    let group: String?
    let groupID: Int?
    let order: Int?
    let parentID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case target
        case intervalNanos = "interval"
        case timeoutNanos = "timeout"
        case enabled
        case group
        case groupID = "group_id"
        case order
        case parentID = "parent_id"
    }
}

struct APICheckResult: Decodable {
    let timestamp: Date
    let success: Bool
    let latencyNanos: Int64
    let message: String

    enum CodingKeys: String, CodingKey {
        case timestamp
        case success
        case latencyNanos = "latency"
        case message
    }
}

// Single-monitor response from /api/monitors/{id}. Uses the *converted*
// shape (durations in seconds / milliseconds, all snake_case).
struct APIMonitorDetail: Decodable {
    let config: APIMonitorDetailConfig
    let status: String
    let lastChecked: Date
    let lastLatencyMs: Int64
    let lastMessage: String
    let lastChange: Date

    enum CodingKeys: String, CodingKey {
        case config
        case status
        case lastChecked = "last_checked"
        case lastLatencyMs = "last_latency"
        case lastMessage = "last_message"
        case lastChange = "last_change"
    }
}

struct APIGroup: Decodable, Hashable {
    let id: Int
    let name: String
    let type: String?
    let order: Int?
}

struct APIMonitorDetailConfig: Decodable {
    let id: String
    let name: String
    let type: String
    let target: String
    let intervalSeconds: Int
    let timeoutSeconds: Int
    let enabled: Bool
    let group: String?
    let groupID: Int?
    let order: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case target
        case intervalSeconds = "interval_seconds"
        case timeoutSeconds = "timeout_seconds"
        case enabled
        case group
        case groupID = "group_id"
        case order
    }
}

// MARK: - Errors

enum UpturtleClientError: LocalizedError {
    case missingServerURL
    case invalidServerURL(String)
    case httpStatus(Int, String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .missingServerURL: "Server URL not configured."
        case .invalidServerURL(let s): "Invalid server URL: \(s)"
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty { "HTTP \(code): \(message)" }
            else { "HTTP \(code)" }
        case .decoding(let err): "Could not parse server response: \(err.localizedDescription)"
        case .transport(let err): err.localizedDescription
        }
    }
}

// MARK: - Client

actor UpturtleClient {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    static func make(serverURL: String, apiKey: String) throws -> UpturtleClient {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw UpturtleClientError.missingServerURL }
        guard let url = URL(string: trimmed) else {
            throw UpturtleClientError.invalidServerURL(trimmed)
        }
        return UpturtleClient(baseURL: url, apiKey: apiKey)
    }

    func fetchMonitors() async throws -> [APISnapshot] {
        try await getJSON(path: "api/monitors", type: [APISnapshot].self)
    }

    func fetchMonitor(id: String) async throws -> APIMonitorDetail {
        try await getJSON(path: "api/monitors/\(id)", type: APIMonitorDetail.self)
    }

    func fetchGroups() async throws -> [APIGroup] {
        try await getJSON(path: "api/groups", type: [APIGroup].self)
    }

    private func getJSON<T: Decodable>(path: String, type: T.Type) async throws -> T {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpturtleClientError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = UpturtleAPIDecoding.parseErrorMessage(data: data)
            throw UpturtleClientError.httpStatus(http.statusCode, message)
        }

        do {
            return try UpturtleAPIDecoding.decoder.decode(T.self, from: data)
        } catch {
            throw UpturtleClientError.decoding(error)
        }
    }
}

enum UpturtleAPIDecoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: raw) { return date }
            if let date = plainFormatter.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date: \(raw)"
            )
        }
        return d
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseErrorMessage(data: Data) -> String? {
        struct ErrorEnvelope: Decodable { let error: String? }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error
    }
}
