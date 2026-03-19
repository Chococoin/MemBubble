import Cocoa
import SwiftUI
import Darwin

// MARK: - Memory Data

struct MemoryInfo {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var free: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var active: UInt64 = 0
    var inactive: UInt64 = 0
    var appMemory: UInt64 = 0
    var pressure: Double = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var kernelPressureLevel: Int = 0   // 0=normal, 1=warn, 2=critical, 4=urgent
    var compressedRatio: Double = 0    // compressed / total
}

struct ProcessMemInfo: Identifiable {
    let id = UUID()
    let pid: Int32
    let name: String
    let memory: UInt64
}

// MARK: - Memory Reader (Native Mach APIs)

class MemoryReader: ObservableObject {
    @Published var info = MemoryInfo()
    @Published var topProcesses: [ProcessMemInfo] = []

    private var timer: Timer?
    private var baselineUsed: UInt64 = 0

    init() {
        // Capture raw memory first to establish baseline
        info = readSystemMemory()
        baselineUsed = info.used
        // Recalculate pressure relative to baseline (will be 0%)
        info.pressure = 0
        topProcesses = readTopProcesses(limit: 12)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func calibrate() {
        let raw = readSystemMemory()
        baselineUsed = raw.used
        refresh()
    }

    func refresh() {
        info = readSystemMemory()

        // 1. RAM pressure relative to baseline
        let available = info.total - baselineUsed
        var ramPressure: Double = 0
        if info.used > baselineUsed && available > 0 {
            let delta = info.used - baselineUsed
            ramPressure = min(Double(delta) / Double(available) * 100, 100)
        }

        // 2. Swap boost — swap usage as % of total RAM adds urgency
        let swapBoost: Double
        if info.total > 0 && info.swapUsed > 0 {
            let swapRatio = Double(info.swapUsed) / Double(info.total) * 100
            // 1 GB swap on 16 GB = ~6% boost, scales up fast
            swapBoost = min(swapRatio * 2, 40)
        } else {
            swapBoost = 0
        }

        // 3. Kernel pressure level boost — the OS itself is alarming
        let kernelBoost: Double
        switch info.kernelPressureLevel {
        case 1: kernelBoost = 15   // warn
        case 2: kernelBoost = 30   // critical
        case 4: kernelBoost = 50   // urgent
        default: kernelBoost = 0   // normal
        }

        // 4. Compressed ratio boost — high compression = CPU strain
        let compressBoost: Double
        if info.compressedRatio > 0.25 {
            compressBoost = (info.compressedRatio - 0.25) * 60  // 25%→0, 50%→15
        } else {
            compressBoost = 0
        }

        // Composite: RAM is base, signals boost the severity
        info.pressure = min(ramPressure + swapBoost + kernelBoost + compressBoost, 100)

        topProcesses = readTopProcesses(limit: 12)
    }

    private func readSystemMemory() -> MemoryInfo {
        var info = MemoryInfo()

        // Total physical memory
        var size = MemoryLayout<UInt64>.size
        var totalMem: UInt64 = 0
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)
        info.total = totalMem

        // VM statistics via host_statistics64
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)

            info.free = UInt64(vmStats.free_count) * pageSize
            info.active = UInt64(vmStats.active_count) * pageSize
            info.inactive = UInt64(vmStats.inactive_count) * pageSize
            info.wired = UInt64(vmStats.wire_count) * pageSize
            info.compressed = UInt64(vmStats.compressor_page_count) * pageSize
            info.used = info.total - info.free
            info.appMemory = info.active + info.inactive - UInt64(vmStats.purgeable_count) * pageSize
        }

        // Swap usage
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        info.swapUsed = swapUsage.xsu_used
        info.swapTotal = swapUsage.xsu_total

        // Kernel memory pressure level (0=normal, 1=warn, 2=critical, 4=urgent)
        var pressureLevel: Int32 = 0
        var plSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &plSize, nil, 0)
        info.kernelPressureLevel = Int(pressureLevel)

        // Compressed ratio
        if info.total > 0 {
            info.compressedRatio = Double(info.compressed) / Double(info.total)
        }

        // Raw pressure (will be recalculated relative to baseline in refresh())
        info.pressure = min(Double(info.used) / Double(info.total) * 100, 100)

        return info
    }

    private func readTopProcesses(limit: Int) -> [ProcessMemInfo] {
        // Use libproc to enumerate processes natively
        var pids = [pid_t](repeating: 0, count: 2048)
        let bytesUsed = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        let pidCount = Int(bytesUsed) / MemoryLayout<pid_t>.size

        var processes: [ProcessMemInfo] = []

        for i in 0..<pidCount {
            let pid = pids[i]
            if pid == 0 { continue }

            var taskInfo = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, infoSize)

            if ret > 0 {
                let mem = UInt64(taskInfo.pti_resident_size)
                if mem > 10 * 1024 * 1024 { // Only show > 10 MB
                    var nameBuffer = [CChar](repeating: 0, count: 1024)
                    proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
                    let name = String(cString: nameBuffer)

                    if !name.isEmpty {
                        processes.append(ProcessMemInfo(pid: pid, name: name, memory: mem))
                    }
                }
            }
        }

        processes.sort { $0.memory > $1.memory }
        return Array(processes.prefix(limit))
    }
}

