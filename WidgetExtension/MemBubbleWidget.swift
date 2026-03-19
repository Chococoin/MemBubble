import WidgetKit
import SwiftUI

// MARK: - Shared Constants (duplicated from main app to avoid cross-target deps)

private let suiteName = "group.com.chocos.MemBubble"

struct WidgetData {
    var pressure: Double = 0
    var cpuUsage: Double = 0
    var usedMemory: UInt64 = 0
    var totalMemory: UInt64 = 0
    var lastUpdate: Date = .distantPast
    var thresholdYellow: Double = 50
    var thresholdOrange: Double = 70
    var thresholdRed: Double = 85

    var pressureColor: Color {
        if pressure < thresholdYellow { return .green }
        if pressure < thresholdOrange { return .yellow }
        if pressure < thresholdRed { return .orange }
        return .red
    }

    var levelLabel: String {
        if pressure < thresholdYellow { return "Normal" }
        if pressure < thresholdOrange { return "Elevated" }
        if pressure < thresholdRed { return "High" }
        return "Critical"
    }

    static func read() -> WidgetData {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return WidgetData()
        }
        var data = WidgetData()
        data.pressure = defaults.double(forKey: "shared_pressure")
        data.cpuUsage = defaults.double(forKey: "shared_cpuUsage")

        let usedRaw = defaults.object(forKey: "shared_usedMemory") as? Int64 ?? 0
        data.usedMemory = UInt64(bitPattern: usedRaw)

        let totalRaw = defaults.object(forKey: "shared_totalMemory") as? Int64 ?? 0
        data.totalMemory = UInt64(bitPattern: totalRaw)

        let ts = defaults.double(forKey: "shared_lastUpdate")
        data.lastUpdate = ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast

        data.thresholdYellow = defaults.object(forKey: "shared_thresholdYellow") as? Double ?? 50
        data.thresholdOrange = defaults.object(forKey: "shared_thresholdOrange") as? Double ?? 70
        data.thresholdRed = defaults.object(forKey: "shared_thresholdRed") as? Double ?? 85

        return data
    }
}

// MARK: - Format Helpers

private func formatBytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1.0 {
        return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_048_576
    return String(format: "%.0f MB", mb)
}

// MARK: - Timeline Entry

struct MemBubbleEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - Timeline Provider

struct MemBubbleProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemBubbleEntry {
        MemBubbleEntry(date: .now, data: WidgetData())
    }

    func getSnapshot(in context: Context, completion: @escaping (MemBubbleEntry) -> Void) {
        let entry = MemBubbleEntry(date: .now, data: WidgetData.read())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemBubbleEntry>) -> Void) {
        let data = WidgetData.read()
        let entry = MemBubbleEntry(date: .now, data: data)
        // Refresh every 5 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct MemBubbleWidgetSmallView: View {
    let entry: MemBubbleEntry

    var body: some View {
        let data = entry.data

        VStack(spacing: 6) {
            // Pressure gauge ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    .frame(width: 60, height: 60)

                Circle()
                    .trim(from: 0, to: data.pressure / 100)
                    .stroke(data.pressureColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text(String(format: "%.0f%%", data.pressure))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(data.pressureColor)
                    Text("MEM")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Text(data.levelLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .containerBackground(for: .widget) {
            Color(.windowBackgroundColor)
        }
    }
}

struct MemBubbleWidgetMediumView: View {
    let entry: MemBubbleEntry

    var body: some View {
        let data = entry.data

        HStack(spacing: 16) {
            // Left: pressure gauge
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    .frame(width: 56, height: 56)

                Circle()
                    .trim(from: 0, to: data.pressure / 100)
                    .stroke(data.pressureColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text(String(format: "%.0f%%", data.pressure))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(data.pressureColor)
                    Text("MEM")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            // Right: stats
            VStack(alignment: .leading, spacing: 4) {
                Text("MemBubble")
                    .font(.system(size: 12, weight: .bold, design: .rounded))

                Text(data.levelLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(data.pressureColor)

                Divider()

                if data.totalMemory > 0 {
                    HStack {
                        Text("RAM:")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(formatBytes(data.usedMemory)) / \(formatBytes(data.totalMemory))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                }

                if data.cpuUsage > 0 {
                    HStack {
                        Text("CPU:")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", data.cpuUsage))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                }

                Text(data.lastUpdate, style: .relative)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .containerBackground(for: .widget) {
            Color(.windowBackgroundColor)
        }
    }
}

// MARK: - Widget Definition

@main
struct MemBubbleWidget: Widget {
    let kind = "com.chocos.MemBubble.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemBubbleProvider()) { entry in
            if #available(macOS 14.0, *) {
                MemBubbleWidgetEntryView(entry: entry)
            } else {
                MemBubbleWidgetEntryView(entry: entry)
                    .padding()
            }
        }
        .configurationDisplayName("MemBubble")
        .description("Memory pressure at a glance")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MemBubbleWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MemBubbleEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MemBubbleWidgetMediumView(entry: entry)
        default:
            MemBubbleWidgetSmallView(entry: entry)
        }
    }
}
