import Foundation

// MARK: - MenuBarStatKind

/// A system metric that can be shown next to the menu bar icon.
enum MenuBarStatKind: String, CaseIterable, Identifiable {
    case cpu, memory, disk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu:    return "CPU"
        case .memory: return "Memory Used"
        case .disk:   return "Disk Free"
        }
    }
}

// MARK: - Menu bar stat selection

enum MenuBarStatsPreference {

    private static let key = "menuBarStatKinds"
    private static let defaultSelection: [MenuBarStatKind] = [.cpu, .memory]

    static var selected: [MenuBarStatKind] {
        get {
            guard let raw = UserDefaults.standard.stringArray(forKey: key) else {
                return defaultSelection
            }
            return raw.compactMap(MenuBarStatKind.init)
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue), forKey: key)
            NotificationCenter.default.post(name: .menuBarStatsPreferenceChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let menuBarStatsPreferenceChanged = Notification.Name("menuBarStatsPreferenceChanged")
}

// MARK: - SystemStatsMonitor

/// Reads system-wide CPU load, memory pressure, and free disk space using
/// public host/vm mach APIs — no elevated privileges or private API needed.
final class SystemStatsMonitor {

    static let shared = SystemStatsMonitor()

    private var previousCPUTicks: host_cpu_load_info?

    private init() {}

    func formattedValue(for kind: MenuBarStatKind) -> String {
        switch kind {
        case .cpu:    return cpuUsagePercent().map { "\(Int($0.rounded()))%" } ?? "--%"
        case .memory: return memoryUsedGB().map { String(format: "%.1fG", $0) } ?? "--G"
        case .disk:   return diskFreeGB().map { "\(Int($0.rounded()))G" } ?? "--G"
        }
    }

    // MARK: CPU

    /// Percent busy since the last call. Returns nil on the first call —
    /// there's no prior sample to diff against yet.
    private func cpuUsagePercent() -> Double? {
        guard let current = hostCPULoadInfo() else { return nil }
        defer { previousCPUTicks = current }
        guard let previous = previousCPUTicks else { return nil }

        let userDelta = Double(current.cpu_ticks.0 &- previous.cpu_ticks.0)
        let systemDelta = Double(current.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idleDelta = Double(current.cpu_ticks.2 &- previous.cpu_ticks.2)
        let niceDelta = Double(current.cpu_ticks.3 &- previous.cpu_ticks.3)
        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        guard totalDelta > 0 else { return nil }

        return (userDelta + systemDelta + niceDelta) / totalDelta * 100
    }

    private func hostCPULoadInfo() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    // MARK: Memory

    private func memoryUsedGB() -> Double? {
        var size = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        var stats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }

        let usedPages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)
        return Double(usedBytes) / 1_073_741_824
    }

    // MARK: Disk

    private func diskFreeGB() -> Double? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return Double(free) / 1_073_741_824
    }
}
