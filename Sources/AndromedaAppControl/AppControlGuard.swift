import Foundation
import HTTPTypes

/**
 * 🎭 The App Control Guard - The Triple Lock
 *
 * "Bearer, content, origin — three locks, one door, no exceptions.
 *  The moat was never a wall; now the wall is a wall."
 *
 * - The Spellbinding Museum Director of App Control
 */

/// Fail-closed request gate for the HUD App Control plane (HAB-866).
///
/// The 127.0.0.1 bind is **not** a security boundary on its own: DNS
/// rebinding lets a foreign page address `attacker-controlled.example`
/// which resolves to 127.0.0.1, and any local process can dial loopback.
/// Every request therefore clears three independent locks:
///
/// 1. **Bearer** — `Authorization: Bearer <token>` with the token minted at
///    arm time and persisted at `~/.andromeda/app-control-token` (0600).
///    Same-machine clients read the file out-of-band; nothing else learns it.
/// 2. **Origin/Host** — a present `Origin` must be a loopback origin
///    (`http://127.0.0.1[:port]`, `http://localhost[:port]`, `[::1]`);
///    `Origin: null` is rejected. `Host` must be a loopback literal with an
///    optional port — foreign Hosts are the DNS-rebinding tell. Absent
///    `Origin` (curl, same-origin tooling) is allowed; absent `Host` is not.
/// 3. **Content-Type** — mutating (`POST /action`) requests must declare
///    `application/json` *before* any body parsing happens.
///
/// Absent or malformed anything is a rejection. Fail closed, always.
public struct AppControlGuard: Sendable {
    /// Why a request was refused. Carries the offending value for the log
    /// line and the error envelope — never the expected token.
    public enum Rejection: Equatable, Sendable {
        /// No `Authorization` header, or not a Bearer scheme.
        case bearerRequired
        /// Bearer scheme presented, token did not match.
        case bearerInvalid
        /// `Origin` present but not a loopback origin (includes `null`).
        case originForbidden(String)
        /// `Host` absent or not a loopback literal.
        case hostForbidden(String)
        /// Body-bearing request without an `application/json` content type.
        case mediaTypeUnsupported(String)
    }

    private let bearerToken: String

    /// - Parameter bearerToken: The secret this guard demands. Empty tokens
    ///   are a programmer error (they would lock the door with a paper key).
    public init(bearerToken: String) {
        precondition(!bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "AppControlGuard requires a non-empty bearer token")
        self.bearerToken = bearerToken
    }

    /// Runs the full gate. Returns `nil` when the request may proceed.
    /// - Parameter headers: The request's header fields.
    /// - Parameter authority: The request's authority — the HTTP/1 `Host`
    ///   header (HTTPTypes surfaces it as `request.head.authority`, not as
    ///   a header field). Foreign authorities are the DNS-rebinding tell.
    /// - Parameter requireJSON: When true (mutating requests), additionally
    ///   demands `Content-Type: application/json` — checked *before* any
    ///   body parsing, so a mislabeled body is never decoded.
    public func authorize(_ headers: HTTPFields, authority: String?, requireJSON: Bool = false) -> Rejection? {
        // Nested Optional switches, not an if-let chain: each lock is an
        // enum (`.some(Rejection)` / `.none`) and fail-closed order is
        // exhaustive at compile time — bearer, then origin, then host,
        // then media when the body exists.
        switch checkBearer(headers) {
        case let .some(rejection):
            return rejection
        case .none:
            switch checkOrigin(headers) {
            case let .some(rejection):
                return rejection
            case .none:
                switch checkHost(authority) {
                case let .some(rejection):
                    return rejection
                case .none:
                    guard requireJSON else { return nil }
                    switch checkMediaType(headers) {
                    case let .some(rejection):
                        return rejection
                    case .none:
                        return nil
                    }
                }
            }
        }
    }

    // MARK: - Locks

    private func checkBearer(_ headers: HTTPFields) -> Rejection? {
        guard
            let authorization = headers[.authorization],
            authorization.lowercased().hasPrefix("bearer ")
        else {
            return .bearerRequired
        }
        let presented = authorization.dropFirst("bearer ".count)
            .trimmingCharacters(in: .whitespaces)
        guard !presented.isEmpty, Self.constantTimeEquals(presented, bearerToken) else {
            return .bearerInvalid
        }
        return nil
    }

