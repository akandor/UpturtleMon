import Foundation

enum MonitorStatus: String {
    case up
    case down
    case disabled

    var label: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .disabled: "Disabled"
        }
    }
}

enum MonitorKind: String {
    case http = "HTTP"
    case icmp = "ICMP"
    case docker = "Docker"

    static func from(rawType: String) -> MonitorKind {
        switch rawType.lowercased() {
        case "http", "https": .http
        case "icmp": .icmp
        case "docker": .docker
        default: .http
        }
    }
}

struct HistoryEntry: Hashable {
    var timestamp: Date
    var status: MonitorStatus
    var latencyMs: Double
}

struct Monitor: Identifiable, Hashable {
    var id: String
    var name: String
    var kind: MonitorKind
    var url: String
    var status: MonitorStatus
    var lastChecked: Date?
    var history: [HistoryEntry]
    var uptime: Double
    var group: String
}

struct MonitorGroup: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var monitors: [Monitor]
}

enum SampleData {
    static let now = Date()

    private static func sampleHistory(_ statuses: [MonitorStatus], step: TimeInterval = 60) -> [HistoryEntry] {
        let base = now
        return statuses.enumerated().map { offset, status in
            HistoryEntry(
                timestamp: base.addingTimeInterval(-step * Double(statuses.count - offset)),
                status: status,
                latencyMs: Double.random(in: 65...140)
            )
        }
    }

    static let groups: [MonitorGroup] = [
        MonitorGroup(name: "Webserver", monitors: [
            Monitor(
                id: "sample-kenvb",
                name: "KenVB",
                kind: .http,
                url: "https://kendoverband-berlin.de",
                status: .up,
                lastChecked: now.addingTimeInterval(-50),
                history: sampleHistory(Array(repeating: .up, count: 20)),
                uptime: 1.0,
                group: "Webserver"
            ),
            Monitor(
                id: "sample-tkkn",
                name: "TKKN",
                kind: .http,
                url: "https://tekkeikan.de",
                status: .up,
                lastChecked: now.addingTimeInterval(-50),
                history: sampleHistory(
                    [.up, .up, .down, .up, .up, .up, .up, .up, .up, .up,
                     .up, .up, .up, .up, .up, .up, .up, .up, .up, .up]
                ),
                uptime: 0.95,
                group: "Webserver"
            ),
            Monitor(
                id: "sample-eduviyo",
                name: "Eduviyo",
                kind: .http,
                url: "https://api.eduviyo.com",
                status: .up,
                lastChecked: now.addingTimeInterval(-1),
                history: sampleHistory(Array(repeating: .up, count: 20)),
                uptime: 1.0,
                group: "Webserver"
            )
        ]),
        MonitorGroup(name: "Ungrouped", monitors: [
            Monitor(
                id: "sample-test",
                name: "Test",
                kind: .http,
                url: "https://bla.toepper.rocks",
                status: .disabled,
                lastChecked: nil,
                history: sampleHistory(Array(repeating: .down, count: 20)),
                uptime: 0.0,
                group: "Ungrouped"
            )
        ])
    ]
}