// MARK: - Formatting

func formatBytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1.0 {
        return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_048_576
    return String(format: "%.0f MB", mb)
}

// MARK: - Bubble View (Collapsed)

struct BubbleView: View {
    let info: MemoryInfo

    var pressureColor: Color {
        if info.pressure < 50 { return .green }
        if info.pressure < 70 { return .yellow }
        if info.pressure < 85 { return .orange }
        return .red
    }

    // Pressure fill height: 0% = empty, 100% = full pearl
    var fillRatio: CGFloat { info.pressure / 100 }

    var body: some View {
        let s: CGFloat = 28

        ZStack {
            // 1. Deep pearl body — dark core with radial depth
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.18).opacity(0.6),
                            Color(white: 0.10).opacity(0.5),
                            Color(white: 0.05).opacity(0.4)
                        ],
                        center: .center,
                        startRadius: s * 0.05,
                        endRadius: s * 0.50
                    )
                )
                .frame(width: s, height: s)

            // 2. Internal pressure liquid — rises from bottom
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            pressureColor.opacity(0.0),
                            pressureColor.opacity(0.20),
                            pressureColor.opacity(0.45),
                            pressureColor.opacity(0.6)
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 1.0 - fillRatio),
                        endPoint: .bottom
                    )
                )
                .frame(width: s, height: s)

            // 3. Internal caustic reflections — reacts to pressure
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            pressureColor.opacity(0.4),
                            pressureColor.opacity(0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.3
                    )
                )
                .frame(width: s * 0.6, height: s * 0.35)
                .offset(y: s * (0.5 - fillRatio * 0.5))
                .blur(radius: 4)

            // 4. Secondary internal glow — deep refraction
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            pressureColor.opacity(0.2),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.25
                    )
                )
                .frame(width: s * 0.4, height: s * 0.25)
                .offset(x: -s * 0.08, y: s * 0.15)
                .blur(radius: 3)

            // 5. Pearl surface sheen — 3D sphere illusion
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02),
                            .clear
                        ],
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: s * 0.0,
                        endRadius: s * 0.5
                    )
                )
                .frame(width: s, height: s)

            // 6. Primary specular highlight — top-left light source
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.5),
                            .white.opacity(0.1),
                            .clear
                        ],
                        center: UnitPoint(x: 0.45, y: 0.4),
                        startRadius: 0,
                        endRadius: s * 0.22
                    )
                )
                .frame(width: s * 0.4, height: s * 0.25)
                .offset(x: -s * 0.08, y: -s * 0.18)

            // 7. Sharp specular pinpoint
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.7),
                            .white.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.08
                    )
                )
                .frame(width: s * 0.1, height: s * 0.07)
                .offset(x: -s * 0.08, y: -s * 0.2)

            // 8. Rim light — edge catch from light source
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.25),
                            .white.opacity(0.05),
                            .clear,
                            .clear,
                            .clear,
                            .white.opacity(0.08),
                            .white.opacity(0.25)
                        ],
                        center: .center,
                        startAngle: .degrees(-40),
                        endAngle: .degrees(320)
                    ),
                    lineWidth: 2
                )
                .frame(width: s - 2, height: s - 2)

            // 9. Bottom reflection — surface bounce
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.07),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.18
                    )
                )
                .frame(width: s * 0.35, height: s * 0.12)
                .offset(y: s * 0.34)

            // 10. Text content
            VStack(spacing: 0) {
                Text(String(format: "%.0f%%", info.pressure))
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundStyle(pressureColor)
                    .foregroundStyle(pressureColor)
            }
            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
        }
        .clipShape(Circle())
        .opacity(0.9)
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Expanded Detail View

