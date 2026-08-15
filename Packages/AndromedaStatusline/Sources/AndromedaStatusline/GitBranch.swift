import Foundation

enum GitBranch {
    /// Best-effort current branch. Timeout, missing git, or a detached HEAD → `nil`.
    static func current(in directory: String, timeout: DispatchTimeInterval = .milliseconds(800)) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"]
        process.standardOutput = Pipe()
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        let done = DispatchGroup()
        done.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            done.leave()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0,
              let pipe = process.standardOutput as? Pipe else { return nil }
        let name = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty || name == "HEAD") ? nil : name
    }
}
