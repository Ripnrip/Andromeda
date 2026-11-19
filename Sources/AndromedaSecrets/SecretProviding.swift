import Foundation

#if os(macOS) && canImport(Security)
import LocalAuthentication
import Security
#endif

/// Names a secret stored outside the process without carrying its value.
/// Configuration may hold references; never raw secrets.
public struct SecretReference: Sendable, Equatable, Hashable, Codable {
    public let service: String
    public let account: String

    /// Creates an exact service/account reference; neither component is normalized.
    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}

/// Errors surfaced when a secret cannot be resolved. Native backend reasons
/// are fixed safe strings; neither descriptions nor diagnostics contain values.
/// The existing two-case public enum is retained for exhaustive-switch compatibility.
public enum SecretProviderError: Error, Equatable, LocalizedError {
    case notFound(service: String, account: String)
    case backendUnavailable(String)

    /// Presents only the reference or a backend reason, never resolved secret data.
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
    /// Resolves the reference for the current operation without caching its value.
    func secret(for reference: SecretReference) async throws -> String
}

/// Dictionary-backed provider for tests and local development.
public struct InMemorySecretProvider: SecretProviding {
    private let values: [SecretReference: String]

    /// Installs the supplied test/development values without changing their bytes.
    public init(values: [SecretReference: String]) {
        self.values = values
    }

    /// Returns the stored value, preserving existing in-memory provider behavior.
    public func secret(for reference: SecretReference) async throws -> String {
        guard let value = values[reference] else {
            throw SecretProviderError.notFound(service: reference.service, account: reference.account)
        }
        return value
    }
}

/// Resolves exact generic-password references using the macOS Security framework.
/// UI is prohibited. The synchronous native call is dispatched through a bounded
/// blocking lane, never run on Swift's cooperative executor by `secret(for:)`.
/// Values are not cached, logged, persisted, or trimmed.
public struct MacOSKeychainSecretProvider: SecretProviding {
    /// Preserves the existing synchronous injection API. Injected runners remain
    /// trusted code: their returned strings and thrown errors are passed through.
    /// Tests can replace the runner without reading the real Keychain.
    public struct Runner: Sendable {
        public var lookup: @Sendable (_ service: String, _ account: String) throws -> String

        /// Installs a synchronous lookup; the provider supplies bounded offloading.
        public init(lookup: @escaping @Sendable (_ service: String, _ account: String) throws -> String) {
            self.lookup = lookup
        }

        /// Native read-only adapter. Calling `Runner.live.lookup` directly is still
        /// synchronous; callers needing offloading must use the async provider API.
        public static let live = Runner { service, account in
            #if os(macOS) && canImport(Security)
            return try NativeKeychainLookup.lookup(
                service: service, account: account, adapter: .live
            )
            #else
            throw SecretProviderError.backendUnavailable(NativeKeychainLookup.Reason.unsupported.message)
            #endif
        }
    }

    private let runner: Runner
    private let executor: BoundedSecretLookup

    /// Retains source compatibility while sharing one process-wide blocking lane.
    /// Excess admission fails immediately; an admitted caller waits at most five
    /// seconds of dispatch-deadline time, subject to normal scheduling latency.
    public init(runner: Runner = .live) {
        self.runner = runner
        self.executor = BoundedSecretLookup.shared
    }

    /// Internal test-only seam for a private lane; production constructors always
    /// share the one global lane, including providers with injected runners.
    init(runner: Runner, executor: BoundedSecretLookup) {
        self.runner = runner
        self.executor = executor
    }

    /// Resolves on the blocking lane. Cancellation/deadline end caller waiting,
    /// not a running `SecItemCopyMatching`. Its slot remains occupied until return.
    public func secret(for reference: SecretReference) async throws -> String {
        try await executor.lookup(reference: reference, runner: runner)
    }
}

/// Pure request/reply interpretation surrounding the single native read effect.
/// Tests inject `Adapter` and never invoke Security APIs.
enum NativeKeychainLookup {
    /// Carries only exact reference names. Query policy is deliberately closed:
    /// generic password, one match, data only, authentication UI explicitly failing.
    struct Query: Sendable, Equatable {
        let service: String
        let account: String

        /// Builds a reference request without broadening or normalizing matching.
        init(service: String, account: String) {
            self.service = service
            self.account = account
        }
    }

    /// Keeps untrusted CF object kinds out of the Sendable boundary. Unexpected
    /// objects are discarded at the adapter; they are never stringified in errors.
    enum Payload: Sendable {
        case data(Data)
        case missing
        case unexpectedType
    }

    struct Reply: Sendable {
        let status: Int32
        let payload: Payload

        /// Creates a native-status fixture or a reply from the confined C call.
        init(status: Int32, payload: Payload = .missing) {
            self.status = status
            self.payload = payload
        }
    }

    /// Value-based injection keeps the native call and status decoder separable,
    /// like the retained public `Runner` seam, without a dependency container.
    struct Adapter: Sendable {
        let copyMatching: @Sendable (Query) -> Reply

        /// Installs the sole synchronous effect; fixture adapters return pure data.
        init(copyMatching: @escaping @Sendable (Query) -> Reply) {
            self.copyMatching = copyMatching
        }

