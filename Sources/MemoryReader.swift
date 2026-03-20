import Cocoa
import Darwin

// MARK: - Memory Reader (Native Mach APIs)

class MemoryReader: ObservableObject {
    @Published var info = MemoryInfo()
    @Published var diskInfo = DiskInfo()
    @Published var topProcesses: [ProcessMemInfo] = []
    @Published var activity: Double = 0  // baseline-relative usage 0-100%

    private var timer: Timer?
    private(set) var baselineUsed: UInt64 = 0
    private var previousCPUTimes: [Int32: Double] = [:]  // pid -> total CPU seconds
    private var previousSampleTime: Date = Date()

    init() {
        // Capture raw memory first to establish baseline
        info = readSystemMemory()

        // Restore persisted baseline or use current
        if let saved = SettingsManager.shared.loadBaseline() {
            baselineUsed = saved
        } else {
            baselineUsed = info.used
        }

        // Recalculate pressure relative to baseline
        recalculatePressure()
        topProcesses = readTopProcesses(limit: 12)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func calibrate() {
        let raw = readSystemMemory()
        baselineUsed = raw.used
        SettingsManager.shared.saveBaseline(baselineUsed)
        refresh()
    }

    func refresh() {
        info = readSystemMemory()
        recalculatePressure()
        recalculateActivity()
        diskInfo = readDiskUsage()

        let sortMode = SettingsManager.shared.processSortMode
        topProcesses = readTopProcesses(limit: 12, sortMode: sortMode)
    }

    private func recalculatePressure() {
        // Pressure should reflect REAL danger, not just memory usage.
        // macOS keeps RAM full by design (inactive pages, caches). That's normal.
        // Real danger = kernel pressure level + heavy swap + high compression.
        //
        // Levels:
        //   Green  (0-49):  Normal operation, system healthy
        //   Yellow (50-69): Elevated, some swap or compression
        //   Orange (70-84): High, significant swap or kernel warning
        //   Red    (85+):   Critical, system struggling, close apps now

        var pressure: Double = 0

        // 1. Kernel pressure level — the most authoritative signal from macOS itself
        //    This is what the OS uses internally to decide when to kill apps
        switch info.kernelPressureLevel {
        case 0: pressure = 10   // normal — base level, everything fine
        case 1: pressure = 45   // warn — system noticed pressure
        case 2: pressure = 75   // critical — system actively reclaiming
        case 4: pressure = 90   // urgent — system about to kill processes
        default: pressure = 10
        }

        // 2. Swap usage — real indicator of memory exhaustion
        //    Small swap (< 200MB) is normal on macOS, don't panic
        //    Heavy swap (> 1GB) means RAM is genuinely full
        if info.total > 0 && info.swapUsed > 0 {
            let swapMB = Double(info.swapUsed) / 1_048_576
            if swapMB > 2000 {
                pressure += 25      // > 2GB swap: serious
            } else if swapMB > 1000 {
                pressure += 15      // > 1GB swap: elevated
            } else if swapMB > 200 {
                pressure += 8       // > 200MB swap: mild
            }
            // < 200MB swap: normal, no boost
        }

        // 3. Compressed memory ratio — high compression means CPU is working hard
        //    to keep things in RAM. > 30% is notable, > 40% is heavy
        if info.compressedRatio > 0.40 {
            pressure += 12
        } else if info.compressedRatio > 0.30 {
            pressure += 5
        }

        // 4. Available memory (free + inactive) — if truly near zero, boost
        //    Inactive can be reclaimed instantly, so free+inactive is what matters
        let reclaimable = info.free + info.inactive
        if info.total > 0 {
            let reclaimableRatio = Double(reclaimable) / Double(info.total)
            if reclaimableRatio < 0.05 {
                pressure += 15   // < 5% reclaimable: dangerous
            } else if reclaimableRatio < 0.10 {
                pressure += 5    // < 10% reclaimable: getting tight
            }
        }

        info.pressure = min(pressure, 100)
    }

    private func recalculateActivity() {
        // Activity = how much more memory is being used compared to baseline (launch/calibrate)
        // 0% = same as baseline, 100% = all remaining RAM consumed since baseline
        let available = info.total - baselineUsed
        if info.used > baselineUsed && available > 0 {
            let delta = info.used - baselineUsed
            activity = min(Double(delta) / Double(available) * 100, 100)
        } else {
            activity = 0
        }
    }

    private func readSystemMemory() -> MemoryInfo {
        var info = MemoryInfo()

        // Total physical memory
        var size = MemoryLayout<UInt64>.size
        var totalMem: UInt64 = 0
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)
        info.total = totalMem

        // VM statistics via host_statistics64
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            info.free = UInt64(vmStats.free_count) * pageSize
            info.active = UInt64(vmStats.active_count) * pageSize
            info.inactive = UInt64(vmStats.inactive_count) * pageSize
            info.wired = UInt64(vmStats.wire_count) * pageSize
            info.compressed = UInt64(vmStats.compressor_page_count) * pageSize
            info.used = info.total - info.free
            info.appMemory = info.active + info.inactive - UInt64(vmStats.purgeable_count) * pageSize
        }

