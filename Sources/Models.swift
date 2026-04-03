import Cocoa

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
    var pageouts: UInt64 = 0           // cumulative pageouts since boot
    var swapouts: UInt64 = 0           // cumulative swapouts since boot
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

// MARK: - Snapshot (for export)

struct Snapshot: Codable {
    let timestamp: Date
    let memoryPressure: Double
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let cpuUsage: Double
    let diskUsed: UInt64
    let diskTotal: UInt64
    let topProcesses: [ProcessSnapshot]
}

struct ProcessSnapshot: Codable {
    let pid: Int32
    let name: String
    let memory: UInt64
    let cpuPercent: Double
}

struct SessionRecord: Codable {
    let id: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let snapshotCount: Int
    let peakPressure: Double
    let peakCPU: Double
    let peakMemoryUsed: UInt64
    let snapshots: [Snapshot]
}

// MARK: - Display Mode

enum DisplayMode: Int {
    case memoryOnly = 0
    case cpuOnly = 1
    case both = 2
    case all = 3  // memory + activity + CPU
}

// MARK: - Process Sort Mode

enum ProcessSortMode: Int {
    case byMemory = 0
    case byName = 1
    case byCPU = 2
}

// MARK: - Anchor Quadrant (determines expansion direction)

enum AnchorQuadrant: Int {
    case topRight = 0     // bubble top-right fixed, panel grows down-left
    case topLeft = 1      // bubble top-left fixed, panel grows down-right
    case bottomRight = 2  // bubble bottom-right fixed, panel grows up-left
    case bottomLeft = 3   // bubble bottom-left fixed, panel grows up-right

    /// The anchor corner of the window frame for this quadrant
    func anchorPoint(from frame: NSRect) -> NSPoint {
        switch self {
        case .topRight:    return NSPoint(x: frame.maxX, y: frame.maxY)
        case .topLeft:     return NSPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight: return NSPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft:  return NSPoint(x: frame.minX, y: frame.minY)
        }
    }

    /// Compute the window origin given an anchor point and the new content size
    func origin(for anchor: NSPoint, size: NSSize) -> NSPoint {
        switch self {
        case .topRight:    return NSPoint(x: anchor.x - size.width, y: anchor.y - size.height)
        case .topLeft:     return NSPoint(x: anchor.x,              y: anchor.y - size.height)
        case .bottomRight: return NSPoint(x: anchor.x - size.width, y: anchor.y)
        case .bottomLeft:  return NSPoint(x: anchor.x,              y: anchor.y)
        }
    }

    /// Determine quadrant from the window center relative to the screen
    static func from(windowCenter: NSPoint, screen: NSScreen) -> AnchorQuadrant {
        let sf = screen.visibleFrame
        let midX = sf.midX
        let midY = sf.midY
        let isRight = windowCenter.x >= midX
        let isTop = windowCenter.y >= midY
        switch (isRight, isTop) {
        case (true, true):   return .topRight
        case (false, true):  return .topLeft
        case (true, false):  return .bottomRight
        case (false, false): return .bottomLeft
        }
    }
}
