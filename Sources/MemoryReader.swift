import Cocoa
import Darwin

// MARK: - Memory Reader (Native Mach APIs)

class MemoryReader: ObservableObject {
    @Published var info = MemoryInfo()
    @Published var topProcesses: [ProcessMemInfo] = []

    private var timer: Timer?
    private(set) var baselineUsed: UInt64 = 0

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

        let sortMode = SettingsManager.shared.processSortMode
        topProcesses = readTopProcesses(limit: 12, sortMode: sortMode)
    }

    private func recalculatePressure() {
        // 1. RAM pressure relative to baseline
        let available = info.total - baselineUsed
        var ramPressure: Double = 0
        if info.used > baselineUsed && available > 0 {
            let delta = info.used - baselineUsed
            ramPressure = min(Double(delta) / Double(available) * 100, 100)
        }

        // 2. Swap boost — swap usage as % of total RAM adds urgency
        let swapBoost: Double
        if info.total > 0 && info.swapUsed > 0 {
            let swapRatio = Double(info.swapUsed) / Double(info.total) * 100
            swapBoost = min(swapRatio * 2, 40)
        } else {
            swapBoost = 0
        }

        // 3. Kernel pressure level boost — the OS itself is alarming
        let kernelBoost: Double
        switch info.kernelPressureLevel {
        case 1: kernelBoost = 15   // warn
        case 2: kernelBoost = 30   // critical
        case 4: kernelBoost = 50   // urgent
        default: kernelBoost = 0   // normal
        }

        // 4. Compressed ratio boost — high compression = CPU strain
        let compressBoost: Double
        if info.compressedRatio > 0.25 {
            compressBoost = (info.compressedRatio - 0.25) * 60
        } else {
            compressBoost = 0
        }

        // Composite: RAM is base, signals boost the severity
        info.pressure = min(ramPressure + swapBoost + kernelBoost + compressBoost, 100)
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
        var pids = [pid_t](repeating: 0, count: 2048)
        let bytesUsed = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        let pidCount = Int(bytesUsed) / MemoryLayout<pid_t>.size

        var processes: [ProcessMemInfo] = []

        for i in 0..<pidCount {
            let pid = pids[i]
            if pid == 0 { continue }

            var taskInfo = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, infoSize)

            if ret > 0 {
                let mem = UInt64(taskInfo.pti_resident_size)
                if mem > 10 * 1024 * 1024 {
                    var nameBuffer = [CChar](repeating: 0, count: 1024)
                    proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
                    let name = String(cString: nameBuffer)

                    if !name.isEmpty {
                        processes.append(ProcessMemInfo(pid: pid, name: name, memory: mem))
                    }
                }
            }
        }

        switch sortMode {
        case .byMemory:
            processes.sort { $0.memory > $1.memory }
        case .byName:
            processes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return Array(processes.prefix(limit))
    }
}
