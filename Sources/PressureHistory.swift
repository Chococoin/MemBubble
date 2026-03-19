import Foundation

// MARK: - Pressure History (Ring Buffer)

class PressureHistory: ObservableObject {
    static let maxSamples = 300  // 10 min at 2s intervals

    @Published private(set) var samples: [Double] = []
    @Published private(set) var peakPressure: Double = 0

    func record(_ pressure: Double) {
        samples.append(pressure)
        if samples.count > PressureHistory.maxSamples {
            samples.removeFirst()
        }
        if pressure > peakPressure {
            peakPressure = pressure
        }
    }

    func resetPeak() {
        peakPressure = samples.max() ?? 0
    }
}