    private func checkOrigin(_ headers: HTTPFields) -> Rejection? {
        // No Origin at all: curl and same-origin server-side tooling — the
        // browser-only DNS-rebinding/XSRF vector does not apply. Allowed.
        guard let origin = headers[.origin], !origin.isEmpty else { return nil }
        // "null" comes from sandboxed iframes and opaque origins — hostile.
        guard origin != "null" else { return .originForbidden(origin) }
        guard
            let url = URL(string: origin),
            let host = url.host,
            Self.isLoopbackHost(host)
        else {
            return .originForbidden(origin)
        }
        return nil
    }

    private func checkHost(_ authority: String?) -> Rejection? {
        guard let host = authority, !host.isEmpty else {
            return .hostForbidden("<missing>")
        }
        guard Self.isLoopbackHost(Self.hostWithoutPort(host)) else {
            return .hostForbidden(host)
        }
        return nil
    }

    private func checkMediaType(_ headers: HTTPFields) -> Rejection? {
        let raw = headers[.contentType] ?? ""
        let mediaType = raw
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? ""
        guard mediaType == "application/json" else {
            return .mediaTypeUnsupported(raw.isEmpty ? "<missing>" : raw)
        }
        return nil
    }

    // MARK: - Host parsing

    /// Loopback literals this plane answers to. The bind is 127.0.0.1;
    /// `localhost`/`::1` resolve to it on this machine. Nothing else —
    /// not `127.0.0.2`, not a name an attacker controls.
    public static func isLoopbackHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower.hasPrefix("[") {
            // IPv6 literal — [::1] (the canonical loopback form).
            guard let close = lower.firstIndex(of: "]") else { return false }
            let inner = String(lower[lower.index(after: lower.startIndex)..<close])
            return inner == "::1" || inner == "0:0:0:0:0:0:0:1"
        }
        return lower == "127.0.0.1" || lower == "localhost" || lower == "::1"
    }

    /// Strips a trailing `:port` from a Host header value. Bracketed IPv6
    /// literals (`[::1]:8791`) are unwrapped so the inner literal is judged.
    public static func hostWithoutPort(_ host: String) -> String {
        if host.hasPrefix("[") {
            guard let close = host.firstIndex(of: "]") else { return host }
            return String(host[...close])
        }
        guard let colon = host.lastIndex(of: ":") else { return host }
        let port = host[host.index(after: colon)...]
        guard !port.isEmpty, port.allSatisfy(\.isNumber) else { return host }
        return String(host[host.startIndex..<colon])
    }

    /// Constant-time string equality — no early exit on first mismatching
    /// byte, so token probing cannot read the comparison's timing.
    public static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty && b.isEmpty }
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices {
            difference |= a[index] ^ b[index]
        }
        return difference == 0
    }
}

// MARK: - Token custody

/// Minting and custody of the App Control bearer token (HAB-866).
///
/// The token is random per installation, persisted at
/// `~/.andromeda/app-control-token` with `0600` permissions (directory
/// `0700`). Out-of-band distribution: the loopback HUD client runs as the
/// same user on the same machine and reads the file directly — the token
/// never rides a socket. If the file cannot be read or written, callers
/// should mint an ephemeral token (undiscoverable = fail closed) and log.
public enum AppControlToken {
    /// Directory under the user's home that holds the token file.
    public static let directoryName = ".andromeda"
    /// File name of the persisted token inside that directory.
    public static let fileName = "app-control-token"

    /// Default custody location: `~/.andromeda/app-control-token`.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(directoryName)
            .appendingPathComponent(fileName)
    }

    /// Loads the persisted token, or mints and persists a fresh one.
    /// Tightens an existing file back to `0600` if permissions drifted.
    /// - Returns: The token to hand to `AppControlGuard`.
    public static func loadOrGenerate(at url: URL = defaultURL) throws -> String {
        let fileManager = FileManager.default
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            let token = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                try? fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: url.path
                )
                return token
            }
        }
        let token = generate()
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let wrote = fileManager.createFile(
            atPath: url.path,
            contents: Data(token.utf8),
            attributes: [.posixPermissions: 0o600]
        )
        guard wrote else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSFilePathErrorKey: url.path,
            ])
        }
        return token
    }

    /// Mints a fresh 256-bit token, hex-encoded (64 characters).
    /// `SystemRandomNumberGenerator` is cryptographically secure on Apple
    /// platforms (arc4random-backed).
    public static func generate() -> String {
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        for _ in 0..<32 {
            bytes.append(UInt8.random(in: .min ... .max))
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
