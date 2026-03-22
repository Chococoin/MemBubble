import Cocoa
import SwiftUI

// MARK: - Bubble Tuning Lab

struct PreviewContentView: View {
    // Simulated values
    @State private var pressure: Double = 45
    @State private var activity: Double = 30
    @State private var cpu: Double = 15

    // Glass bubble tuning parameters
    @State private var bubbleSize: Double = 27
    @State private var fillOpLow: Double = 0.12
    @State private var fillOpHigh: Double = 0.30
    @State private var specularOp: Double = 0.30
    @State private var pinpointOp: Double = 0.50
    @State private var rimOp: Double = 0.20
    @State private var rimWidth: Double = 1.0
    @State private var reflectionOp: Double = 0.05
    @State private var shadowOp: Double = 0.25
    @State private var shadowRadius: Double = 5.0
    @State private var materialOp: Double = 1.0

    // Background preview
    @State private var bgBrightness: Double = 0.15

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

    var tuningParams: GlassTuning {
        GlassTuning(
            size: CGFloat(bubbleSize),
            fillOpLow: fillOpLow,
            fillOpHigh: fillOpHigh,
            specularOp: specularOp,
            pinpointOp: pinpointOp,
            rimOp: rimOp,
            rimWidth: CGFloat(rimWidth),
            reflectionOp: reflectionOp,
            shadowOp: shadowOp,
            shadowRadius: CGFloat(shadowRadius),
            materialOp: materialOp
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Preview area
            VStack(spacing: 20) {
                Text("BUBBLE LAB")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                // Real size bubbles
                HStack(spacing: 8) {
                    TunableBubble(tintColor: pressureColor(for: pressure), fillRatio: max(0.15, pressure / 100), label: String(format: "%.0f%%", pressure), params: tuningParams)
                    TunableBubble(tintColor: activityColor, fillRatio: max(0.15, activity / 100), label: String(format: "%.0f%%", activity), params: tuningParams)
                    TunableBubble(tintColor: cpuColorFor(cpu), fillRatio: max(0.15, cpu / 100), label: String(format: "%.0f%%", cpu), params: tuningParams)
                }

                // 4x scaled for inspection
                HStack(spacing: 30) {
                    VStack(spacing: 6) {
                        TunableBubble(tintColor: pressureColor(for: pressure), fillRatio: max(0.15, pressure / 100), label: String(format: "%.0f%%", pressure), params: tuningParams)
                            .scaleEffect(4)
                            .frame(width: 110, height: 110)
                        Text("Memory")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    VStack(spacing: 6) {
                        TunableBubble(tintColor: activityColor, fillRatio: max(0.15, activity / 100), label: String(format: "%.0f%%", activity), params: tuningParams)
                            .scaleEffect(4)
                            .frame(width: 110, height: 110)
                        Text("Activity")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    VStack(spacing: 6) {
                        TunableBubble(tintColor: cpuColorFor(cpu), fillRatio: max(0.15, cpu / 100), label: String(format: "%.0f%%", cpu), params: tuningParams)
                            .scaleEffect(4)
                            .frame(width: 110, height: 110)
                        Text("CPU")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Divider().background(Color.white.opacity(0.2))

                // Value knobs
                HStack(spacing: 20) {
                    KnobView(label: "PRESSURE", color: pressureColor(for: pressure), value: Binding(get: { pressure / 100 }, set: { pressure = $0 * 100 }))
                    KnobView(label: "ACTIVITY", color: activityColor, value: Binding(get: { activity / 100 }, set: { activity = $0 * 100 }))
                    KnobView(label: "CPU", color: cpuColorFor(cpu), value: Binding(get: { cpu / 100 }, set: { cpu = $0 * 100 }))
                    KnobView(label: "BG", color: .gray, value: $bgBrightness)
                }
            }
            .padding(24)
            .frame(width: 420)
            .background(Color(white: bgBrightness))

            Divider().background(Color.white.opacity(0.2))

            // Right: Tuning sliders
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("GLASS TUNING")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(.white)

                    Group {
                        sectionHeader("Bubble")
                        paramSlider("Size", value: $bubbleSize, range: 18...40, format: "%.0f pt")

                        sectionHeader("Material")
                        paramSlider("Material opacity", value: $materialOp, range: 0...1, format: "%.2f")

                        sectionHeader("Liquid Fill")
                        paramSlider("Fill low", value: $fillOpLow, range: 0...0.5, format: "%.2f")
                        paramSlider("Fill high", value: $fillOpHigh, range: 0...0.8, format: "%.2f")
                    }

                    Group {
                        sectionHeader("Specular")
                        paramSlider("Highlight", value: $specularOp, range: 0...1, format: "%.2f")
                        paramSlider("Pinpoint", value: $pinpointOp, range: 0...1, format: "%.2f")
                    }

                    Group {
                        sectionHeader("Rim & Reflection")
                        paramSlider("Rim opacity", value: $rimOp, range: 0...0.5, format: "%.2f")
                        paramSlider("Rim width", value: $rimWidth, range: 0.5...3, format: "%.1f px")
                        paramSlider("Bottom refl.", value: $reflectionOp, range: 0...0.3, format: "%.2f")
                    }

                    Group {
                        sectionHeader("Shadow")
                        paramSlider("Shadow opacity", value: $shadowOp, range: 0...0.8, format: "%.2f")
                        paramSlider("Shadow radius", value: $shadowRadius, range: 0...15, format: "%.1f")
                    }

                    Divider().background(Color.white.opacity(0.2))

                    // Export current values
                    Button("Copy Values to Clipboard") {
                        let text = """
                        // GlassBubbleView tuning — \(Date())
                        size: \(String(format: "%.0f", bubbleSize))
                        fillOpLow: \(String(format: "%.2f", fillOpLow))
                        fillOpHigh: \(String(format: "%.2f", fillOpHigh))
                        specularOp: \(String(format: "%.2f", specularOp))
                        pinpointOp: \(String(format: "%.2f", pinpointOp))
                        rimOp: \(String(format: "%.2f", rimOp))
                        rimWidth: \(String(format: "%.1f", rimWidth))
                        reflectionOp: \(String(format: "%.2f", reflectionOp))
                        shadowOp: \(String(format: "%.2f", shadowOp))
                        shadowRadius: \(String(format: "%.1f", shadowRadius))
                        materialOp: \(String(format: "%.2f", materialOp))
                        """
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .buttonStyle(.bordered)

                    Button("Reset to Defaults") {
                        bubbleSize = 27; fillOpLow = 0.12; fillOpHigh = 0.30
                        specularOp = 0.30; pinpointOp = 0.50; rimOp = 0.20
                        rimWidth = 1.0; reflectionOp = 0.05; shadowOp = 0.25
                        shadowRadius = 5.0; materialOp = 1.0
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
            }
            .frame(width: 260)
            .background(Color(white: 0.08))
        }
    }

    var activityColor: Color {
        if activity < 30 { return .mint }
        if activity < 55 { return .teal }
        if activity < 80 { return .indigo }
        return .pink
    }

    func cpuColorFor(_ v: Double) -> Color {
        if v < 40 { return .cyan }
        if v < 65 { return .blue }
        if v < 85 { return .purple }
        return .red
    }

    func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
            .padding(.top, 4)
    }

    func paramSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 100, alignment: .leading)
            Slider(value: value, in: range)
                .controlSize(.small)
            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 50, alignment: .trailing)
        }
    }
}

