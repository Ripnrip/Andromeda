import AndromedaHostOps
import Darwin
import Foundation
import os

/// Keeps the Letta Cloud computer listener signed in.
///
/// `letta server` authenticates with an OAuth access token. The desktop
/// daemon treats a 401 as signed-out, and the running listener holds the
/// token in memory, so a refresh that only rewrites settings.json is not
/// enough. This process refreshes on a fixed interval, writes the new grant
/// to `~/.letta/settings.json`, then SIGTERMs the listener so the daemon
/// relaunches it against the new grant.
///
/// Visible fleet contract: LaunchAgent `com.andromeda.letta-oauth-keepalive`,
/// seeded in `LaunchEntityRegistry`, installed only through
/// `LaunchAgentInstaller` (BIN-101). Status lands in os.Logger and a
/// secret-free status file — never the token.
enum LettaOAuthKeepalive {
    static let label = "com.andromeda.letta-oauth-keepalive"
    static let logger = Logger(subsystem: "ai.andromeda.fleet", category: "oauth-keepalive")
    static let refreshInterval: TimeInterval = 2 * 60 * 60
    static let clientID = "ci-let-724dea7e98f4af6f8f370f4b1466200c"
    static let tokenURL = URL(string: "https://app.letta.com/api/oauth/token")!

    static func main() async {
        if CommandLine.arguments.contains("--install") {
            do {
                let report = try await install()
                print(report)
                logger.notice("installed \(Self.label, privacy: .public)")
            } catch {
                logger.error("install failed: \(String(describing: error), privacy: .public)")
                fputs("install failed: \(error)\n", stderr)
                exit(1)
            }
            return
        }

        let once = CommandLine.arguments.contains("--once")
        repeat {
            let result = await refreshAndReload()
            writeStatus(result)
            if once { exit(result.ok ? 0 : 1) }
            try? await Task.sleep(for: .seconds(refreshInterval))
        } while !Task.isCancelled
    }

    struct RefreshResult: Sendable {
        var ok: Bool
        var detail: String
        var expiresInHours: Double?
        var restarted: Int
    }

    /// Refresh the grant and bounce listeners that still hold the old token.
    static func refreshAndReload() async -> RefreshResult {
        do {
            let hours = try await refreshSettings()
            let restarted = restartListeners()
            logger.notice(
                "oauth refreshed expires_in_hours=\(hours, privacy: .public) restarted=\(restarted)"
            )
            return RefreshResult(
                ok: true,
                detail: "refreshed",
                expiresInHours: hours,
                restarted: restarted
            )
        } catch {
            logger.error("oauth refresh failed: \(String(describing: error), privacy: .public)")
            return RefreshResult(ok: false, detail: String(describing: error), expiresInHours: nil, restarted: 0)
        }
    }

    /// POST the refresh grant and persist only the three credential fields.
    static func refreshSettings(home: String = NSHomeDirectory()) async throws -> Double {
        let settingsURL = URL(fileURLWithPath: home).appendingPathComponent(".letta/settings.json")
        let data = try Data(contentsOf: settingsURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KeepaliveError("settings.json is not an object")
        }
        guard let refresh = root["refreshToken"] as? String, !refresh.isEmpty else {
            throw KeepaliveError("no refreshToken in settings.json — one interactive sign-in is required")
        }
        let deviceID = (root["deviceId"] as? String) ?? "studio"
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refresh,
            "refresh_token_mode": "new",
            "device_id": deviceID,
            "device_name": Host.current().localizedName ?? "studio",
        ])
        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KeepaliveError("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String
            throw KeepaliveError("oauth HTTP \(http.statusCode) \(code ?? "no-code")")
        }
        guard let tokens = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let access = tokens["access_token"] as? String,
              let expiresIn = tokens["expires_in"] as? Double ?? (tokens["expires_in"] as? Int).map(Double.init)
        else {
            throw KeepaliveError("oauth response missing access_token or expires_in")
        }
        var env = root["env"] as? [String: Any] ?? [:]
        env["LETTA_API_KEY"] = access
        root["env"] = env
        root["refreshToken"] = (tokens["refresh_token"] as? String) ?? refresh
        root["tokenExpiresAt"] = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000
        let encoded = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let backup = settingsURL.appendingPathExtension("bak-oauth-keepalive")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        let tmp = settingsURL.appendingPathExtension("tmp")
        try encoded.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(settingsURL, withItemAt: tmp)
        return expiresIn / 3600
    }

    /// SIGTERM listener processes so the desktop daemon relaunches them
    /// against the grant just written. Skips this process.
    static func restartListeners() -> Int {
        let me = ProcessInfo.processInfo.processIdentifier
        var restarted = 0
        for pid in listenerPIDs() where pid != me {
            if kill(pid, SIGTERM) == 0 {
                restarted += 1
                logger.notice("signaled listener pid=\(pid) to reload oauth grant")
            }
        }
        return restarted
    }

    static func listenerPIDs() -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Drain before waitUntilExit. The reverse deadlocks when ps
            // output exceeds the pipe buffer (Andromeda PR #67 class).
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.split(separator: "\n").compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let space = trimmed.firstIndex(of: " ") else { return nil }
                let command = String(trimmed[trimmed.index(after: space)...])
                let isServer = command.contains("letta.js server") || command.contains("letta server")
                guard isServer, !command.contains("LettaOAuthKeepalive") else { return nil }
                return pid_t(trimmed[..<space].trimmingCharacters(in: .whitespaces))
            }
        } catch {
            logger.error("ps failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    static func writeStatus(_ result: RefreshResult) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".letta/logs/letta-oauth-keepalive.status")
        let payload: [String: Any] = [
            "ok": result.ok,
            "detail": result.detail,
            "expiresInHours": result.expiresInHours ?? -1,
            "restartedListeners": result.restarted,
            "at": ISO8601DateFormatter().string(from: Date()),
            "label": label,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Copy this binary into ~/.local/bin and bootstrap the LaunchAgent
    /// through AndromedaHostOps. No shell, no hidden plist write.
    static func install() async throws -> String {
        let home = NSHomeDirectory()
        let destBin = URL(fileURLWithPath: home).appendingPathComponent(".local/bin/LettaOAuthKeepalive")
        let sourceBin = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let binaryReport = try await BinaryInstaller().install(source: sourceBin, destination: destBin)
        let template = plistTemplate()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(label).plist")
        try template.write(to: tmp, atomically: true, encoding: .utf8)
        let destPlist = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
        let spec = LaunchAgentInstaller.Spec(
            label: label,
            home: home,
            uid: UInt32(getuid()),
            bootstrap: true,
            kickstart: false
        )
        let report = try await LaunchAgentInstaller().install(source: tmp, destination: destPlist, spec: spec)
        return "\(binaryReport)\n\(report)"
    }

    static func plistTemplate() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Users/<user>/.local/bin/LettaOAuthKeepalive</string>
            </array>
            <key>WorkingDirectory</key>
            <string>/Users/<user></string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
            <key>StandardOutPath</key>
            <string>/Users/<user>/.letta/logs/letta-oauth-keepalive.out.log</string>
            <key>StandardErrorPath</key>
            <string>/Users/<user>/.letta/logs/letta-oauth-keepalive.err.log</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>HOME</key>
                <string>/Users/<user></string>
            </dict>
        </dict>
        </plist>
        """
    }
}

struct KeepaliveError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
struct Main {
    static func main() async {
        await LettaOAuthKeepalive.main()
    }
}
