import SwiftUI
import Darwin

// MARK: - Stress Test Manager

class StressTestManager: ObservableObject {
    @Published var memoryLevel: Double = 0  // 0.0 to 1.0
    @Published var cpuLevel: Double = 0

    private var memoryProcesses: [Process] = []
    private var cpuProcesses: [Process] = []
    private let scriptDir: String

    init() {
        // Find the tests directory relative to the bundle or working dir
        let bundlePath = Bundle.main.bundlePath
        let projectDir = (bundlePath as NSString).deletingLastPathComponent
        // Go up from MemBubble.app to project root
        let root = ((projectDir as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        scriptDir = root + "/tests"
    }

    func updateMemoryStress(_ level: Double) {
        memoryLevel = level
        killProcesses(&memoryProcesses)

        if level <= 0.05 { return }

        // Allocate proportional to available memory
        // At 100% knob, allocate ~12GB (enough to stress 16GB system)
        let targetMB = Int(level * 12288)
        if targetMB < 256 { return }

        // Launch stress processes in 2GB chunks
        let chunkMB = 2048
        let processCount = max(1, targetMB / chunkMB)
        let perProcessMB = targetMB / processCount

        for _ in 0..<processCount {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = [scriptDir + "/stress_memory.py", String(perProcessMB)]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            memoryProcesses.append(proc)
        }
    }

    func updateCPUStress(_ level: Double) {
        cpuLevel = level
        killProcesses(&cpuProcesses)

        if level <= 0.05 { return }

        // Spawn CPU-burning python processes
        let threadCount = max(1, Int(level * 8))  // up to 8 CPU burners

        for _ in 0..<threadCount {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = ["-c", """
                import time, math
                while True:
                    for i in range(100000):
                        math.sqrt(i * 1.23456)
                """]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            cpuProcesses.append(proc)
        }
    }

    func stopAll() {
        killProcesses(&memoryProcesses)
        killProcesses(&cpuProcesses)
        memoryLevel = 0
        cpuLevel = 0
    }

    private func killProcesses(_ processes: inout [Process]) {
        for proc in processes {
            if proc.isRunning {
                proc.terminate()
            }
        }
        processes.removeAll()
    }

    deinit {
        stopAll()
    }
}

// MARK: - Test Panel View

struct TestPanelView: View {
    @StateObject private var manager = StressTestManager()
    @State private var memKnob: Double = 0
    @State private var cpuKnob: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("STRESS TEST")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text("Turn knobs to stress the system and watch the bubbles react")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            HStack(spacing: 30) {
                KnobView(label: "MEMORY", color: .green, value: $memKnob)
                    .onChange(of: memKnob) { _, newValue in
                        manager.updateMemoryStress(newValue)
                    }

                KnobView(label: "CPU", color: .cyan, value: $cpuKnob)
                    .onChange(of: cpuKnob) { _, newValue in
                        manager.updateCPUStress(newValue)
                    }
            }

            // Status
            VStack(spacing: 4) {
                HStack {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text(String(format: "Memory: %.0f%% (~%.1f GB target)",
                                memKnob * 100, memKnob * 12))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
                HStack {
                    Circle().fill(.cyan).frame(width: 6, height: 6)
                    Text(String(format: "CPU: %.0f%% (%d threads)",
                                cpuKnob * 100, max(0, Int(cpuKnob * 8))))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
            }

            Button(action: {
                memKnob = 0
                cpuKnob = 0
                manager.stopAll()
            }) {
                HStack {
                    Image(systemName: "stop.circle.fill")
                    Text("Stop All")
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(20)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .onDisappear {
            manager.stopAll()
        }
    }
}
