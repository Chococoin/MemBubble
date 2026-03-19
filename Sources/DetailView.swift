import SwiftUI

// MARK: - Sparkline Chart

struct SparklineView: View {
    let samples: [Double]
    let peakPressure: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if samples.count >= 2 {
                let maxVal = max(peakPressure, 100)
                let w = geo.size.width
                let h = geo.size.height

                // Filled area
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    for (i, sample) in samples.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(samples.count - 1)
                        let y = h - (h * CGFloat(sample / maxVal))
                        if i == 0 {
                            path.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line
                Path { path in
                    for (i, sample) in samples.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(samples.count - 1)
                        let y = h - (h * CGFloat(sample / maxVal))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, lineWidth: 1.5)
            } else {
                Text("Collecting data...")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Expanded Detail View

struct DetailView: View {
    let info: MemoryInfo
    let diskInfo: DiskInfo
    let processes: [ProcessMemInfo]
    let session: WorkSession
    let cpuInfo: CPUInfo?
    let onClose: () -> Void
    @State private var selectedProcess: ProcessMemInfo?

    var pColor: Color { pressureColor(for: info.pressure) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("MemBubble")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()

                if session.peakPressure > 0 {
                    Text(String(format: "Peak: %.0f%%", session.peakPressure))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            Divider().background(Color.white.opacity(0.2))

            // Sparkline
            if !session.samples.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PRESSURE (10 MIN)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))

                    SparklineView(
                        samples: session.samples,
                        peakPressure: session.peakPressure,
                        color: pColor
                    )
                    .frame(height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

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

            // CPU info (if monitoring enabled)
            if let cpu = cpuInfo {
                HStack {
                    Text("CPU")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.0f%% (user %.0f%% + sys %.0f%%)", cpu.totalUsage, cpu.userLoad, cpu.systemLoad))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
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

            // Disk bar
            if diskInfo.totalBytes > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Disk")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(formatBytes(diskInfo.usedBytes)) / \(formatBytes(diskInfo.totalBytes))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.15))

                            let usedRatio = CGFloat(diskInfo.usedBytes) / CGFloat(diskInfo.totalBytes)
                            let diskColor: Color = usedRatio > 0.9 ? .red : usedRatio > 0.75 ? .orange : .purple

                            Rectangle()
                                .fill(diskColor.opacity(0.7))
                                .frame(width: geo.size.width * usedRatio)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .frame(height: 10)

                    HStack(spacing: 12) {
                        Label("Used", systemImage: "circle.fill")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.purple.opacity(0.8))
                        Label("\(formatBytes(diskInfo.freeBytes)) free", systemImage: "circle.fill")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }

            Divider().background(Color.white.opacity(0.2))

            // Session summary
            VStack(alignment: .leading, spacing: 4) {
                Text("SESSION")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        statRow("Duration:", session.durationFormatted)
                        statRow("Snapshots:", "\(session.snapshotCount)")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        statRow("Peak CPU:", String(format: "%.0f%%", session.peakCPU))
                        statRow("Peak RAM:", formatBytes(session.peakMemoryUsed))
                    }
                }
            }

            Divider().background(Color.white.opacity(0.2))

            // Top processes
            Text("TOP PROCESSES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))

            ForEach(processes) { proc in
                ProcessRowView(
                    process: proc,
                    isSelected: selectedProcess?.pid == proc.pid,
                    onSelect: {
                        selectedProcess = (selectedProcess?.pid == proc.pid) ? nil : proc
                    },
                    onDismiss: {
                        selectedProcess = nil
                    }
                )
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
                .stroke(pColor.opacity(0.4), lineWidth: 1)
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

}
