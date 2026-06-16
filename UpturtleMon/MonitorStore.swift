import Foundation
import Observation

@MainActor
@Observable
final class MonitorStore {
    var groups: [MonitorGroup] = []
    var lastRefreshed: Date?
    var lastError: String?
    var isLoading: Bool = false

    var selectedMonitorIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(selectedMonitorIDs),
                forKey: Self.selectionKey
            )
        }
    }

    private var bulkRefreshTask: Task<Void, Never>?
    private var perMonitorTasks: [String: Task<Void, Never>] = [:]
    private var monitorIntervals: [String: TimeInterval] = [:]

    private let historyWindow = 20
    private let bulkReconcileInterval: TimeInterval = 300 // 5 min
    private let minimumPollInterval: TimeInterval = 5

    private static let selectionKey = "selectedMonitorIDs"
    private static let initializedKey = "monitorSelectionInitialized"

    init() {
        let ids = UserDefaults.standard.stringArray(forKey: Self.selectionKey) ?? []
        self.selectedMonitorIDs = Set(ids)
    }

    var allMonitors: [Monitor] {
        groups.flatMap { $0.monitors }
    }

    var visibleGroups: [MonitorGroup] {
        groups.compactMap { group in
            let filtered = group.monitors.filter { selectedMonitorIDs.contains($0.id) }
            guard !filtered.isEmpty else { return nil }
            return MonitorGroup(name: group.name, monitors: filtered)
        }
    }

    func setSelected(_ id: String, isSelected: Bool) {
        if isSelected {
            selectedMonitorIDs.insert(id)
        } else {
            selectedMonitorIDs.remove(id)
        }
    }

    // MARK: Lifecycle

    func start() {
        guard bulkRefreshTask == nil else { return }
        bulkRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.bulkReconcileInterval))
                await self.refresh()
            }
        }
    }

    func stop() {
        bulkRefreshTask?.cancel()
        bulkRefreshTask = nil
        for task in perMonitorTasks.values { task.cancel() }
        perMonitorTasks.removeAll()
        monitorIntervals.removeAll()
    }

    // MARK: Bulk refresh (reconciliation)

    func refresh() async {
        let defaults = UserDefaults.standard
        let serverURL = defaults.string(forKey: "serverURL") ?? ""
        let apiKey = defaults.string(forKey: "apiToken") ?? ""

        guard !serverURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            groups = []
            lastError = nil
            cancelAllPerMonitorTasks()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let client = try UpturtleClient.make(serverURL: serverURL, apiKey: apiKey)
            async let snapshotsTask = client.fetchMonitors()
            async let serverGroupsTask = try? await client.fetchGroups()

            let snapshots = try await snapshotsTask
            let serverGroups = await serverGroupsTask ?? []

            groups = Self.group(
                snapshots,
                serverGroups: serverGroups,
                historyWindow: historyWindow
            )
            initializeSelectionIfNeeded(snapshots: snapshots)
            reconcilePerMonitorTasks(snapshots: snapshots)
            lastError = nil
            lastRefreshed = Date()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func initializeSelectionIfNeeded(snapshots: [APISnapshot]) {
        guard !UserDefaults.standard.bool(forKey: Self.initializedKey) else { return }
        selectedMonitorIDs = Set(snapshots.map { $0.config.id })
        UserDefaults.standard.set(true, forKey: Self.initializedKey)
    }

    // MARK: Per-monitor polling

    private func reconcilePerMonitorTasks(snapshots: [APISnapshot]) {
        let currentIDs = Set(snapshots.map { $0.config.id })

        // Cancel tasks for monitors that no longer exist on the server.
        for (id, task) in perMonitorTasks where !currentIDs.contains(id) {
            task.cancel()
            perMonitorTasks.removeValue(forKey: id)
            monitorIntervals.removeValue(forKey: id)
        }

        // Schedule or re-schedule per-monitor pollers.
        for snap in snapshots {
            let id = snap.config.id
            let newInterval = Self.computeInterval(
                nanos: snap.config.intervalNanos,
                floor: minimumPollInterval
            )

            let hasTask = perMonitorTasks[id] != nil
            let intervalChanged = monitorIntervals[id] != newInterval
            if !hasTask || intervalChanged {
                perMonitorTasks[id]?.cancel()
                monitorIntervals[id] = newInterval
                perMonitorTasks[id] = launchPollTask(id: id, interval: newInterval)
            }
        }
    }

    private func cancelAllPerMonitorTasks() {
        for task in perMonitorTasks.values { task.cancel() }
        perMonitorTasks.removeAll()
        monitorIntervals.removeAll()
    }

    private func launchPollTask(id: String, interval: TimeInterval) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.refreshMonitor(id: id)
            }
        }
    }

    private func refreshMonitor(id: String) async {
        let defaults = UserDefaults.standard
        let serverURL = defaults.string(forKey: "serverURL") ?? ""
        let apiKey = defaults.string(forKey: "apiToken") ?? ""
        guard !serverURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        do {
            let client = try UpturtleClient.make(serverURL: serverURL, apiKey: apiKey)
            let detail = try await client.fetchMonitor(id: id)
            apply(detail)
        } catch {
            // Per-monitor failures stay quiet; the bulk refresh surfaces errors.
        }
    }

    private func apply(_ detail: APIMonitorDetail) {
        let id = detail.config.id
        for groupIdx in groups.indices {
            guard let monitorIdx = groups[groupIdx].monitors.firstIndex(where: { $0.id == id }) else {
                continue
            }
            var monitor = groups[groupIdx].monitors[monitorIdx]

            let newStatus = Self.parseStatus(detail.status, enabled: detail.config.enabled)
            let newCheck = detail.lastChecked
            let previousCheck = monitor.lastChecked

            // Only append a history bar when the server actually ran a new check.
            if previousCheck == nil || newCheck > previousCheck! {
                let barStatus: MonitorStatus = detail.config.enabled
                    ? (detail.status.lowercased() == "up" ? .up : .down)
                    : .disabled
                monitor.history.append(HistoryEntry(
                    timestamp: newCheck,
                    status: barStatus,
                    latencyMs: Double(detail.lastLatencyMs)
                ))
                if monitor.history.count > historyWindow {
                    monitor.history.removeFirst(monitor.history.count - historyWindow)
                }
                let ups = monitor.history.filter { $0.status == .up }.count
                monitor.uptime = monitor.history.isEmpty
                    ? 0
                    : Double(ups) / Double(monitor.history.count)
            }

            monitor.status = newStatus
            monitor.lastChecked = newCheck
            groups[groupIdx].monitors[monitorIdx] = monitor
            return
        }
    }

    // MARK: Transform

    private static func computeInterval(nanos: Int64, floor: TimeInterval) -> TimeInterval {
        let seconds = Double(nanos) / 1_000_000_000
        guard seconds.isFinite, seconds > 0 else { return 60 }
        return max(floor, seconds)
    }

    private static func group(
        _ snapshots: [APISnapshot],
        serverGroups: [APIGroup],
        historyWindow: Int
    ) -> [MonitorGroup] {
        // /api/monitors doesn't populate config.group (the name); we have to
        // resolve it from group_id against the /api/groups response.
        let nameByID: [Int: String] = Dictionary(
            uniqueKeysWithValues: serverGroups.map { ($0.id, $0.name) }
        )

        func resolveGroupName(for snap: APISnapshot) -> String {
            let embedded = (snap.config.group ?? "").trimmingCharacters(in: .whitespaces)
            if !embedded.isEmpty { return embedded }
            if let gid = snap.config.groupID,
               gid > 0,
               let resolved = nameByID[gid] {
                return resolved
            }
            return "Ungrouped"
        }

        let buckets = Dictionary(grouping: snapshots, by: resolveGroupName)

        // Map group name -> server-defined sort key. Groups missing from the
        // server list (e.g. "Ungrouped") fall through to alphabetical.
        let orderByName: [String: Int] = Dictionary(
            uniqueKeysWithValues: serverGroups.enumerated().map { idx, group in
                (group.name, group.order ?? idx)
            }
        )

        return buckets
            .map { (groupName, snaps) in
                let sorted = snaps.sorted { ($0.config.order ?? 0) < ($1.config.order ?? 0) }
                return MonitorGroup(
                    name: groupName,
                    monitors: sorted.map {
                        mapMonitor(
                            $0,
                            resolvedGroup: groupName,
                            historyWindow: historyWindow
                        )
                    }
                )
            }
            .sorted { lhs, rhs in
                if lhs.name == "Ungrouped" { return false }
                if rhs.name == "Ungrouped" { return true }

                switch (orderByName[lhs.name], orderByName[rhs.name]) {
                case let (l?, r?) where l != r:
                    return l < r
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
    }

    private static func mapMonitor(
        _ snap: APISnapshot,
        resolvedGroup: String,
        historyWindow: Int
    ) -> Monitor {
        let trimmedHistory = snap.history.suffix(historyWindow)
        let history = trimmedHistory.map { result -> HistoryEntry in
            HistoryEntry(
                timestamp: result.timestamp,
                status: snap.config.enabled ? (result.success ? .up : .down) : .disabled,
                latencyMs: Double(result.latencyNanos) / 1_000_000.0
            )
        }

        let uptime: Double
        if trimmedHistory.isEmpty {
            uptime = snap.config.enabled ? (snap.status.lowercased() == "up" ? 1.0 : 0.0) : 0.0
        } else {
            let ups = trimmedHistory.filter(\.success).count
            uptime = Double(ups) / Double(trimmedHistory.count)
        }

        return Monitor(
            id: snap.config.id,
            name: snap.config.name,
            kind: MonitorKind.from(rawType: snap.config.type),
            url: snap.config.target,
            status: parseStatus(snap.status, enabled: snap.config.enabled),
            lastChecked: snap.lastChecked,
            history: Array(history),
            uptime: uptime,
            group: resolvedGroup
        )
    }

    private static func parseStatus(_ raw: String, enabled: Bool) -> MonitorStatus {
        guard enabled else { return .disabled }
        switch raw.lowercased() {
        case "up": return .up
        case "down": return .down
        default: return .down
        }
    }
}
