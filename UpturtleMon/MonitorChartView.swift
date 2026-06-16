import SwiftUI
import Charts

struct MonitorChartView: View {
    let monitor: Monitor
    @State private var hoveredEntry: HistoryEntry?
    @State private var hoveredX: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Response time", systemImage: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                stats
            }

            chart
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.18))
        )
    }

    private var stats: some View {
        HStack(spacing: 12) {
            statText("Avg", value: avgLatency)
            statText("Min", value: minLatency)
            statText("Max", value: maxLatency)
        }
    }

    @ViewBuilder
    private func statText(_ label: String, value: Double?) -> some View {
        if let value {
            HStack(spacing: 3) {
                Text("\(label):")
                    .foregroundStyle(.tertiary)
                Text("\(Int(value.rounded()))ms")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var chart: some View {
        if entries.isEmpty {
            Text("No data yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else {
            Chart {
                ForEach(entries, id: \.timestamp) { entry in
                    AreaMark(
                        x: .value("Time", entry.timestamp),
                        y: .value("Latency", entry.latencyMs)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.35), .blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Time", entry.timestamp),
                        y: .value("Latency", entry.latencyMs)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))

                    if entry.status == .down {
                        PointMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Latency", entry.latencyMs)
                        )
                        .foregroundStyle(.red)
                        .symbol(.circle)
                        .symbolSize(40)
                    }
                }

                if let hoveredEntry {
                    RuleMark(x: .value("Time", hoveredEntry.timestamp))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))

                    PointMark(
                        x: .value("Time", hoveredEntry.timestamp),
                        y: .value("Latency", hoveredEntry.latencyMs)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(90)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisTick().foregroundStyle(Color.primary.opacity(0.2))
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisTick().foregroundStyle(Color.primary.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v.rounded()))ms")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plotFrame = geo[proxy.plotAreaFrame]
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let xInPlot = location.x - plotFrame.minX
                                    guard xInPlot >= 0, xInPlot <= plotFrame.width else {
                                        hoveredEntry = nil
                                        return
                                    }
                                    if let date: Date = proxy.value(atX: xInPlot),
                                       let entry = nearestEntry(to: date) {
                                        hoveredEntry = entry
                                        hoveredX = location.x
                                    }
                                case .ended:
                                    hoveredEntry = nil
                                }
                            }

                        if let hoveredEntry {
                            ChartHoverTooltip(entry: hoveredEntry)
                                .fixedSize()
                                .background(TooltipWidthReporter())
                                .modifier(
                                    TooltipPositionModifier(
                                        hoveredX: hoveredX,
                                        containerWidth: geo.size.width
                                    )
                                )
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .frame(height: 150)
        }
    }

    private var entries: [HistoryEntry] {
        monitor.history.filter { $0.latencyMs > 0 || $0.status != .disabled }
    }

    private var latencies: [Double] {
        entries.map(\.latencyMs).filter { $0 > 0 }
    }

    private var avgLatency: Double? {
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    private var minLatency: Double? { latencies.min() }
    private var maxLatency: Double? { latencies.max() }

    private func nearestEntry(to date: Date) -> HistoryEntry? {
        entries.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }
}

// MARK: - Tooltip

private struct ChartHoverTooltip: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(timeString)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 9, height: 9)
                    .cornerRadius(1)
                Text("Response: \(latencyString)")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 6) {
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                    .cornerRadius(1)
                Text("Status: \(statusLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    private var timeString: String {
        entry.timestamp.formatted(date: .omitted, time: .shortened)
    }

    private var latencyString: String {
        String(format: "%.2f ms", entry.latencyMs)
    }

    private var statusLabel: String {
        switch entry.status {
        case .up: "Up"
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

// Reads the tooltip's measured width so we can clamp it inside the chart.
private struct TooltipWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TooltipWidthReporter: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: TooltipWidthKey.self, value: geo.size.width)
        }
    }
}

private struct TooltipPositionModifier: ViewModifier {
    let hoveredX: CGFloat
    let containerWidth: CGFloat
    @State private var width: CGFloat = 160

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(TooltipWidthKey.self) { width = $0 }
            .offset(x: clampedX, y: 8)
    }

    private var clampedX: CGFloat {
        let proposed = hoveredX - width / 2
        let maxX = containerWidth - width - 8
        return min(max(8, proposed), max(8, maxX))
    }
}
