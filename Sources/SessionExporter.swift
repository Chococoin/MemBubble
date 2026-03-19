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

        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        sessionID = formatter.string(from: Date())
    }

    func startRecording(memoryReader: MemoryReader, cpuReader: CPUReader) {
        timer = Timer.scheduledTimer(withTimeInterval: snapshotInterval, repeats: true) { [weak self] _ in
            self?.captureSnapshot(memoryReader: memoryReader, cpuReader: cpuReader)
        }
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

    var sessionsDirectory: URL { sessionsDir }
    var snapshotCountSoFar: Int { snapshots.count }

    // MARK: - Export JSON

    func exportJSON(session: WorkSession) -> URL? {
        let record = buildRecord(session: session)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(record) else { return nil }

        let fileURL = sessionsDir.appendingPathComponent("session_\(sessionID).json")
        try? data.write(to: fileURL)
        return fileURL
    }

    // MARK: - Export CSV

    func exportCSV(session: WorkSession) -> URL? {
        var lines: [String] = []
        lines.append("timestamp,memory_pressure_%,memory_used_GB,memory_total_GB,cpu_usage_%,disk_used_GB,disk_total_GB,top_process,top_process_memory_GB,top_process_cpu_%")

        let dateFormatter = ISO8601DateFormatter()

        for snap in snapshots {
            let topProc = snap.topProcesses.first
            let ts = dateFormatter.string(from: snap.timestamp)
            let memUsedGB = String(format: "%.2f", Double(snap.memoryUsed) / 1_073_741_824)
            let memTotalGB = String(format: "%.2f", Double(snap.memoryTotal) / 1_073_741_824)
            let diskUsedGB = String(format: "%.2f", Double(snap.diskUsed) / 1_073_741_824)
            let diskTotalGB = String(format: "%.2f", Double(snap.diskTotal) / 1_073_741_824)
            let pressure = String(format: "%.1f", snap.memoryPressure)
            let cpu = String(format: "%.1f", snap.cpuUsage)
            let procName = topProc?.name ?? ""
            let procMem = String(format: "%.2f", Double(topProc?.memory ?? 0) / 1_073_741_824)
            let procCPU = String(format: "%.1f", topProc?.cpuPercent ?? 0)

            lines.append("\(ts),\(pressure),\(memUsedGB),\(memTotalGB),\(cpu),\(diskUsedGB),\(diskTotalGB),\(procName),\(procMem),\(procCPU)")
        }

        let csv = lines.joined(separator: "\n")
        let fileURL = sessionsDir.appendingPathComponent("session_\(sessionID).csv")
        try? csv.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Export HTML Report

    func exportHTML(session: WorkSession) -> URL? {
        let record = buildRecord(session: session)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Build data arrays for charts
        var labels: [String] = []
        var pressureData: [String] = []
        var cpuData: [String] = []
        var memoryData: [String] = []

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        for snap in snapshots {
            labels.append("\"\(timeFormatter.string(from: snap.timestamp))\"")
            pressureData.append(String(format: "%.1f", snap.memoryPressure))
            cpuData.append(String(format: "%.1f", snap.cpuUsage))
            memoryData.append(String(format: "%.2f", Double(snap.memoryUsed) / 1_073_741_824))
        }

        // Build top processes summary (aggregate across all snapshots)
        var processMemTotals: [String: (totalMem: Double, totalCPU: Double, count: Int)] = [:]
        for snap in snapshots {
            for proc in snap.topProcesses {
                let key = proc.name
                var entry = processMemTotals[key] ?? (0, 0, 0)
                entry.totalMem += Double(proc.memory) / 1_073_741_824
                entry.totalCPU += proc.cpuPercent
                entry.count += 1
                processMemTotals[key] = entry
            }
        }
        let topByAvgMem = processMemTotals.sorted { $0.value.totalMem / Double($0.value.count) > $1.value.totalMem / Double($1.value.count) }.prefix(10)

        var processRows = ""
        for (name, stats) in topByAvgMem {
            let avgMem = stats.totalMem / Double(stats.count)
            let avgCPU = stats.totalCPU / Double(stats.count)
            processRows += "<tr><td>\(name)</td><td>\(String(format: "%.2f", avgMem)) GB</td><td>\(String(format: "%.1f", avgCPU))%</td><td>\(stats.count)</td></tr>\n"
        }

        let durationMin = Int(record.duration) / 60
        let durationSec = Int(record.duration) % 60

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>MemBubble Session Report</title>
            <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', sans-serif; background: #1a1a2e; color: #e0e0e0; padding: 32px; }
                h1 { font-size: 24px; margin-bottom: 8px; color: #fff; }
                h2 { font-size: 16px; margin: 24px 0 12px; color: #a0a0c0; text-transform: uppercase; letter-spacing: 1px; }
                .subtitle { color: #808090; font-size: 13px; margin-bottom: 24px; }
                .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-bottom: 24px; }
                .card { background: #252540; border-radius: 12px; padding: 16px; }
                .card .label { font-size: 11px; color: #808090; text-transform: uppercase; letter-spacing: 0.5px; }
                .card .value { font-size: 22px; font-weight: 700; margin-top: 4px; }
                .green { color: #4ade80; }
                .yellow { color: #facc15; }
                .orange { color: #fb923c; }
                .red { color: #f87171; }
                .cyan { color: #22d3ee; }
                .purple { color: #a78bfa; }
                .chart-container { background: #252540; border-radius: 12px; padding: 20px; margin-bottom: 24px; }
                table { width: 100%; border-collapse: collapse; background: #252540; border-radius: 12px; overflow: hidden; }
                th { text-align: left; padding: 10px 14px; background: #1e1e38; color: #808090; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; }
                td { padding: 10px 14px; border-top: 1px solid #2a2a45; font-size: 13px; font-family: 'SF Mono', monospace; }
                .footer { margin-top: 32px; text-align: center; color: #505060; font-size: 11px; }
            </style>
        </head>
        <body>
            <h1>MemBubble Session Report</h1>
            <p class="subtitle">
                \(dateFormatter.string(from: record.startTime)) — \(dateFormatter.string(from: record.endTime))
            </p>

            <div class="cards">
                <div class="card">
                    <div class="label">Duration</div>
                    <div class="value">\(durationMin)m \(durationSec)s</div>
                </div>
                <div class="card">
                    <div class="label">Snapshots</div>
                    <div class="value">\(record.snapshotCount)</div>
                </div>
                <div class="card">
                    <div class="label">Peak Pressure</div>
                    <div class="value \(record.peakPressure < 50 ? "green" : record.peakPressure < 70 ? "yellow" : record.peakPressure < 85 ? "orange" : "red")">\(String(format: "%.0f", record.peakPressure))%</div>
                </div>
                <div class="card">
                    <div class="label">Peak CPU</div>
                    <div class="value cyan">\(String(format: "%.0f", record.peakCPU))%</div>
                </div>
                <div class="card">
                    <div class="label">Peak RAM</div>
                    <div class="value purple">\(String(format: "%.1f", Double(record.peakMemoryUsed) / 1_073_741_824)) GB</div>
                </div>
            </div>

            <h2>Memory Pressure & CPU</h2>
            <div class="chart-container">
                <canvas id="pressureChart"></canvas>
            </div>

            <h2>RAM Usage</h2>
            <div class="chart-container">
                <canvas id="memoryChart"></canvas>
            </div>

            <h2>Top Processes (avg across session)</h2>
            <table>
                <tr><th>Process</th><th>Avg RAM</th><th>Avg CPU</th><th>Appearances</th></tr>
                \(processRows)
            </table>

            <p class="footer">Generated by MemBubble — \(dateFormatter.string(from: Date()))</p>

            <script>
                const labels = [\(labels.joined(separator: ","))];
                const ctxP = document.getElementById('pressureChart').getContext('2d');
                new Chart(ctxP, {
                    type: 'line',
                    data: {
                        labels: labels,
                        datasets: [
                            {
                                label: 'Memory Pressure %',
                                data: [\(pressureData.joined(separator: ","))],
                                borderColor: '#4ade80',
                                backgroundColor: 'rgba(74,222,128,0.1)',
                                fill: true,
                                tension: 0.3
                            },
                            {
                                label: 'CPU Usage %',
                                data: [\(cpuData.joined(separator: ","))],
                                borderColor: '#22d3ee',
                                backgroundColor: 'rgba(34,211,238,0.1)',
                                fill: true,
                                tension: 0.3
                            }
                        ]
                    },
                    options: {
                        responsive: true,
                        scales: {
                            y: { min: 0, max: 100, grid: { color: '#2a2a45' }, ticks: { color: '#808090' } },
                            x: { grid: { color: '#2a2a45' }, ticks: { color: '#808090', maxTicksLimit: 15 } }
                        },
                        plugins: { legend: { labels: { color: '#e0e0e0' } } }
                    }
                });

                const ctxM = document.getElementById('memoryChart').getContext('2d');
                new Chart(ctxM, {
                    type: 'line',
                    data: {
                        labels: labels,
                        datasets: [{
                            label: 'RAM Used (GB)',
                            data: [\(memoryData.joined(separator: ","))],
                            borderColor: '#a78bfa',
                            backgroundColor: 'rgba(167,139,250,0.1)',
                            fill: true,
                            tension: 0.3
                        }]
                    },
                    options: {
                        responsive: true,
                        scales: {
                            y: { min: 0, grid: { color: '#2a2a45' }, ticks: { color: '#808090' } },
                            x: { grid: { color: '#2a2a45' }, ticks: { color: '#808090', maxTicksLimit: 15 } }
                        },
                        plugins: { legend: { labels: { color: '#e0e0e0' } } }
                    }
                });
            </script>
        </body>
        </html>
        """

        let fileURL = sessionsDir.appendingPathComponent("session_\(sessionID).html")
        try? html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Convenience: export all formats

    func exportAll(session: WorkSession) -> URL? {
        _ = exportJSON(session: session)
        _ = exportCSV(session: session)
        return exportHTML(session: session)
    }

    // MARK: - Private

    private func buildRecord(session: WorkSession) -> SessionRecord {
        SessionRecord(
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
    }
}