// MARK: - Tuning Parameters

struct GlassTuning {
    var size: CGFloat
    var fillOpLow: Double
    var fillOpHigh: Double
    var specularOp: Double
    var pinpointOp: Double
    var rimOp: Double
    var rimWidth: CGFloat
    var reflectionOp: Double
    var shadowOp: Double
    var shadowRadius: CGFloat
    var materialOp: Double
}

// MARK: - Tunable Bubble (mirrors GlassBubbleView but with editable params)

struct TunableBubble: View {
    let tintColor: Color
    let fillRatio: CGFloat
    let label: String
    let params: GlassTuning

    var body: some View {
        let s = params.size

        ZStack {
            // Glass base
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(params.materialOp)
                .frame(width: s, height: s)

            // Liquid fill
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            tintColor.opacity(0.0),
                            tintColor.opacity(params.fillOpLow),
                            tintColor.opacity(params.fillOpHigh)
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 1.0 - fillRatio),
                        endPoint: .bottom
                    )
                )
                .frame(width: s, height: s)

            // Specular highlight
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(params.specularOp),
                            .white.opacity(params.specularOp * 0.25),
                            .clear
                        ],
                        center: UnitPoint(x: 0.4, y: 0.35),
                        startRadius: 0,
                        endRadius: s * 0.25
                    )
                )
                .frame(width: s * 0.5, height: s * 0.35)
                .offset(x: -s * 0.08, y: -s * 0.15)

            // Pinpoint
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(params.pinpointOp),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.08
                    )
                )
                .frame(width: s * 0.12, height: s * 0.08)
                .offset(x: -s * 0.1, y: -s * 0.2)

            // Rim light
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            .white.opacity(params.rimOp),
                            .white.opacity(params.rimOp * 0.2),
                            .clear,
                            .clear,
                            .clear,
                            .white.opacity(params.rimOp * 0.3),
                            .white.opacity(params.rimOp)
                        ],
                        center: .center,
                        startAngle: .degrees(-40),
                        endAngle: .degrees(320)
                    ),
                    lineWidth: params.rimWidth
                )
                .frame(width: s - 1, height: s - 1)

            // Bottom reflection
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(params.reflectionOp),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.2
                    )
                )
                .frame(width: s * 0.4, height: s * 0.14)
                .offset(y: s * 0.32)

            // Label
            Text(label)
                .font(.system(size: max(5, s * 0.22), weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(width: s, height: s)
        .clipShape(Circle())
        .shadow(color: .black.opacity(params.shadowOp), radius: params.shadowRadius, x: 0, y: 3)
    }
}

// MARK: - App Delegate

class PreviewDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MemBubble — Bubble Lab"
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
