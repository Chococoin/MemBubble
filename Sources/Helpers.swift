import SwiftUI

// MARK: - Formatting

func formatBytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1.0 {
        return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_048_576
    return String(format: "%.0f MB", mb)
}

// MARK: - Pressure Color

func pressureColor(for pressure: Double, thresholds: ThresholdConfig = SettingsManager.shared.thresholds) -> Color {
    if pressure < thresholds.yellow { return .green }
    if pressure < thresholds.orange { return .yellow }
    if pressure < thresholds.red { return .orange }
    return .red
}

// MARK: - Pressure Level

enum PressureLevel: Int, Comparable {
    case green = 0
    case yellow = 1
    case orange = 2
    case red = 3

    static func < (lhs: PressureLevel, rhs: PressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(pressure: Double, thresholds: ThresholdConfig = SettingsManager.shared.thresholds) -> PressureLevel {
        if pressure < thresholds.yellow { return .green }
        if pressure < thresholds.orange { return .yellow }
        if pressure < thresholds.red { return .orange }
        return .red
    }

    var label: String {
        switch self {
        case .green: return "Normal"
        case .yellow: return "Elevated"
        case .orange: return "High"
        case .red: return "Critical"
        }
    }
}
