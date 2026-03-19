import Foundation

// MARK: - Shared Data (App ↔ Widget via App Group)

enum SharedData {
    static let suiteName = "group.com.chocos.MemBubble"
    static let pressureKey = "shared_pressure"
    static let cpuUsageKey = "shared_cpuUsage"
    static let usedMemoryKey = "shared_usedMemory"
    static let totalMemoryKey = "shared_totalMemory"
    static let lastUpdateKey = "shared_lastUpdate"
    static let thresholdYellowKey = "shared_thresholdYellow"
    static let thresholdOrangeKey = "shared_thresholdOrange"
    static let thresholdRedKey = "shared_thresholdRed"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func write(pressure: Double, cpuUsage: Double, usedMemory: UInt64, totalMemory: UInt64) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(pressure, forKey: pressureKey)
        defaults.set(cpuUsage, forKey: cpuUsageKey)
        defaults.set(Int64(bitPattern: usedMemory), forKey: usedMemoryKey)
        defaults.set(Int64(bitPattern: totalMemory), forKey: totalMemoryKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)

        // Sync thresholds so widget uses the same colors
        let thresholds = SettingsManager.shared.thresholds
        defaults.set(thresholds.yellow, forKey: thresholdYellowKey)
        defaults.set(thresholds.orange, forKey: thresholdOrangeKey)
        defaults.set(thresholds.red, forKey: thresholdRedKey)
    }
}
