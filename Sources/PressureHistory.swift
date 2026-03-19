import Foundation

// MARK: - Work Session

class WorkSession: ObservableObject {
    static let maxSamples = 300  // 10 min at 2s intervals

    let startTime = Date()

    @Published private(set) var samples: [Double] = []
    @Published private(set) var peakPressure: Double = 0
    @Published private(set) var peakCPU: Double = 0
    @Published private(set) var peakMemoryUsed: UInt64 = 0
    @Published private(set) var snapshotCount: Int = 0

    var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    var durationFormatted: String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        }
        return String(format: "%dm %02ds", m, s)
    }

    func record(pressure: Double, cpuUsage: Double, memoryUsed: UInt64) {
        snapshotCount += 1

        // Pressure ring buffer
        samples.append(pressure)
        if samples.count > WorkSession.maxSamples {
            samples.removeFirst()
        }

        // Update peaks
        if pressure > peakPressure {
            peakPressure = pressure
        }
        if cpuUsage > peakCPU {
            peakCPU = cpuUsage
        }
        if memoryUsed > peakMemoryUsed {
            peakMemoryUsed = memoryUsed
        }
    }

    func resetPeaks() {
        peakPressure = samples.max() ?? 0
        peakCPU = 0
        peakMemoryUsed = 0
    }
}
