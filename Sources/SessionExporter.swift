import Foundation

// MARK: - Session Exporter

class SessionExporter {
    static let shared = SessionExporter()

    private let sessionsDir: URL
    private var snapshots: [Snapshot] = []
    private let snapshotInterval: TimeInterval = 30  // every 30 seconds

    private var timer: Timer?
    private var sessionID: String

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        sessionsDir = appSupport.appendingPathComponent("MemBubble/sessions", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        // Session ID from start time
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        sessionID = formatter.string(from: Date())
    }

    func startRecording(memoryReader: MemoryReader, cpuReader: CPUReader) {
        timer = Timer.scheduledTimer(withTimeInterval: snapshotInterval, repeats: true) { [weak self] _ in
            self?.captureSnapshot(memoryReader: memoryReader, cpuReader: cpuReader)
        }
        // Capture first snapshot immediately
        captureSnapshot(memoryReader: memoryReader, cpuReader: cpuReader)
    }

    private func captureSnapshot(memoryReader: MemoryReader, cpuReader: CPUReader) {
        let mem = memoryReader.info
        let cpu = cpuReader.info
        let disk = memoryReader.diskInfo

        let processSnapshots = memoryReader.topProcesses.map { proc in
            ProcessSnapshot(pid: proc.pid, name: proc.name, memory: proc.memory, cpuPercent: proc.cpuPercent)
        }

        let snapshot = Snapshot(
            timestamp: Date(),
            memoryPressure: mem.pressure,
            memoryUsed: mem.used,
            memoryTotal: mem.total,
            cpuUsage: cpu.totalUsage,
            diskUsed: disk.usedBytes,
            diskTotal: disk.totalBytes,
            topProcesses: processSnapshots
        )

        snapshots.append(snapshot)
    }

    func exportSession(session: WorkSession) -> URL? {
        let record = SessionRecord(
            id: sessionID,
            startTime: session.startTime,
            endTime: Date(),
            duration: session.duration,
            snapshotCount: snapshots.count,
            peakPressure: session.peakPressure,
            peakCPU: session.peakCPU,
            peakMemoryUsed: session.peakMemoryUsed,
            snapshots: snapshots
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(record) else { return nil }

        let fileURL = sessionsDir.appendingPathComponent("session_\(sessionID).json")
        try? data.write(to: fileURL)

        return fileURL
    }

    var sessionsDirectory: URL { sessionsDir }

    var snapshotCountSoFar: Int { snapshots.count }
}
