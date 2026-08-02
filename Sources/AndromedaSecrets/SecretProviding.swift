import Foundation

/// Names a secret stored outside the process (e.g. macOS Keychain) without
/// carrying its value. Configuration may hold references; never raw secrets.
public struct SecretReference: Sendable, Equatable, Hashable, Codable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}

/// Errors surfaced when a secret cannot be resolved. Messages intentionally
/// contain only the *reference* (service/account names) — never secret bytes.
public enum SecretProviderError: Error, Equatable, LocalizedError {
    case notFound(service: String, account: String)
    case backendUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(service, account):
            return "No Keychain secret for service '\(service)' account '\(account)'."
        case let .backendUnavailable(reason):
            return "Secret backend unavailable: \(reason)"
        }
    }
}

/// Resolves secret references to values at call time. Implementations must
/// never log or persist resolved values.
public protocol SecretProviding: Sendable {
    func secret(for reference: SecretReference) async throws -> String
}

/// Dictionary-backed provider for tests and local development.
public struct InMemorySecretProvider: SecretProviding {
    private let values: [SecretReference: String]

    public init(values: [SecretReference: String]) {
        self.values = values
    }

    public func secret(for reference: SecretReference) async throws -> String {
        guard let value = values[reference] else {
            throw SecretProviderError.notFound(service: reference.service, account: reference.account)
        }
        return value
    }
}

/// Resolves secrets from the macOS Keychain via the `security` CLI
/// (`find-generic-password -w`). The lookup runs at call time; resolved values
/// are held only for the duration of a single brokered operation.
public struct MacOSKeychainSecretProvider: SecretProviding {
    /// Injectable command runner so tests can simulate Keychain behavior
    /// without touching the real Keychain.
    public struct Runner: Sendable {
        public var lookup: @Sendable (_ service: String, _ account: String) throws -> String

        public init(lookup: @escaping @Sendable (_ service: String, _ account: String) throws -> String) {
            self.lookup = lookup
        }

        public static let live = Runner { service, account in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                throw SecretProviderError.backendUnavailable("failed to launch /usr/bin/security")
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw SecretProviderError.notFound(service: service, account: account)
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .newlines), !value.isEmpty
            else {
                throw SecretProviderError.notFound(service: service, account: account)
            }
            return value
        }
    }

    private let runner: Runner

    public init(runner: Runner = .live) {
        self.runner = runner
    }

    public func secret(for reference: SecretReference) async throws -> String {
        try runner.lookup(reference.service, reference.account)
    }
}
