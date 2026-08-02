import AndromedaSecrets
import Foundation

/// Checks Keychain presence without printing or returning secret bytes.
public struct KeychainPresenceChecker: Sendable {
    public struct Runner: Sendable {
        public var exists: @Sendable (_ service: String, _ account: String) -> Bool

        public init(exists: @escaping @Sendable (_ service: String, _ account: String) -> Bool) {
            self.exists = exists
        }

        /// Uses `security find-generic-password` without `-w` so the password is never emitted.
        public static let live = Runner { service, account in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", service, "-a", account]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return false
            }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }
    }

    private let runner: Runner

    public init(runner: Runner = .live) {
        self.runner = runner
    }

    /// Returns whether the reference exists. Never resolves the secret value.
    public func isPresent(_ reference: SecretReference) -> Bool {
        runner.exists(reference.service, reference.account)
    }
}

/// Seeds Keychain generic passwords from already-held strings (caller must not log them).
public struct KeychainSeeder: Sendable {
    public struct Runner: Sendable {
        public var write: @Sendable (_ service: String, _ account: String, _ secret: String) throws -> Void

        public init(write: @escaping @Sendable (_ service: String, _ account: String, _ secret: String) throws -> Void) {
            self.write = write
        }

        public static let live = Runner { service, account, secret in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            // -U updates if present (idempotent). Password is passed as argv; this is
            // host-local and short-lived — never printed by Andromeda.
            process.arguments = [
                "add-generic-password", "-U",
                "-s", service,
                "-a", account,
                "-w", secret,
            ]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                throw HostOpsError.keychainWriteFailed("failed to launch /usr/bin/security")
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw HostOpsError.keychainWriteFailed(
                    "security exited \(process.terminationStatus) for \(service)/\(account)"
                )
            }
        }
    }

    private let runner: Runner

    public init(runner: Runner = .live) {
        self.runner = runner
    }

    /// Writes or updates a Keychain item. Does not log the secret.
    public func upsert(reference: SecretReference, secret: String) throws {
        guard !secret.isEmpty else {
            throw HostOpsError.keychainWriteFailed("refusing empty secret for \(reference.service)/\(reference.account)")
        }
        try runner.write(reference.service, reference.account, secret)
    }
}