        #if os(macOS) && canImport(Security)
        /// Calls Security exactly once; CF dictionaries/results never cross tasks.
        static let live = Adapter { query in
            let attributes = NativeKeychainLookup.securityQuery(for: query)
            var result: CFTypeRef?
            let status = SecItemCopyMatching(attributes as CFDictionary, &result)
            guard status == errSecSuccess else {
                // Discard any accompanying result, including canary/secret data.
                return Reply(status: status)
            }
            guard let result else { return Reply(status: status, payload: .missing) }
            guard let data = result as? Data else {
                return Reply(status: status, payload: .unexpectedType)
            }
            return Reply(status: status, payload: .data(data))
        }
        #endif
    }

    /// Security OSStatus values kept portable for pure tests. macOS tests pin them
    /// against SDK constants; unknown/future statuses fail closed, not as missing.
    enum Status: Int32, Sendable, CaseIterable {
        case success = 0
        case itemNotFound = -25300
        case interactionNotAllowed = -25308
        case interactionRequired = -25315
        case authFailed = -25293
        case noAccessForItem = -25243
        case userCanceled = -128
        case missingEntitlement = -34018
        case notAvailable = -25291
        case decode = -26275
        case parameter = -50
    }

    /// Internal classification retains distinct safe outcomes without expanding
    /// the public error enum. No message is derived from native result bytes.
    enum Reason: Sendable {
        case unsupported
        case lockedOrInteractionRequired
        case accessDenied
        case malformedItem
        case unexpectedResult
        case emptyData
        case invalidUTF8
        case unavailable
        case queryRejected
        case unknownStatus

        /// Supplies one fixed diagnostic per outcome; never formats native objects.
        var message: String {
            switch self {
            case .unsupported: "native keychain lookup requires macOS Security framework"
            case .lockedOrInteractionRequired: "keychain locked or interaction required; UI disabled"
            case .accessDenied: "keychain access denied"
            case .malformedItem: "keychain item is malformed"
            case .unexpectedResult: "keychain returned an unexpected data result"
            case .emptyData: "keychain item contains empty data"
            case .invalidUTF8: "keychain item is not valid UTF-8"
            case .unavailable: "keychain is unavailable"
            case .queryRejected: "keychain query rejected"
            case .unknownStatus: "keychain lookup failed"
            }
        }
    }

    /// Performs one injected lookup and then pure status/data interpretation.
    static func lookup(service: String, account: String, adapter: Adapter) throws -> String {
        let query = Query(service: service, account: account)
        return try decode(adapter.copyMatching(query), for: query)
    }

    /// Maps status before touching payload. A no-UI response cannot prove whether
    /// a keychain is locked versus an item requiring interaction; it reports both
    /// honestly, separately from missing and authorization denial.
    static func decode(_ reply: Reply, for query: Query) throws -> String {
        guard let status = Status(rawValue: reply.status) else {
            throw SecretProviderError.backendUnavailable(Reason.unknownStatus.message)
        }
        switch status {
        case .success:
            return try decodeData(reply.payload)
        case .itemNotFound:
            throw SecretProviderError.notFound(service: query.service, account: query.account)
        case .interactionNotAllowed, .interactionRequired:
            throw SecretProviderError.backendUnavailable(Reason.lockedOrInteractionRequired.message)
        case .authFailed, .noAccessForItem, .userCanceled, .missingEntitlement:
            throw SecretProviderError.backendUnavailable(Reason.accessDenied.message)
        case .decode:
            throw SecretProviderError.backendUnavailable(Reason.malformedItem.message)
        case .notAvailable:
            throw SecretProviderError.backendUnavailable(Reason.unavailable.message)
        case .parameter:
            throw SecretProviderError.backendUnavailable(Reason.queryRejected.message)
        }
    }

    /// Requires nonempty data and strict UTF-8. Native reads have no CLI-added
    /// newline: preserve leading/trailing whitespace, CR/LF, and newline-only data.
    /// Empty data is a found-but-unusable item, not a missing reference.
    private static func decodeData(_ payload: Payload) throws -> String {
        guard case let .data(data) = payload else {
            throw SecretProviderError.backendUnavailable(Reason.unexpectedResult.message)
        }
        guard !data.isEmpty else {
            throw SecretProviderError.backendUnavailable(Reason.emptyData.message)
        }
        // The stdlib decoder preserves BOM/NUL bytes on macOS 14. Require an exact
        // UTF-8 round trip so its repair behavior cannot silently alter an invalid
        // credential; valid stored replacement characters remain byte-identical.
        let value = String(decoding: data, as: UTF8.self)
        guard value.utf8.elementsEqual(data) else {
            throw SecretProviderError.backendUnavailable(Reason.invalidUTF8.message)
        }
        return value
    }

    #if os(macOS) && canImport(Security)
    /// Builds the exact six-key, generic-password read query. This function only
    /// constructs a noninteractive context/dictionary; it does not perform authentication or a read.
    /// No search list, prompt, access group, enrollment, or synchronizable policy
    /// is invented by this slice; the process's normal Keychain search scope applies.
    static func securityQuery(for query: Query) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: query.service,
            kSecAttrAccount as String: query.account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
    }
    #endif
}
