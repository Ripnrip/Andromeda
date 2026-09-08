import Foundation

@main
struct AndromedaMCPShim {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        // Server id: --server flag, else derive from our own binary name.
        var serverID: String? = nil
        if let index = args.firstIndex(of: "--server"), index + 1 < args.count {
            serverID = args[index + 1]
        } else {
            serverID = Self.serverIDFromBinaryName(CommandLine.arguments[0])
        }

        guard let serverID, !serverID.isEmpty else {
            FileHandle.standardError.write(
                Data("andromeda-mcp-shim: no server id (--server or binary name)\n".utf8)
            )
            exit(64)
        }

        let socketPath = args.firstIndex(of: "--socket").flatMap { index in
            index + 1 < args.count ? args[index + 1] : nil
        } ?? Self.defaultSocketPath(for: serverID)

        // Connect to the hub.
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, Self.connectToHub(fd: fd, path: socketPath) else {
            FileHandle.standardError.write(
                Data(
                    "andromeda-mcp-shim: cannot connect to hub at \(socketPath) — is com.andromeda.mcp-hub running?\n"
                        .utf8
                )
            )
            exit(69) // EX_UNAVAILABLE
        }

        let hubHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)

        // Stdin (agent host → shim) → hub socket.
        FileHandle.standardInput.readabilityHandler = { stdin in
            let data = stdin.availableData
            if data.isEmpty {
                stdin.readabilityHandler = nil
                try? hubHandle.close()
                exit(0)
            }
            try? hubHandle.write(contentsOf: data)
        }

        // Hub socket → stdout (shim → agent host).
        hubHandle.readabilityHandler = { hub in
            let data = hub.availableData
            if data.isEmpty {
                hub.readabilityHandler = nil
                exit(0)
            }
            try? FileHandle.standardOutput.write(contentsOf: data)
        }

        // Keep the main thread alive — the readability handlers do the work.
        dispatchMain()
    }

    /// `andromeda-mcp-filesystem` → `filesystem` (byte-copy naming, §2.2).
    static func serverIDFromBinaryName(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        guard name.hasPrefix("andromeda-mcp-") else { return nil }
        let id = String(name.dropFirst("andromeda-mcp-".count))
        return id.isEmpty ? nil : id
    }

    static func defaultSocketPath(for serverID: String) -> String {
        NSHomeDirectory() + "/.andromeda/mcp-hub/sockets/\(serverID).sock"
    }

    static func connectToHub(fd: Int32, path: String) -> Bool {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
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
        return result == 0
    }
}
