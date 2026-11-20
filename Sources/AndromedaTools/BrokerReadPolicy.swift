/// Stable read-only capability identifiers, without legacy names or write variants.
public enum BrokerReadCapability: String, Sendable, CaseIterable, Hashable {
    case repository = "github_proxy"
    case conversation = "slack_proxy"
}

/// Immutable grants supplied by trusted host integration, not caller authentication.
public struct BrokerReadPrincipal: Sendable, Hashable {
    public let id: BrokerReadPrincipalID
    public let repositories: Set<BrokerRepositoryReference>
    public let channels: Set<BrokerChannelReference>

    /// Bounds each host-approved resource set independently before retaining grants.
    public init(
        id: BrokerReadPrincipalID,
        repositories: Set<BrokerRepositoryReference> = [],
        channels: Set<BrokerChannelReference> = []
    ) throws {
        guard repositories.count <= 128, channels.count <= 128 else {
            throw BrokerReadPolicyError.tooManyResources
        }
        self.id = id
        self.repositories = repositories
        self.channels = channels
    }
}

/// Finite read intent only; channel history has no cursor and reads its first page.
public enum BrokerReadRequest: Sendable, Equatable, Hashable {
    case repositoryMetadata(BrokerRepositoryReference)
    case repositoryIssues(BrokerRepositoryReference, page: BrokerReadPage)
    case repositoryIssue(BrokerRepositoryReference, number: BrokerIssueNumber)
    case channelMetadata(BrokerChannelReference)
    case channelHistory(BrokerChannelReference, limit: BrokerReadLimit)

    /// Maps every supported operation to its stable capability exhaustively.
    public var capability: BrokerReadCapability {
        switch self {
        case .repositoryMetadata, .repositoryIssues, .repositoryIssue:
            return .repository
        case .channelMetadata, .channelHistory:
            return .conversation
        }
    }
}

/// Host-grant authorization only, not a credential or downstream permission proof.
public struct AuthorizedBrokerRead: Sendable, Equatable, Hashable {
    public let principalID: BrokerReadPrincipalID
    public let request: BrokerReadRequest

    /// Derives the authorized capability from the immutable request's finite scope.
    public var capability: BrokerReadCapability {
        request.capability
    }

    /// Restricts construction to this policy file after host-grant authorization.
    fileprivate init(principalID: BrokerReadPrincipalID, request: BrokerReadRequest) {
        self.principalID = principalID
        self.request = request
    }
}

/// Unwired pure authorization core; existing broker routes remain unchanged.
public enum BrokerReadPolicy {
    /// Lists only granted scopes in deterministic repository-then-conversation order.
    public static func listCapabilities(
        for principal: BrokerReadPrincipal
    ) -> [BrokerReadCapability] {
        let repository: [BrokerReadCapability] = principal.repositories.isEmpty ? [] : [.repository]
        let conversation: [BrokerReadCapability] = principal.channels.isEmpty ? [] : [.conversation]
        return repository + conversation
    }

    /// Requires a nonempty capability grant and exact membership of its typed resource.
    public static func authorize(
        _ request: BrokerReadRequest,
        for principal: BrokerReadPrincipal
    ) throws -> AuthorizedBrokerRead {
        switch request {
        case .repositoryMetadata(let repository),
            .repositoryIssues(let repository, page: _),
            .repositoryIssue(let repository, number: _):
            guard !principal.repositories.isEmpty else {
                throw BrokerReadPolicyError.capabilityDenied
            }
            guard principal.repositories.contains(repository) else {
                throw BrokerReadPolicyError.resourceDenied
            }
        case .channelMetadata(let channel), .channelHistory(let channel, limit: _):
            guard !principal.channels.isEmpty else {
                throw BrokerReadPolicyError.capabilityDenied
            }
            guard principal.channels.contains(channel) else {
                throw BrokerReadPolicyError.resourceDenied
            }
        }
        return AuthorizedBrokerRead(principalID: principal.id, request: request)
    }
}
