import Cocoa
import SwiftUI

// MARK: - Preview App (standalone bubble tester with real SwiftUI rendering)

struct PreviewContentView: View {
    @State private var pressure: Double = 10
    @State private var activity: Double = 0
    @State private var cpu: Double = 5

    var memInfo: MemoryInfo {
        var info = MemoryInfo()
        info.pressure = pressure
        info.total = 16 * 1_073_741_824
        info.used = UInt64(Double(info.total) * 0.9)
        info.free = info.total - info.used
        info.active = UInt64(Double(info.total) * 0.3)
        info.inactive = UInt64(Double(info.total) * 0.25)
        info.wired = UInt64(Double(info.total) * 0.12)
        info.compressed = UInt64(Double(info.total) * 0.15)
        return info
    }

    var cpuInfo: CPUInfo {
        CPUInfo(userLoad: cpu * 0.7, systemLoad: cpu * 0.3, idleLoad: 100 - cpu, totalUsage: cpu)
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Bubble Preview")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text("Real SwiftUI rendering — identical to the app")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Bubbles at real size
            HStack(spacing: 12) {
                BubbleView(info: memInfo)
                ActivityBubbleView(activity: activity)
                CPUBubbleView(info: cpuInfo)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
            )

            // Scaled up bubbles (3x) for detail inspection
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    BubbleView(info: memInfo)
                        .scaleEffect(3)
                        .frame(width: 84, height: 84)
                    Text("Pressure")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    ActivityBubbleView(activity: activity)
                        .scaleEffect(3)
                        .frame(width: 84, height: 84)
                    Text("Activity")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    CPUBubbleView(info: cpuInfo)
                        .scaleEffect(3)
                        .frame(width: 84, height: 84)
                    Text("CPU")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
            )

            Divider()

            // Sliders
            VStack(spacing: 16) {
                sliderRow("Pressure", value: $pressure, color: pressureColor(for: pressure))
                sliderRow("Activity", value: $activity, color: activitySliderColor)
                sliderRow("CPU", value: $cpu, color: cpuSliderColor)
            }
            .padding(.horizontal, 20)
        }
        .padding(24)
        .frame(width: 400)
    }

    var activitySliderColor: Color {
        if activity < 30 { return .mint }
        if activity < 55 { return .teal }
        if activity < 80 { return .indigo }
        return .pink
    }

    var cpuSliderColor: Color {
        if cpu < 40 { return .cyan }
        if cpu < 65 { return .blue }
        if cpu < 85 { return .purple }
        return .red
    }

    func sliderRow(_ label: String, value: Binding<Double>, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(width: 70, alignment: .leading)
                Slider(value: value, in: 0...100, step: 1)
                    .tint(color)
                Text(String(format: "%.0f%%", value.wrappedValue))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

// MARK: - App Delegate

class PreviewDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 580),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MemBubble — Bubble Preview"
        window.contentView = NSHostingView(rootView: PreviewContentView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Entry Point

let previewApp = NSApplication.shared
NSApp.setActivationPolicy(.regular)
let previewDelegate = PreviewDelegate()
previewApp.delegate = previewDelegate
previewApp.run()
