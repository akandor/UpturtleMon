import SwiftUI

struct ContentView: View {
    @Environment(MonitorStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage("serverURL") private var serverURL: String = ""
    @AppStorage("apiToken") private var apiToken: String = ""
    @State private var expandedMonitorID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            body(for: store)
            Divider()
            footer
        }
        .frame(width: 560)
        .onChange(of: serverURL) { _, _ in Task { await store.refresh() } }
        .onChange(of: apiToken) { _, _ in Task { await store.refresh() } }
    }

    @ViewBuilder
    private func body(for store: MonitorStore) -> some View {
        if serverURL.trimmingCharacters(in: .whitespaces).isEmpty {
            placeholder(
                icon: "wifi.exclamationmark",
                title: "No server configured",
                detail: "Enter your Upturtle server URL in Settings."
            )
        } else if let error = store.lastError, store.groups.isEmpty {
            placeholder(
                icon: "exclamationmark.triangle",
                title: "Couldn't reach server",
                detail: error
            )
        } else if store.groups.isEmpty && store.isLoading {
            placeholder(
                icon: "arrow.clockwise",
                title: "Loading…",
                detail: nil
            )
        } else if store.groups.isEmpty {
            placeholder(
                icon: "magnifyingglass",
                title: "No monitors yet",
                detail: "Add monitors on your Upturtle server."
            )
        } else if store.visibleGroups.isEmpty {
            placeholder(
                icon: "eye.slash",
                title: "No monitors selected",
                detail: "Activate monitors in Settings → Monitors."
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(store.visibleGroups) { group in
                    groupSection(group)
                }
            }
            .padding(.vertical, 10)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("UpturtleMon")
                .font(.system(size: 15, weight: .semibold))
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Refresh now")

            Button {
                showSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Quit UpturtleMon")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func groupSection(_ group: MonitorGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.name.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 2)

            VStack(spacing: 0) {
                ForEach(Array(group.monitors.enumerated()), id: \.element.id) { index, monitor in
                    MonitorRowView(
                        monitor: monitor,
                        isExpanded: expandedMonitorID == monitor.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            expandedMonitorID = expandedMonitorID == monitor.id ? nil : monitor.id
                        }
                    }
                    if index < group.monitors.count - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 12)
        }
    }

    private var footer: some View {
        HStack {
            footerLeading
            Spacer()
            if let lastError = store.lastError, !store.groups.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(lastError)
            }
            if let lastRefreshed = store.lastRefreshed {
                Text("Updated \(relative(lastRefreshed))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var footerLeading: some View {
        let visible = store.visibleGroups.reduce(0) { $0 + $1.monitors.count }
        let total = store.allMonitors.count
        if visible == total {
            Text("\(total) monitor\(total == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            Text("\(visible) of \(total) monitors")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func placeholder(icon: String, title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 32)
    }

    private func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.settings)
        DispatchQueue.main.async {
            for window in NSApp.windows where window.identifier?.rawValue.hasPrefix(WindowID.settings) == true {
                window.orderFrontRegardless()
                window.makeKey()
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    ContentView()
        .environment(MonitorStore())
}
