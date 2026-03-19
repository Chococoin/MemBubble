import Cocoa
import Darwin

// MARK: - CPU Reader (Native Mach APIs)

class CPUReader: ObservableObject {
    @Published var info = CPUInfo()

    private var timer: Timer?
    private var prevUser: natural_t = 0
    private var prevSystem: natural_t = 0
    private var prevIdle: natural_t = 0

    init() {
        // Take initial snapshot
        let ticks = readCPUTicks()
        prevUser = ticks.user
        prevSystem = ticks.system
        prevIdle = ticks.idle

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let ticks = readCPUTicks()

        let deltaUser = ticks.user &- prevUser
        let deltaSystem = ticks.system &- prevSystem
        let deltaIdle = ticks.idle &- prevIdle
        let total = deltaUser &+ deltaSystem &+ deltaIdle

        if total > 0 {
            info.userLoad = Double(deltaUser) / Double(total) * 100
            info.systemLoad = Double(deltaSystem) / Double(total) * 100
            info.idleLoad = Double(deltaIdle) / Double(total) * 100
            info.totalUsage = info.userLoad + info.systemLoad
        }

        prevUser = ticks.user
        prevSystem = ticks.system
        prevIdle = ticks.idle
    }

    private struct CPUTicks {
        var user: natural_t = 0
        var system: natural_t = 0
        var idle: natural_t = 0
    }

    private func readCPUTicks() -> CPUTicks {
        let host = mach_host_self()
        var cpuLoadInfo: processor_info_array_t?
        var processorMsgCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO,
                                          &processorCount, &cpuLoadInfo, &processorMsgCount)

        guard result == KERN_SUCCESS, let cpuLoad = cpuLoadInfo else {
            return CPUTicks()
        }

        var totalUser: natural_t = 0
        var totalSystem: natural_t = 0
        var totalIdle: natural_t = 0

        for i in 0..<Int(processorCount) {
            let base = Int(CPU_STATE_MAX) * i
            totalUser &+= natural_t(cpuLoad[base + Int(CPU_STATE_USER)])
            totalUser &+= natural_t(cpuLoad[base + Int(CPU_STATE_NICE)])
            totalSystem &+= natural_t(cpuLoad[base + Int(CPU_STATE_SYSTEM)])
            totalIdle &+= natural_t(cpuLoad[base + Int(CPU_STATE_IDLE)])
        }

        // Deallocate
        let size = vm_size_t(processorMsgCount) * vm_size_t(MemoryLayout<integer_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuLoad), size)

        return CPUTicks(user: totalUser, system: totalSystem, idle: totalIdle)
    }
}
