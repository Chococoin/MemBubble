import Foundation

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
    let cpuPercent: Double
}

// MARK: - Disk Data

struct DiskInfo {
    var totalBytes: UInt64 = 0
    var freeBytes: UInt64 = 0
    var usedBytes: UInt64 = 0
}

// MARK: - CPU Data

struct CPUInfo {
    var userLoad: Double = 0
    var systemLoad: Double = 0
    var idleLoad: Double = 0
    var totalUsage: Double = 0   // user + system as percentage
}

// MARK: - Display Mode

enum DisplayMode: Int {
    case memoryOnly = 0
    case cpuOnly = 1
    case both = 2
}

// MARK: - Process Sort Mode

enum ProcessSortMode: Int {
    case byMemory = 0
    case byName = 1
    case byCPU = 2
}
