import Foundation

/// Buffers bytes and yields complete newline-terminated frames.
public final class LineAssembler: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    public init() {}

    /// Feed one chunk; returns the complete lines it completed (CR stripped).
    public func append(_ data: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var line = buffer[..<newlineIndex]
            if line.last == 0x0D {
                line = line.dropLast()
            }
            if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])
        }
        return lines
    }

    /// Bytes buffered awaiting a terminator (diagnostics).
    public var pendingByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }
}

/// Lock-guarded byte counter for drain handlers (Swift 6 capture-safe).
final class ByteTally: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add(_ n: Int) {
        lock.lock()
        count += n
        lock.unlock()
    }
}