        // Swap usage
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        info.swapUsed = swapUsage.xsu_used
        info.swapTotal = swapUsage.xsu_total

        // Kernel memory pressure level
        var pressureLevel: Int32 = 0
        var plSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &plSize, nil, 0)
        info.kernelPressureLevel = Int(pressureLevel)

        // Compressed ratio
        if info.total > 0 {
            info.compressedRatio = Double(info.compressed) / Double(info.total)
        }

        // Raw pressure (will be recalculated relative to baseline)
        info.pressure = min(Double(info.used) / Double(info.total) * 100, 100)

        return info
    }

    private func readTopProcesses(limit: Int, sortMode: ProcessSortMode = .byMemory) -> [ProcessMemInfo] {
        let now = Date()
        let elapsed = now.timeIntervalSince(previousSampleTime)
        previousSampleTime = now

        var pids = [pid_t](repeating: 0, count: 2048)
        let bytesUsed = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        let pidCount = Int(bytesUsed) / MemoryLayout<pid_t>.size

        var processes: [ProcessMemInfo] = []
        var currentCPUTimes: [Int32: Double] = [:]

        for i in 0..<pidCount {
            let pid = pids[i]
            if pid == 0 { continue }

            var taskInfo = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, infoSize)

            if ret > 0 {
                let mem = UInt64(taskInfo.pti_resident_size)
                if mem > 10 * 1024 * 1024 {
                    // Try proc_pidpath first for reliable name, fall back to proc_name
                    var pathBuffer = [CChar](repeating: 0, count: 4096)
                    let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
                    var name: String
                    if pathLen > 0 {
                        let fullPath = String(cString: pathBuffer)
                        let lastComponent = (fullPath as NSString).lastPathComponent
                        // If last component looks like a version number, use parent dir name
                        if lastComponent.allSatisfy({ $0.isNumber || $0 == "." }) {
                            let parent = ((fullPath as NSString).deletingLastPathComponent as NSString).lastPathComponent
                            name = parent == "versions" ?
                                ((((fullPath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent as NSString).lastPathComponent) :
                                parent
                        } else {
                            name = lastComponent
                        }
                    } else {
                        var nameBuffer = [CChar](repeating: 0, count: 1024)
                        proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
                        name = String(cString: nameBuffer)
                    }

                    if !name.isEmpty {
                        // CPU time in seconds (user + system)
                        let totalCPU = Double(taskInfo.pti_total_user) / 1_000_000_000.0
                                     + Double(taskInfo.pti_total_system) / 1_000_000_000.0
                        currentCPUTimes[pid] = totalCPU

                        // Compute CPU% as delta of CPU time / elapsed wall time
                        var cpuPercent = 0.0
                        if elapsed > 0, let prev = previousCPUTimes[pid] {
                            let delta = totalCPU - prev
                            cpuPercent = (delta / elapsed) * 100.0
                            if cpuPercent < 0 { cpuPercent = 0 }
                        }

                        processes.append(ProcessMemInfo(pid: pid, name: name, memory: mem, cpuPercent: cpuPercent))
                    }
                }
            }
        }

        previousCPUTimes = currentCPUTimes

        switch sortMode {
        case .byMemory:
            processes.sort { $0.memory > $1.memory }
        case .byName:
            processes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .byCPU:
            processes.sort { $0.cpuPercent > $1.cpuPercent }
        }

        return Array(processes.prefix(limit))
    }

    private func readDiskUsage() -> DiskInfo {
        var disk = DiskInfo()
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")
            if let total = attrs[.systemSize] as? UInt64,
               let free = attrs[.systemFreeSize] as? UInt64 {
                disk.totalBytes = total
                disk.freeBytes = free
                disk.usedBytes = total - free
            }
        } catch {}
        return disk
    }
}
