import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Failure modes of acquiring the proof-state transaction lock.
public enum ProofStateLockError: Error, Equatable, Sendable {
    /// `open(2)` on the lock file failed.
    case openFailed(path: String, errno: Int32)
    /// `flock(2)` failed after a successful open.
    case flockFailed(path: String, errno: Int32)
}

/// Cross-process advisory lock serializing proof-state read-merge-write
/// transactions (PR #91 review, P1-1: an unlocked load→merge→save can lose a
/// concurrently-written leg).
///
/// `flock(2)` on a lock file beside the proof document. The kernel releases the
/// lock when the owning fd closes — including on process death — so a crashed
/// writer cannot leave a stale lock behind (the failure mode an O_EXCL
/// create-and-check protocol has to recover from). Two writers in the same
/// process also serialize correctly: each `acquire` opens its own fd, and
/// `flock` locks are per open-file-description, not per process.
///
/// The critical section is synchronous file IO only — never `await` while
/// holding the lock, or a blocked cooperative thread could stall the owner.
public final class CrossProcessFileLock: @unchecked Sendable {
    private let fd: Int32
    private let path: String

    /// Creates `lockFilePath` (and its parent directory) if needed, then blocks
    /// until an exclusive lock is held. Returns a handle whose `deinit` drops
    /// the lock.
    public static func acquire(lockFilePath: String) throws -> CrossProcessFileLock {
        let expanded = (lockFilePath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fd = open(expanded, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            throw ProofStateLockError.openFailed(path: expanded, errno: errno)
        }
        guard flock(fd, LOCK_EX) == 0 else {
            let code = errno
            close(fd)
            throw ProofStateLockError.flockFailed(path: expanded, errno: code)
        }
        return CrossProcessFileLock(fd: fd, path: expanded)
    }

    private init(fd: Int32, path: String) {
        self.fd = fd
        self.path = path
    }

    /// Explicit release; closing the fd also drops the lock (deinit does it).
    public func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
    }

    deinit {
        guard fd >= 0 else { return }
        close(fd)
    }

    /// Path of the lock file this handle owns (diagnostics).
    public var lockFilePath: String { path }
}

extension ProofStateLockError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .openFailed(path, errno):
            "proof-state lock open failed at \(path) (errno \(errno))"
        case let .flockFailed(path, errno):
            "proof-state lock flock failed at \(path) (errno \(errno))"
        }
    }
}
