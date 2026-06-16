import SwiftUI

struct MonitorRowView: View {
    let monitor: Monitor
    var isExpanded: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            rowContent
                .contentShape(Rectangle())
                .onTapGesture { onToggle?() }

            if isExpanded {
                Divider().padding(.leading, 36)
                MonitorChartView(monitor: monitor)
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(monitor.name)
                        .font(.system(size: 15, weight: .semibold))
                    StatusBadge(status: monitor.status)
                }
                targetLine
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                HistoryBars(history: monitor.history)
                HStack(spacing: 6) {
                    Text(uptimeString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text(lastCheckedString)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var targetLine: some View {
        if monitor.kind == .http, let url = URL(string: monitor.url), url.scheme?.hasPrefix("http") == true {
            HStack(spacing: 4) {
                Text("\(monitor.kind.rawValue) ·")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Link(monitor.url, destination: url)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text("\(monitor.kind.rawValue) · \(monitor.url)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusColor: Color {
        switch monitor.status {
        case .up: .green
        case .down: .red
        case .disabled: .secondary
        }
    }

    private var uptimeString: String {
        String(format: "%.1f%%", monitor.uptime * 100)
    }

    private var lastCheckedString: String {
        guard let lastChecked = monitor.lastChecked else { return "—" }
        let seconds = Int(Date().timeIntervalSince(lastChecked))
        if seconds < 60 { return "\(max(seconds, 1))s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}

struct StatusBadge: View {
    let status: MonitorStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch status {
        case .up: Color.green.opacity(0.18)
        case .down: Color.red.opacity(0.2)
        case .disabled: Color.secondary.opacity(0.18)
        }
    }

    private var foreground: Color {
        switch status {
        case .up: .green
        case .down: .red
        case .disabled: .secondary
        }
    }
}

struct HistoryBars: View {
    let history: [HistoryEntry]
    @State private var hoveredIndex: Int?

    private static let maxBars = 20
    private static let barWidth: CGFloat = 9
    private static let barHeight: CGFloat = 22
    private static let barSpacing: CGFloat = 3

    private var trimmed: [HistoryEntry] {
        history.suffix(Self.maxBars).map { $0 }
    }

    var body: some View {
        HStack(spacing: Self.barSpacing) {
            ForEach(Array(trimmed.enumerated()), id: \.offset) { idx, entry in
                HistoryBar(
                    status: entry.status,
                    isHovered: hoveredIndex == idx
                )
                .frame(width: Self.barWidth, height: Self.barHeight)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    withAnimation(.easeOut(duration: 0.10)) {
                        hoveredIndex = isHovering ? idx : nil
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let hoveredIndex, hoveredIndex < trimmed.count {
                HistoryHoverTooltip(entry: trimmed[hoveredIndex])
                    .fixedSize()
                    .offset(y: -(Self.barHeight + 14))
                    .transition(.opacity.combined(with: .offset(y: 4)))
                    .allowsHitTesting(false)
                    .zIndex(1)
            }
        }
    }
}

private struct HistoryBar: View {
    let status: MonitorStatus
    let isHovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .brightness(isHovered ? 0.08 : 0)
            .scaleEffect(isHovered ? 1.12 : 1.0, anchor: .center)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var color: Color {
        switch status {
        case .up: .green
        case .down: .red
        case .disabled: .secondary.opacity(0.4)
        }
    }
}

private struct HistoryHoverTooltip: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(timeString)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            Text("·")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text(statusLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
    }

    private var timeString: String {
        entry.timestamp.formatted(date: .numeric, time: .standard)
    }

    private var statusLabel: String {
        switch entry.status {
        case .up: "OK"
        case .down: "Down"
        case .disabled: "Disabled"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .up: .green
        case .down: .red
        case .disabled: .secondary
        }
    }
}
