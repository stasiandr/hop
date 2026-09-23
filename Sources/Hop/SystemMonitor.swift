import Darwin
import Foundation
import HopCore
import IOKit

/// Samples CPU, GPU, memory and network load. CPU and network are rates, so
/// each `sample()` reports the change since the previous one.
final class SystemMonitor {
    private struct Counters {
        var time = Date()
        /// Busy and total ticks summed over all cores.
        var cpu = SystemMonitor.cpuTicks()
        var network = SystemMonitor.networkBytes()
    }

    private var previous: Counters?
    private(set) var load = SystemLoad()

    /// Deltas over longer than this (e.g. since the panel was last open) aren't "current".
    private static let maxInterval: TimeInterval = 5

    /// The load as of at most ~1 s ago, sampling again when it's older, so
    /// several rows or redraws within one tick share a sample. Right after a
    /// baseline (no rates yet) the next tick samples sooner, so "…" goes away fast.
    func current() -> SystemLoad {
        let fresh: TimeInterval = load.cpu == nil ? 0.25 : 0.9
        if let previous, Date().timeIntervalSince(previous.time) < fresh { return load }
        return sample()
    }

    @discardableResult
    func sample() -> SystemLoad {
        let now = Counters()
        var load = SystemLoad(gpu: Self.gpuUtilization(), memoryTotal: ProcessInfo.processInfo.physicalMemory)
        load.memoryUsed = Self.memoryUsed()

        if let previous, case let elapsed = now.time.timeIntervalSince(previous.time),
           elapsed > 0.2, elapsed < Self.maxInterval {
            // Per-core counters are 32-bit and wrap; skip a sample where that happened.
            if let a = previous.cpu, let b = now.cpu, b.total > a.total, b.busy >= a.busy {
                load.cpu = Double(b.busy - a.busy) / Double(b.total - a.total)
            }
            // Counters also reset when an interface goes away.
            if let a = previous.network, let b = now.network, b.received >= a.received, b.sent >= a.sent {
                load.download = Double(b.received - a.received) / elapsed
                load.upload = Double(b.sent - a.sent) / elapsed
            }
        }
        previous = now
        self.load = load
        return load
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var busy: UInt64 = 0, total: UInt64 = 0
        for cpu in 0..<Int(count) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return (busy, total)
    }

    /// App memory + wired + compressed, which is what Activity Monitor calls "Memory Used".
    private static func memoryUsed() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count), UInt64(stats.purgeable_count))
        let pages = app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(vm_kernel_page_size)
    }

    /// Bytes received and sent since boot over all interfaces except loopback.
    /// Uses `NET_RT_IFLIST2` for 64-bit counters (`getifaddrs` wraps at 4 GB).
    private static func networkBytes() -> (received: UInt64, sent: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        var received: UInt64 = 0, sent: UInt64 = 0
        return buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= size {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if header.ifm_type == RTM_IFINFO2 {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if message.ifm_flags & IFF_LOOPBACK == 0 {
                        received += message.ifm_data.ifi_ibytes
                        sent += message.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
            return (received, sent)
        }
    }

    /// "Device Utilization %" from the GPU driver's performance statistics.
    private static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                               kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let percent = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber else { continue }
            best = max(best ?? 0, percent.doubleValue / 100)
        }
        return best
    }
}
