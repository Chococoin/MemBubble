import Foundation

// MARK: - UserDefaults Keys

enum SettingsKey {
    static let windowX = "windowPositionX"
    static let windowY = "windowPositionY"
    static let baselineUsed = "baselineUsed"
    static let hasBaseline = "hasBaseline"
    static let notificationsMuted = "notificationsMuted"
    static let alertSoundEnabled = "alertSoundEnabled"
    static let launchAtLogin = "launchAtLogin"
    static let displayMode = "displayMode"
    static let processSortMode = "processSortMode"

    // Thresholds (pressure percentages)
    static let thresholdYellow = "thresholdYellow"
    static let thresholdOrange = "thresholdOrange"
    static let thresholdRed = "thresholdRed"
}

// MARK: - Threshold Configuration

struct ThresholdConfig {
    var yellow: Double
    var orange: Double
    var red: Double

    static let `default` = ThresholdConfig(yellow: 50, orange: 70, red: 85)

    static func load() -> ThresholdConfig {
        let defaults = UserDefaults.standard
        let yellow = defaults.object(forKey: SettingsKey.thresholdYellow) as? Double ?? ThresholdConfig.default.yellow
        let orange = defaults.object(forKey: SettingsKey.thresholdOrange) as? Double ?? ThresholdConfig.default.orange
        let red = defaults.object(forKey: SettingsKey.thresholdRed) as? Double ?? ThresholdConfig.default.red
        return ThresholdConfig(yellow: yellow, orange: orange, red: red)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(yellow, forKey: SettingsKey.thresholdYellow)
        defaults.set(orange, forKey: SettingsKey.thresholdOrange)
        defaults.set(red, forKey: SettingsKey.thresholdRed)
    }
}

// MARK: - Settings Manager

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var thresholds: ThresholdConfig {
        didSet { thresholds.save() }
    }

    @Published var notificationsMuted: Bool {
        didSet { UserDefaults.standard.set(notificationsMuted, forKey: SettingsKey.notificationsMuted) }
    }

    @Published var alertSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(alertSoundEnabled, forKey: SettingsKey.alertSoundEnabled) }
    }

    @Published var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: SettingsKey.displayMode) }
    }

    @Published var processSortMode: ProcessSortMode {
        didSet { UserDefaults.standard.set(processSortMode.rawValue, forKey: SettingsKey.processSortMode) }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.thresholds = ThresholdConfig.load()
        self.notificationsMuted = defaults.bool(forKey: SettingsKey.notificationsMuted)
        self.alertSoundEnabled = defaults.bool(forKey: SettingsKey.alertSoundEnabled)
        self.displayMode = DisplayMode(rawValue: defaults.integer(forKey: SettingsKey.displayMode)) ?? .memoryOnly
        self.processSortMode = ProcessSortMode(rawValue: defaults.integer(forKey: SettingsKey.processSortMode)) ?? .byMemory
    }

    // MARK: - Window Position (stores top-right anchor point)

    func saveWindowAnchor(_ topRight: NSPoint) {
        let defaults = UserDefaults.standard
        defaults.set(Double(topRight.x), forKey: SettingsKey.windowX)
        defaults.set(Double(topRight.y), forKey: SettingsKey.windowY)
    }

    func loadWindowAnchor() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsKey.windowX) != nil else { return nil }
        let x = defaults.double(forKey: SettingsKey.windowX)
        let y = defaults.double(forKey: SettingsKey.windowY)
        return NSPoint(x: x, y: y)
    }

    // MARK: - Baseline

    func saveBaseline(_ value: UInt64) {
        let defaults = UserDefaults.standard
        defaults.set(Int64(bitPattern: value), forKey: SettingsKey.baselineUsed)
        defaults.set(true, forKey: SettingsKey.hasBaseline)
    }

    func loadBaseline() -> UInt64? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.hasBaseline) else { return nil }
        let stored = defaults.object(forKey: SettingsKey.baselineUsed) as? Int64 ?? 0
        return UInt64(bitPattern: stored)
    }
}
