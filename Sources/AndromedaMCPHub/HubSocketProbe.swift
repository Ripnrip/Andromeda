import Foundation

#if canImport(Darwin)
    import Darwin
#endif

// MARK: - Socket probe

/// Probes a hub socket pathname by connecting — a stale socket file survives
/// crashes, so existence is not health (Codex P2). A live listener accepts;
/// a dead file refuses.
public enum HubSocketProbe {
    /// Typed probe outcome for one socket path.
    public static func probeListening(path: String) -> ProbeOutcome {
        let expanded = (path as NSString).expandingTildeInPath
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .socketCreationFailed(errno: errno) }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(expanded.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            return .pathTooLong
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            _ = pathBytes.withUnsafeBufferPointer { src in
                memcpy(dest.baseAddress!, src.baseAddress!, pathBytes.count)
            }
        }
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { return .connectFailed(errno: errno) }
        return .listening
    }
}

// MARK: - Probe outcome

/// Why a socket is (not) listening — every failure mode the probe can hit, as
/// a typed value instead of a bare Bool that erases the difference
/// (Q3: honest about cost and failure). Shared by the CLI census and the HUD
/// `memory_health` chain report.
public enum ProbeOutcome: Sendable, Equatable {
    /// connect() accepted — a hub is listening on this path.
    case listening

    /// socket() failed — kernel out of descriptors, etc.
    case socketCreationFailed(errno: Int32)

    /// Path longer than sockaddr_un.sun_path (~104 bytes).
    case pathTooLong

    /// connect() refused — dead/stale socket file, or no hub bound.
    /// errno names which (ECONNREFUSED vs ENOENT vs …).
    case connectFailed(errno: Int32)

    public var isListening: Bool {
        if case .listening = self {
            return true
        }
        return false
    }

    /// Operator-readable refusal reason, or `nil` when listening.
    public var refusalReason: String? {
        switch self {
        case .listening: nil
        case let .socketCreationFailed(errno): "socket() failed (errno \(errno))"
        case .pathTooLong: "path exceeds sun_path capacity"
        case let .connectFailed(errno): "connect refused (errno \(errno))"
        }
    }
}
