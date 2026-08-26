import Foundation
import OSLog

// MARK: - Protocol boundaries
//
// Every side effect lives behind a protocol and arrives by initializer
// injection. Tests never touch a live process, a real signal, or the disk —
// they substitute recording implementations of these boundaries.

/// Supplies the process census.
public protocol CensusProvider: Sendable {
    /// Snapshot every process on the host.
    func sampleAll() throws -> [ProcessSample]
}

/// Supplies memory pressure.
public protocol PressureProvider: Sendable {
    /// Current pressure for the given configuration.
    func pressure(configuration: GuardianConfiguration) -> Pressure
}

/// Sends signals to processes.
public protocol ProcessSignaler: Sendable {
    /// Send a POSIX signal to a pid. Returns true when the signal was delivered.
    func signal(_ pid: Int32, _ sig: Int32) -> Bool
    /// True when the pid is currently alive.
    func alive(_ pid: Int32) -> Bool
}

/// Receives sweep telemetry (status, logs, dashboards read from here).
public protocol TelemetrySink: Sendable {
    /// Record one completed sweep.
    func record(_ report: SweepReport) async
}

// MARK: - Production census (libproc, typed Swift — never `ps`)

/// Live process census via `proc_listallpids` + `proc_pidinfo` — pids,
/// parentage, rss, and start time without a single pipe (Exhibit-3 class:
/// ad-hoc child-process plumbing is canon anti-pattern).
public struct LibprocCensus: CensusProvider {

    public init() {}

    public enum CensusError: Error, Sendable {
        case listAllPidsFailed(Int32)
    }

    public func sampleAll() throws -> [ProcessSample] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { throw CensusError.listAllPidsFailed(count) }

        var pids = [pid_t](repeating: 0, count: Int(count))
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { throw CensusError.listAllPidsFailed(filled) }

        let now = Date()
        return pids.prefix(Int(filled)).compactMap { sample(pid: $0, now: now) }
    }

    /// Snapshot one pid; nil when it exits mid-census (normal — processes die).
    public func sample(pid: pid_t, now: Date = Date()) -> ProcessSample? {
        var info = proc_taskallinfo()
        let size = proc_pidinfo(
            pid, PROC_PIDTASKALLINFO, 0,
            &info, Int32(MemoryLayout<proc_taskallinfo>.size)
        )
        guard size == Int32(MemoryLayout<proc_taskallinfo>.size) else { return nil }

        let startTime = Date(
            timeIntervalSince1970: TimeInterval(info.pbsd.pbi_start_tvsec)
                + TimeInterval(info.pbsd.pbi_start_tvusec) / 1_000_000
        )
        return ProcessSample(
            pid: pid,
            ppid: pid_t(info.pbsd.pbi_ppid),
            user: userName(uid: info.pbsd.pbi_uid),
            executablePath: executablePath(pid: pid) ?? shortName(info: &info),
            args: processArgs(pid: pid),
            ageSeconds: max(0, now.timeIntervalSince(startTime)),
            rssBytes: info.ptinfo.pti_resident_size
        )
    }

    /// Full executable path via `proc_pidpath`; falls back to the short name.
    private func executablePath(pid: pid_t) -> String? {
        // MAXPATHLEN — PROC_PIDPATHINFO_MAXSIZE is not exported to Swift.
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// `pbi_comm` short name from the task info tuple (C tuple → String).
    private func shortName(info: inout proc_taskallinfo) -> String {
        withUnsafeBytes(of: &info.pbsd.pbi_comm) { raw in
            raw.bindMemory(to: CChar.self)
                .baseAddress
                .map { String(cString: $0) } ?? "?"
        }
    }

    /// Process arguments via `sysctl(KERN_PROCARGS2)`. Empty on denial —
    /// policy degrades to executable-name-only matching, never a crash.
    private func processArgs(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        // Layout: argc (int32) + exec path + NUL-separated args.
        return Data(buffer.dropFirst(MemoryLayout<Int32>.size))
            .split(separator: 0)
            .dropFirst()
            .compactMap { field in
                field.isEmpty ? nil : String(decoding: field, as: UTF8.self)
            }
    }

    private func userName(uid: uid_t) -> String {
        guard let pw = getpwuid(uid) else { return String(uid) }
        return String(cString: pw.pointee.pw_name)
    }
}

/// Swap-driven pressure sampling via `sysctl(VM_SWAPUSAGE)`.
public struct SwapPressureSampler: PressureProvider {

    public init() {}

    /// Current swap usage in bytes; 0 when the sysctl is unavailable.
    public func swapUsedBytes() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        guard sysctl(&mib, 2, &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    public func pressure(configuration: GuardianConfiguration) -> Pressure {
        swapUsedBytes() > configuration.swapEscalationBytes ? .elevated : .normal
    }
}

/// Production signaler over `kill(2)`.
public struct POSIXSignaler: ProcessSignaler {
    public init() {}
    public func signal(_ pid: Int32, _ sig: Int32) -> Bool {
        kill(pid, sig) == 0
    }
    public func alive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}

/// JSON-lines telemetry at `~/.andromeda/logs/guardian.jsonl` — the visible
/// status surface AGENTS.md demands of every background behavior.
public struct JSONLTelemetrySink: TelemetrySink {
    private static let log = Logger(subsystem: "ai.andromeda.guardian", category: "telemetry")

    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".andromeda/logs/guardian.jsonl")
    }

    public func record(_ report: SweepReport) async {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let line = try encoder.encode(report)
            guard !line.isEmpty else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line + [0x0A])
            } else {
                try (line + [0x0A]).write(to: fileURL, options: .atomic)
            }
        } catch {
            Self.log.error("guardian telemetry write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Composite telemetry: fan one record out to several sinks (JSONL + OSLog
/// is the production pair).
public struct CompositeTelemetrySink: TelemetrySink {
    public let sinks: [any TelemetrySink]

    public init(sinks: [any TelemetrySink]) {
        self.sinks = sinks
    }

    public func record(_ report: SweepReport) async {
        for sink in sinks { await sink.record(report) }
    }
}
