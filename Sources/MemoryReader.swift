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
    private var previousPageouts: UInt64 = 0
    private var previousSwapouts: UInt64 = 0
    private var swapIORate: Double = 0  // swap page operations per second

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
        // Pressure reflects PERCEIVED SLOWNESS, not kernel alarm levels.
        // Apple Silicon handles memory pressure gracefully — compressor is fast,
        // SSD swap is ~7 GB/s. The user doesn't feel it until the system is
        // actively thrashing (high swap I/O rate).
        //
        // Design principle: at 80%, the user should START feeling slowness.
        // Red (85+) means "close apps now, you will notice lag."
        //
        // Levels:
        //   Green  (0-39):  Healthy, Apple Silicon handling everything
        //   Yellow (40-64): Memory is tight but performance is fine
        //   Orange (65-79): Starting to strain, consider closing apps
        //   Red    (80+):   Thrashing — user will feel real slowness

        // -- Calculate swap I/O rate (thrashing indicator) --
        let elapsed = Date().timeIntervalSince(previousSampleTime)
        if elapsed > 0 && previousPageouts > 0 {
            let deltaPageouts = info.pageouts > previousPageouts ? info.pageouts - previousPageouts : 0
            let deltaSwapouts = info.swapouts > previousSwapouts ? info.swapouts - previousSwapouts : 0
            let newRate = Double(deltaPageouts + deltaSwapouts) / elapsed
            // Smooth the rate to avoid spikes
            swapIORate = swapIORate * 0.6 + newRate * 0.4
        }
        previousPageouts = info.pageouts
        previousSwapouts = info.swapouts

        var pressure: Double = 0

        // 1. Swap I/O rate — THE primary indicator of perceived slowness
        //    This measures active thrashing, not just that swap exists.
        //    On Apple Silicon, < 50 ops/s is imperceptible, > 500 is painful.
        if swapIORate > 1000 {
            pressure = 75           // severe thrashing
        } else if swapIORate > 500 {
            pressure = 55           // heavy I/O, starting to feel it
        } else if swapIORate > 100 {
            pressure = 35           // moderate, system working but OK
        } else if swapIORate > 20 {
            pressure = 18           // light swap activity, normal
        } else {
            pressure = 5            // quiet, everything fine
        }

        // 2. Swap volume — large accumulated swap means more potential thrashing
        let swapGB = Double(info.swapUsed) / 1_073_741_824
        if swapGB > 4 {
            pressure += 20          // > 4GB: system is deep in swap
        } else if swapGB > 2 {
            pressure += 10          // > 2GB: significant swap
        } else if swapGB > 0.5 {
            pressure += 3           // > 500MB: mild, normal on macOS
        }

        // 3. Reclaimable memory — if near zero, any new allocation triggers swap
        let reclaimable = info.free + info.inactive
        if info.total > 0 {
            let reclaimableRatio = Double(reclaimable) / Double(info.total)
            if reclaimableRatio < 0.03 {
                pressure += 15      // < 3%: extremely tight
            } else if reclaimableRatio < 0.08 {
                pressure += 6       // < 8%: getting tight
            }
        }

        // 4. Kernel level — only boost for urgent (level 4, about to kill apps)
        //    Levels 1-2 are too sensitive on Apple Silicon, ignore them
        if info.kernelPressureLevel >= 4 {
            pressure += 15          // kernel about to OOM-kill
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
            info.pageouts = UInt64(vmStats.pageouts)
            info.swapouts = UInt64(vmStats.swapouts)
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
