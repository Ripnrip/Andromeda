/// Payload-free failures for reference validation and read authorization.
public enum BrokerReadPolicyError: Error, Sendable, Equatable, Hashable {
    case invalidPrincipal
    case invalidRepository
    case invalidChannel
    case invalidLimit
    case invalidPage
    case invalidIssueNumber
    case tooManyResources
    case capabilityDenied
    case resourceDenied
}

/// A case-sensitive identifier supplied by trusted host principal binding.
public struct BrokerReadPrincipalID: Sendable, Hashable {
    public let rawValue: String

    /// Validates a bounded ASCII identifier without normalizing its identity.
    public init(_ rawValue: String) throws {
        let bytes = try brokerReadBoundedASCIIBytes(
            rawValue, maximumLength: 64, error: .invalidPrincipal
        )
        guard let first = bytes.first,
            brokerReadIsASCIIAlphanumeric(first),
            bytes.allSatisfy({
                brokerReadIsASCIIAlphanumeric($0) || $0 == 95 || $0 == 45 || $0 == 46
            })
        else {
            throw BrokerReadPolicyError.invalidPrincipal
        }
        self.rawValue = String(decoding: bytes, as: UTF8.self)
    }
}

/// A validated repository reference with ASCII-lowercased canonical identity.
public struct BrokerRepositoryReference: Sendable, Hashable {
    public let owner: String
    public let name: String

    /// Bounds and validates both components before canonicalizing ASCII case.
    public init(owner: String, name: String) throws {
        let ownerBytes = try brokerReadBoundedASCIIBytes(
            owner, maximumLength: 39, error: .invalidRepository
        )
        let nameBytes = try brokerReadBoundedASCIIBytes(
            name, maximumLength: 100, error: .invalidRepository
        )
        guard let first = ownerBytes.first,
            let last = ownerBytes.last,
            brokerReadIsASCIIAlphanumeric(first),
            brokerReadIsASCIIAlphanumeric(last),
            ownerBytes.allSatisfy({ brokerReadIsASCIIAlphanumeric($0) || $0 == 45 }),
            nameBytes.allSatisfy({
                brokerReadIsASCIIAlphanumeric($0) || $0 == 95 || $0 == 45 || $0 == 46
            }),
            nameBytes != [46],
            nameBytes != [46, 46]
        else {
            throw BrokerReadPolicyError.invalidRepository
        }
        self.owner = brokerReadLowercasedASCII(ownerBytes)
        self.name = brokerReadLowercasedASCII(nameBytes)
    }
}

/// A case-sensitive channel reference; shape does not prove provider permission.
public struct BrokerChannelReference: Sendable, Hashable {
    public let rawValue: String

    /// Accepts only bounded uppercase ASCII channel shapes beginning with C or G.
    public init(_ rawValue: String) throws {
        let bytes = try brokerReadBoundedASCIIBytes(
            rawValue, maximumLength: 64, error: .invalidChannel
        )
        guard bytes.count >= 2,
            let first = bytes.first,
            first == 67 || first == 71,
            bytes.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) })
        else {
            throw BrokerReadPolicyError.invalidChannel
        }
        self.rawValue = String(decoding: bytes, as: UTF8.self)
    }
}

/// A finite read size with no unbounded or provider-specific parameter surface.
public struct BrokerReadLimit: Sendable, Hashable {
    public let value: Int
    public static let standard = BrokerReadLimit(validatedValue: 30)

    /// Rejects read sizes outside the inclusive range 1 through 100.
    public init(_ value: Int) throws {
        guard (1...100).contains(value) else {
            throw BrokerReadPolicyError.invalidLimit
        }
        self.value = value
    }

    /// Constructs the private, known-valid standard constant without forced tries.
    private init(validatedValue value: Int) {
        self.value = value
    }
}

/// One explicitly requested issue page; this value never triggers pagination.
public struct BrokerReadPage: Sendable, Hashable {
    public let number: Int
    public let limit: BrokerReadLimit
    public static let first = BrokerReadPage(validatedNumber: 1, limit: .standard)

    /// Rejects page numbers outside 1 through 10 while preserving the typed limit.
    public init(number: Int, limit: BrokerReadLimit = .standard) throws {
        guard (1...10).contains(number) else {
            throw BrokerReadPolicyError.invalidPage
        }
        self.number = number
        self.limit = limit
    }

    /// Constructs the private, known-valid first-page constant without forced tries.
    private init(validatedNumber number: Int, limit: BrokerReadLimit) {
        self.number = number
        self.limit = limit
    }
}

/// A positive issue number bounded independently of the platform's Int width.
public struct BrokerIssueNumber: Sendable, Hashable {
    public let value: Int

    /// Rejects issue numbers outside the inclusive range 1 through 2_147_483_647.
    public init(_ value: Int) throws {
        guard (1...2_147_483_647).contains(value) else {
            throw BrokerReadPolicyError.invalidIssueNumber
        }
        self.value = value
    }
}

/// Materializes at most the configured byte bound plus one before ASCII validation.
private func brokerReadBoundedASCIIBytes(
    _ rawValue: String,
    maximumLength: Int,
    error: BrokerReadPolicyError
) throws -> [UInt8] {
    let bytes = Array(rawValue.utf8.prefix(maximumLength + 1))
    guard !bytes.isEmpty,
        bytes.count <= maximumLength,
        bytes.allSatisfy({ $0 < 128 })
    else {
        throw error
    }
    return bytes
}

/// Tests only the ASCII digit and letter ranges used by identifier grammars.
private func brokerReadIsASCIIAlphanumeric(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
}

/// Lowercases already bounded, validated ASCII bytes without Unicode normalization.
private func brokerReadLowercasedASCII(_ bytes: [UInt8]) -> String {
    let lowercased = bytes.map { byte in
        (65...90).contains(byte) ? byte + 32 : byte
    }
    return String(decoding: lowercased, as: UTF8.self)
}