struct DetailView: View {
    let info: MemoryInfo
    let processes: [ProcessMemInfo]
    let onClose: () -> Void

    var pressureColor: Color {
        if info.pressure < 50 { return .green }
        if info.pressure < 70 { return .yellow }
        if info.pressure < 85 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("MemBubble")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            Divider().background(Color.white.opacity(0.2))

            // System memory bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("RAM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(formatBytes(info.used)) / \(formatBytes(info.total))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.15))

                        let totalW = geo.size.width
                        let wiredW = totalW * CGFloat(info.wired) / CGFloat(info.total)
                        let activeW = totalW * CGFloat(info.active) / CGFloat(info.total)
                        let compW = totalW * CGFloat(info.compressed) / CGFloat(info.total)

                        HStack(spacing: 0) {
                            Rectangle().fill(Color.red.opacity(0.7))
                                .frame(width: wiredW)
                            Rectangle().fill(Color.yellow.opacity(0.7))
                                .frame(width: activeW)
                            Rectangle().fill(Color.blue.opacity(0.7))
                                .frame(width: compW)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .frame(height: 10)

                HStack(spacing: 12) {
                    Label("Wired", systemImage: "circle.fill")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                    Label("Active", systemImage: "circle.fill")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.8))
                    Label("Compressed", systemImage: "circle.fill")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.blue.opacity(0.8))
                }
            }

            // Stats grid
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    statRow("Wired:", formatBytes(info.wired))
                    statRow("Active:", formatBytes(info.active))
                    statRow("Inactive:", formatBytes(info.inactive))
                }
                VStack(alignment: .leading, spacing: 3) {
                    statRow("Compressed:", formatBytes(info.compressed))
                    statRow("Free:", formatBytes(info.free))
                    statRow("Swap:", formatBytes(info.swapUsed))
                }
            }

            Divider().background(Color.white.opacity(0.2))

            // Top processes
            Text("TOP PROCESSES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))

            ForEach(processes) { proc in
                HStack {
                    Text(proc.name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatBytes(proc.memory))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(processColor(proc.memory))
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(pressureColor.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
    }

    func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    func processColor(_ mem: UInt64) -> Color {
        let mb = mem / 1_048_576
        if mb > 500 { return .red }
        if mb > 200 { return .orange }
        if mb > 100 { return .yellow }
        return .white.opacity(0.8)
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @ObservedObject var reader: MemoryReader
    @State private var expanded = false

    var body: some View {
        Group {
            if expanded {
                DetailView(
                    info: reader.info,
                    processes: reader.topProcesses,
                    onClose: { expanded = false }
                )
            } else {
                BubbleView(info: reader.info)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expanded = true
                        }
                    }
            }
        }
    }
}

// MARK: - App Delegate (Floating Window)

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var reader = MemoryReader()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        let contentView = ContentView(reader: reader)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let hostingView = RightClickHostingView(rootView: contentView)
        hostingView.onRightClick = { [weak self] event in
            guard let self = self else { return }
            NSMenu.popUpContextMenu(self.contextMenu, with: event, for: hostingView)
        }
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Position top-right
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 90
            let y = screenFrame.maxY - 90
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Auto-resize window based on content
        window.contentView?.setFrameSize(window.contentView?.fittingSize ?? NSSize(width: 80, height: 80))

        // Observe content size changes
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: window.contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let contentView = self.window.contentView else { return }
            let newSize = contentView.fittingSize
            let currentOrigin = self.window.frame.origin
            self.window.setFrame(
                NSRect(origin: currentOrigin, size: newSize),
                display: true,
                animate: true
            )
        }

        window.orderFrontRegardless()
    }

    lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshMemory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Calibrate (Set Zero)", action: #selector(calibrateBaseline), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MemBubble", action: #selector(quitApp), keyEquivalent: ""))
        return menu
    }()

    @objc func refreshMemory() {
        reader.refresh()
    }

    @objc func calibrateBaseline() {
        reader.calibrate()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Custom Hosting View for Right-Click

class RightClickHostingView<Content: View>: NSHostingView<Content> {
    var onRightClick: ((NSEvent) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

// MARK: - Main Entry Point

// Prevent multiple instances
let lockPath = NSTemporaryDirectory() + "MemBubble.lock"
let lockFD = open(lockPath, O_CREAT | O_WRONLY, 0o644)
if lockFD == -1 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    fputs("MemBubble is already running.\n", stderr)
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
