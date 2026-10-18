import Foundation
import Security
import os

/// Named Slack-channels supervisor (`LettaChannels` in Activity Monitor).
///
/// launchd must exec this binary directly. Wrapping it in `/opt/homebrew/bin/node`
/// made every crash look like an anonymous `node` row, and a hardcoded
/// `LETTA_API_KEY` in the old JS launcher 401'd cloud register until the
/// job KeepAlive-looped. This process: read the keychain, spawn letta.js,
/// forward SIGTERM/SIGINT, exit with the child's code.
@main
enum LettaChannels {
    static let logger = Logger(subsystem: "com.binarybros.letta-channels", category: "launcher")

    static func main() {
        do {
            try run()
        } catch {
            logger.error("fatal: \(String(describing: error), privacy: .public)")
            fputs("LettaChannels: \(error)\n", stderr)
            exit(1)
        }
    }

    /// Load the key, spawn the listener, wait. Returning is the child's
    /// lifetime — KeepAlive only restarts us if we actually exit.
    private static func run() throws {
        let apiKey = try Keychain.lettaAPIKey()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: Paths.node)
        child.arguments = [Paths.lettaJS, "server", "--channels", "slack", "--debug"]
        child.currentDirectoryURL = URL(fileURLWithPath: Paths.home)
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = Paths.home
        env["PATH"] = Paths.path
        env["LETTA_API_KEY"] = apiKey
        env["LETTA_DISABLE_CRON_SCHEDULER"] = "1"
        child.environment = env

        // waitUntilExit blocks this thread, so signal sources cannot
        // sit on .main — they would never fire. A side queue is fine.
        let sigQ = DispatchQueue(label: "com.binarybros.letta-channels.signals")
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: sigQ)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: sigQ)
        let stop = {
            if child.isRunning { child.terminate() }
        }
        term.setEventHandler(handler: stop)
        interrupt.setEventHandler(handler: stop)
        term.resume()
        interrupt.resume()

        logger.notice("spawning slack channels listener")
        try child.run()
        // Keep the sources retained across the wait; otherwise ARC
        // drops them and SIGTERM becomes a no-op.
        withExtendedLifetime((term, interrupt)) {
            child.waitUntilExit()
        }
        let code = Int32(child.terminationStatus)
        if code != 0 {
            logger.error("listener exited \(code, privacy: .public)")
        }
        exit(code)
    }
}

/// Keychain lookup is the only credential path. A missing item must fail
/// closed — launchd has no TTY, so falling through to device OAuth opens
/// a browser loop and looks like a healthy KeepAlive restart.
enum Keychain {
    static func lettaAPIKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "letta-code",
            kSecAttrAccount as String: "letta-api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw LaunchError.missingKeychainKey(status)
        }
        guard let key = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !key.isEmpty
        else {
            throw LaunchError.emptyKeychainKey
        }
        return key
    }
}

enum Paths {
    static let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/admin"
    static let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    static let node = "/opt/homebrew/bin/node"
    /// Letta.app unpacked copy — same file the JS launcher used. nvm
    /// paths are session-only and vanish under launchd.
    static let lettaJS = "/Applications/Letta.app/Contents/Resources/app.asar.unpacked/node_modules/@letta-ai/letta-code/letta.js"
}

enum LaunchError: Error, CustomStringConvertible {
    case missingKeychainKey(OSStatus)
    case emptyKeychainKey

    var description: String {
        switch self {
        case .missingKeychainKey(let status):
            return "keychain letta-code/letta-api-key missing (osstatus \(status))"
        case .emptyKeychainKey:
            return "keychain letta-code/letta-api-key was empty"
        }
    }
}
