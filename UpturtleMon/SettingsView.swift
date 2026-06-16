import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @State private var tab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch tab {
                case .general: GeneralSettingsView()
                case .monitors: MonitorsSettingsView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 520)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases) { item in
                SettingsTabButton(
                    tab: item,
                    isSelected: tab == item
                ) { tab = item }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, monitors, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .monitors: "Monitors"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .monitors: "dot.radiowaves.left.and.right"
        case .about: "info.circle"
        }
    }
}

struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18))
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(width: 72, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("serverURL") private var serverURL: String = ""
    @AppStorage("apiToken") private var apiToken: String = ""
    @AppStorage("language") private var language: AppLanguage = .system

    var body: some View {
        Form {
            Section("Server") {
                TextField(
                    "Server URL",
                    text: $serverURL,
                    prompt: Text("https://uptime.example.com")
                )
                .textContentType(.URL)
                .autocorrectionDisabled()

                SecureField(
                    "API Token",
                    text: $apiToken,
                    prompt: Text("Paste your API token")
                )
            }

            Section("Appearance") {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section("Startup") {
                StartOnLoginToggle()
            }
        }
        .formStyle(.grouped)
    }
}

struct StartOnLoginToggle: View {
    @State private var enabled: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Start on Login", isOn: $enabled)
            .onChange(of: enabled) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case de
    case es
    case fr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System Default"
        case .en: "English"
        case .de: "Deutsch"
        case .es: "Español"
        case .fr: "Français"
        }
    }
}

// MARK: - Monitors

struct MonitorsSettingsView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        Group {
            if store.allMonitors.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 14) {
                    MonitorListCard(title: "Available Monitors") {
                        ForEach(availableMonitors) { monitor in
                            MonitorAvailableRow(monitor: monitor) {
                                store.setSelected(monitor.id, isSelected: true)
                            }
                            if monitor.id != availableMonitors.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }

                    MonitorListCard(title: "Selected Monitors") {
                        if selectedMonitors.isEmpty {
                            Text("No monitors selected.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(selectedMonitors) { monitor in
                                MonitorSelectedRow(monitor: monitor) {
                                    store.setSelected(monitor.id, isSelected: false)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var availableMonitors: [Monitor] {
        store.allMonitors.filter { !store.selectedMonitorIDs.contains($0.id) }
    }

    private var selectedMonitors: [Monitor] {
        store.allMonitors.filter { store.selectedMonitorIDs.contains($0.id) }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No monitors loaded")
                .font(.system(size: 14, weight: .semibold))
            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                Text("Configure the server URL and API token in the General tab.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            Button("Refresh") {
                Task { await store.refresh() }
            }
            .controlSize(.small)
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Card wrapper shared by both monitor lists.
struct MonitorListCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 0) {
                    content
                }
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct MonitorAvailableRow: View {
    let monitor: Monitor
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(monitor.name)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
            GroupChip(text: monitor.group)
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Activate in popup")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct MonitorSelectedRow: View {
    let monitor: Monitor
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(monitor.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
            Spacer(minLength: 8)
            GroupChip(text: monitor.group)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Hide from popup")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.green.opacity(0.4), lineWidth: 1)
        )
    }
}

struct GroupChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.18))
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
    }
}

// MARK: - About

struct AboutView: View {
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (Build \(build))"
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        VStack(spacing: 12) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)

            Text("UpturtleMon")
                .font(.system(size: 22, weight: .semibold))

            Text(versionString)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("A lightweight menu bar companion for the Upturtle monitor server")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            VStack(spacing: 6) {
                AboutLink(
                    title: "UpturtleMon on GitHub",
                    url: URL(string: "https://github.com/akandor/UpturtleMon")!,
                    icon: .github
                )
                AboutLink(
                    title: "Report an issue",
                    url: URL(string: "https://github.com/akandor/UpturtleMon/issues")!,
                    icon: .system("exclamationmark.bubble")
                )
                AboutLink(
                    title: "Upturtle on GitHub",
                    url: URL(string: "https://github.com/Z3nto/upturtle")!,
                    icon: .github
                )
            }
            .padding(.top, 4)

            Spacer(minLength: 8)

            VStack(spacing: 4) {
                (Text("Powered by ") +
                 Text("Upturtle").font(.system(size: 11, weight: .semibold)) +
                 Text(" by Z3nto · Upturtle is MIT licensed."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 4) {
                    Text(verbatim: "© \(currentYear)")
                        .foregroundStyle(.tertiary)
                    Link("Toepper.Rocks", destination: URL(string: "https://toepper.rocks")!)
                        .foregroundStyle(Color.accentColor)
                }
                .font(.system(size: 11))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 540)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AboutLink: View {
    enum IconKind {
        case github
        case system(String)
    }

    let title: String
    let url: URL
    let icon: IconKind

    var body: some View {
        Link(destination: url) {
            Label {
                Text(title)
                    .fixedSize()
            } icon: {
                switch icon {
                case .github:
                    Image("github-mark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                case .system(let name):
                    Image(systemName: name)
                        .font(.system(size: 12))
                }
            }
            .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
}
