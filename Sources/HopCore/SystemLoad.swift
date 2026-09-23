import Foundation

/// A snapshot of how busy the machine is, shown under Activity Monitor.
/// Fields are nil until they can be measured (CPU and network need two samples).
public struct SystemLoad: Equatable, Sendable {
    /// 0…1 across all cores.
    public var cpu: Double?
    /// 0…1, the GPU's "Device Utilization".
    public var gpu: Double?
    /// Bytes in use (app memory + wired + compressed, as Activity Monitor counts it).
    public var memoryUsed: UInt64?
    public var memoryTotal: UInt64?
    /// Bytes per second over all non-loopback interfaces.
    public var download: Double?
    public var upload: Double?

    public init(cpu: Double? = nil, gpu: Double? = nil, memoryUsed: UInt64? = nil, memoryTotal: UInt64? = nil,
                download: Double? = nil, upload: Double? = nil) {
        self.cpu = cpu
        self.gpu = gpu
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.download = download
        self.upload = upload
    }

    /// "CPU 12% · GPU 3% · RAM 18.4/48 GB · ↓ 1.2 MB/s ↑ 40 KB/s"; unknown parts show "…".
    public var summary: String {
        let memory: String
        if let used = memoryUsed, let total = memoryTotal {
            memory = "\(Self.gigabytes(used))/\(Self.gigabytes(total)) GB"
        } else {
            memory = "…"
        }
        let net = [("↓", download), ("↑", upload)].map { "\($0) \($1.map(Self.rate) ?? "…")" }.joined(separator: " ")
        return ["CPU \(cpu.map(Self.percent) ?? "…")", "GPU \(gpu.map(Self.percent) ?? "…")", "RAM \(memory)", net]
            .joined(separator: " · ")
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// Binary gigabytes, like Activity Monitor: 1 decimal, none for whole numbers.
    static func gigabytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        let rounded = (gb * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    /// "0 B/s", "512 B/s", "40 KB/s", "1.2 MB/s": SI units, one decimal below 10.
    static func rate(_ bytesPerSecond: Double) -> String {
        var value = max(bytesPerSecond, 0)
        for unit in ["B", "KB", "MB", "GB"] {
            if value < 999.5 || unit == "GB" {
                if unit == "B" { return "\(Int(value.rounded())) B/s" }
                return value < 9.95 ? String(format: "%.1f %@/s", value, unit) : "\(Int(value.rounded())) \(unit)/s"
            }
            value /= 1000
        }
        return ""
    }
}
