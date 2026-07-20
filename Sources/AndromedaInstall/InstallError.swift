import Foundation

/// Fail-closed errors for `andromeda-install`.
public enum InstallError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidTarget(String)
    case missingHome
    case missingRepositoryRoot
    case missingBinary(String)
    case missingPlistTemplate(String)
    case plistTemplateMissingStudioHome(path: String, studioHome: String)
    case commandFailed(executable: String, arguments: [String], exitCode: Int32, stderr: String)
    case kickstartFailed(label: String)
    case unsupportedPlatform(String)

    public var description: String {
        switch self {
        case .invalidTarget(let raw):
            return "Invalid target \(raw.dbg). Require one of: home | hud | both"
        case .missingHome:
            return "HOME is unset; LaunchAgent paths require an absolute home directory"
        case .missingRepositoryRoot:
            return "Could not locate the Andromeda repository root (Package.swift)"
        case .missingBinary(let path):
            return "Release binary missing or not executable: \(path)"
        case .missingPlistTemplate(let path):
            return "LaunchAgent plist template missing: \(path)"
        case .plistTemplateMissingStudioHome(let path, let studioHome):
            return "Plist \(path) is missing Studio home template \(studioHome.dbg)"
        case .commandFailed(let executable, let arguments, let exitCode, let stderr):
            let args = arguments.joined(separator: " ")
            let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if err.isEmpty {
                return "\(executable) \(args) failed with exit \(exitCode)"
            }
            return "\(executable) \(args) failed with exit \(exitCode): \(err)"
        case .kickstartFailed(let label):
            return "launchctl kickstart failed for \(label) (fail-closed; HUD must start under launchd)"
        case .unsupportedPlatform(let detail):
            return "Install mutate requires macOS: \(detail)"
        }
    }
}

private extension String {
    var dbg: String { "\"\(self)\"" }
}
