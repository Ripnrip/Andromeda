import Testing

@testable import AndromedaTools

/// Exercises only the pure read-policy contract; fixtures imply no live resource or provider permission.
@Suite("Broker read policy frozen contract")
struct BrokerReadPolicyTests {
    /// Metadata approval preserves the trusted principal and the exact typed repository intent.
    @Test
    func approvesRepositoryMetadata() throws {
        let fixture = try approvedFixture()
        try expectApproval(.repositoryMetadata(fixture.repository), for: fixture.principal)
    }

    /// Issue-list approval preserves the explicit final allowed page and maximum bounded limit.
    @Test
    func approvesRepositoryIssues() throws {
        let fixture = try approvedFixture()
        let limit = try BrokerReadLimit(100)
        let page = try BrokerReadPage(number: 10, limit: limit)
        let request = BrokerReadRequest.repositoryIssues(fixture.repository, page: page)
        try expectApproval(request, for: fixture.principal)
    }

    /// Single-issue approval preserves the largest supported issue number rather than changing it.
    @Test
    func approvesRepositoryIssue() throws {
        let fixture = try approvedFixture()
        let number = try BrokerIssueNumber(2_147_483_647)
        let request = BrokerReadRequest.repositoryIssue(fixture.repository, number: number)
        try expectApproval(request, for: fixture.principal)
    }

    /// Channel metadata approval requires an exact synthetic channel grant and returns read intent only.
    @Test
    func approvesChannelMetadata() throws {
        let fixture = try approvedFixture()
        try expectApproval(.channelMetadata(fixture.channel), for: fixture.principal)
    }

    /// First-page history approval preserves its bounded limit without introducing cursor parameters.
    @Test
    func approvesChannelHistory() throws {
        let fixture = try approvedFixture()
        let limit = try BrokerReadLimit(100)
        let request = BrokerReadRequest.channelHistory(fixture.channel, limit: limit)
        try expectApproval(request, for: fixture.principal)
    }

    /// Every request maps to exactly its read capability, independently of any principal or grants.
    @Test
    func mapsAllFiveRequestsToTheirCapabilities() throws {
        let fixture = try approvedFixture()
        let repositoryOperations = try repositoryRequests(for: fixture.repository)
        let channelOperations = channelRequests(for: fixture.channel)
        #expect(repositoryOperations.count == 3)
        #expect(channelOperations.count == 2)
        for request in repositoryOperations {
            #expect(request.capability == .repository)
        }
        for request in channelOperations {
            #expect(request.capability == .conversation)
        }
    }

    /// All four grant combinations have explicit menus and identical scope for authorization of all five reads.
    @Test
    func listingAndAuthorizationHaveEquivalentCapabilityScope() throws {
        let fixture = try approvedFixture()
        let scopes: [
            (
                repositories: Set<BrokerRepositoryReference>,
                channels: Set<BrokerChannelReference>,
                expected: [BrokerReadCapability]
            )
        ] = [
            ([], [], []),
            ([fixture.repository], [], [.repository]),
            ([], [fixture.channel], [.conversation]),
            ([fixture.repository], [fixture.channel], [.repository, .conversation]),
        ]
        let requests = try allRequests(repository: fixture.repository, channel: fixture.channel)
        for scope in scopes {
            let principal = try BrokerReadPrincipal(
                id: fixture.principal.id,
                repositories: scope.repositories,
                channels: scope.channels
            )
            let listed = BrokerReadPolicy.listCapabilities(for: principal)
            #expect(listed == scope.expected)
            #expect(BrokerReadPolicy.listCapabilities(for: principal) == listed)
            for request in requests {
                if scope.expected.contains(request.capability) {
                    let authorized = try BrokerReadPolicy.authorize(request, for: principal)
                    #expect(listed.contains(authorized.capability))
                    #expect(authorized.principalID == principal.id)
                    #expect(authorized.request == request)
                } else {
                    #expect(throws: BrokerReadPolicyError.capabilityDenied) {
                        try BrokerReadPolicy.authorize(request, for: principal)
                    }
                }
            }
        }
    }

    /// Default grants remain empty; role-like, write-like, and automation-like IDs never confer access.
    @Test(arguments: [
        "Reader.Default", "admin", "root", "automation", "automationAllowed",
        "github_proxy", "slack_proxy", "write", "github_proxy.write",
    ])
    func defaultGrantsHaveNoPrivilegedIdentityEscape(_ rawID: String) throws {
        let fixture = try approvedFixture()
        let principal = try BrokerReadPrincipal(id: BrokerReadPrincipalID(rawID))
        #expect(principal.repositories.isEmpty)
        #expect(principal.channels.isEmpty)
        #expect(BrokerReadPolicy.listCapabilities(for: principal).isEmpty)
        for request in try allRequests(repository: fixture.repository, channel: fixture.channel) {
            #expect(throws: BrokerReadPolicyError.capabilityDenied) {
                try BrokerReadPolicy.authorize(request, for: principal)
            }
        }
    }

    /// A populated capability is not global access: every unlisted repository or channel is resourceDenied.
    @Test
    func nonemptyGrantsDoNotAuthorizeUnlistedResources() throws {
        let fixture = try approvedFixture()
        let repositories = [
            try BrokerRepositoryReference(owner: fixture.repository.owner, name: "another-repo"),
            try BrokerRepositoryReference(owner: "another-owner", name: fixture.repository.name),
            try BrokerRepositoryReference(owner: "another-owner", name: "another-repo"),
        ]
        let channels = [
            try BrokerChannelReference("CSYNTHETIC2"),
            try BrokerChannelReference("GSYNTHETIC1"),
        ]
        #expect(BrokerReadPolicy.listCapabilities(for: fixture.principal) == [.repository, .conversation])
        for repository in repositories {
            for request in try repositoryRequests(for: repository) {
                #expect(throws: BrokerReadPolicyError.resourceDenied) {
                    try BrokerReadPolicy.authorize(request, for: fixture.principal)
                }
            }
        }
        for channel in channels {
            for request in channelRequests(for: channel) {
                #expect(throws: BrokerReadPolicyError.resourceDenied) {
                    try BrokerReadPolicy.authorize(request, for: fixture.principal)
                }
            }
        }
    }

    /// Disjoint trusted principals cannot borrow one another's grants in either direction for any operation.
    @Test
    func rejectsCrossPrincipalRepositoryAndChannelReads() throws {
        let first = try approvedFixture()
        let secondRepository = try BrokerRepositoryReference(owner: "other-synthetic", name: "other-read")
        let secondChannel = try BrokerChannelReference("GOTHERSYNTHETIC1")
        let second = try BrokerReadPrincipal(
            id: BrokerReadPrincipalID("Reader.Other-2"),
            repositories: [secondRepository],
            channels: [secondChannel]
        )
        let firstRequests = try allRequests(repository: first.repository, channel: first.channel)
        let secondRequests = try allRequests(repository: secondRepository, channel: secondChannel)
        for request in firstRequests {
            try expectApproval(request, for: first.principal)
            #expect(throws: BrokerReadPolicyError.resourceDenied) {
                try BrokerReadPolicy.authorize(request, for: second)
            }
        }
        for request in secondRequests {
            try expectApproval(request, for: second)
            #expect(throws: BrokerReadPolicyError.resourceDenied) {
                try BrokerReadPolicy.authorize(request, for: first.principal)
            }
        }
    }

    /// A matching principal ID is not a hidden grant lookup: only the supplied trusted value provides scope.
    @Test
    func equalPrincipalIDsDoNotTransferGrants() throws {
        let fixture = try approvedFixture()
        let ungranted = try BrokerReadPrincipal(id: fixture.principal.id)
        #expect(ungranted.id == fixture.principal.id)
        #expect(BrokerReadPolicy.listCapabilities(for: ungranted).isEmpty)
        for request in try allRequests(repository: fixture.repository, channel: fixture.channel) {
            try expectApproval(request, for: fixture.principal)
            #expect(throws: BrokerReadPolicyError.capabilityDenied) {
                try BrokerReadPolicy.authorize(request, for: ungranted)
            }
        }
    }

    /// Repository owner/name case is canonicalized before equality, hashing, and grant membership checks.
    @Test
    func canonicalRepositoryCaseAuthorizesAllRepositoryOperations() throws {
        let lower = try BrokerRepositoryReference(owner: "synthetic-lab", name: "read.tests")
        let upper = try BrokerRepositoryReference(owner: "SYNTHETIC-LAB", name: "READ.TESTS")
        let mixed = try BrokerRepositoryReference(owner: "Synthetic-Lab", name: "Read.Tests")
        #expect(upper.owner == "synthetic-lab")
        #expect(upper.name == "read.tests")
        #expect(mixed == lower)
        #expect(upper == lower)
        #expect(Set([lower, upper, mixed]).count == 1)
        let principal = try BrokerReadPrincipal(
            id: BrokerReadPrincipalID("Reader.Case"),
            repositories: [upper]
        )
        #expect(principal.repositories.contains(lower))
        #expect(BrokerReadPolicy.listCapabilities(for: principal) == [.repository])
        for repository in [lower, upper, mixed] {
            for request in try repositoryRequests(for: repository) {
                try expectApproval(request, for: principal)
            }
        }
    }

    /// Principal identities preserve case and remain distinct even when their resource grants are identical.
    @Test
    func principalCaseIsExactAndPreservedInAuthorization() throws {
        let fixture = try approvedFixture()
        let upperID = try BrokerReadPrincipalID("Reader.Case-1")
        let lowerID = try BrokerReadPrincipalID("reader.case-1")
        #expect(upperID.rawValue == "Reader.Case-1")
        #expect(lowerID.rawValue == "reader.case-1")
        #expect(upperID != lowerID)
        #expect(Set([upperID, lowerID]).count == 2)
        let upper = try BrokerReadPrincipal(id: upperID, repositories: [fixture.repository])
        let lower = try BrokerReadPrincipal(id: lowerID, repositories: [fixture.repository])
        let request = BrokerReadRequest.repositoryMetadata(fixture.repository)
        let upperResult = try BrokerReadPolicy.authorize(request, for: upper)
        let lowerResult = try BrokerReadPolicy.authorize(request, for: lower)
        #expect(upperResult.principalID == upperID)
        #expect(lowerResult.principalID == lowerID)
        #expect(upperResult != lowerResult)
    }

    /// Channels preserve exact uppercase IDs, reject lowercase input, and never conflate C and G prefixes.
    @Test
    func channelIDsHaveExactIdentityRatherThanRepositoryCanonicalization() throws {
        let channel = try BrokerChannelReference("CSYNTHETIC1")
        let same = try BrokerChannelReference("CSYNTHETIC1")
        let other = try BrokerChannelReference("GSYNTHETIC1")
        #expect(channel.rawValue == "CSYNTHETIC1")
        #expect(channel == same)
        #expect(channel != other)
        #expect(Set([channel, same, other]).count == 2)
        #expect(throws: BrokerReadPolicyError.invalidChannel) {
            try BrokerChannelReference("csynthetic1")
        }
        let principal = try BrokerReadPrincipal(id: BrokerReadPrincipalID("Reader.Channel"), channels: [channel])
        for request in channelRequests(for: channel) {
            try expectApproval(request, for: principal)
        }
        for request in channelRequests(for: other) {
            #expect(throws: BrokerReadPolicyError.resourceDenied) {
                try BrokerReadPolicy.authorize(request, for: principal)
            }
        }
    }

    /// Valid principal grammar includes single alphanumerics and permitted noninitial punctuation, without trimming.
    @Test(arguments: ["a", "Z", "0", "A_b-c.d", "a_", "a-", "a."])
    func acceptsPrincipalGrammarExactly(_ raw: String) throws {
        #expect(try BrokerReadPrincipalID(raw).rawValue == raw)
    }

    /// Invalid principal grammar rejects empty values, nonalphanumeric starts, separators, wildcards, and spaces.
    @Test(arguments: ["", "_a", "-a", ".a", "*", "a*b", "a/b", "a\\b", "a:b", " a", "a ", "a b"])
    func rejectsInvalidPrincipalGrammar(_ raw: String) {
        #expect(throws: BrokerReadPolicyError.invalidPrincipal) {
            try BrokerReadPrincipalID(raw)
        }
    }

    /// Owner endpoints must be alphanumeric; interior hyphens and ASCII case canonicalization remain valid.
    @Test(arguments: ["a", "Z", "0", "Synthetic-Lab", "a--b", "1-2"])
    func acceptsRepositoryOwnerGrammar(_ raw: String) throws {
        let repository = try BrokerRepositoryReference(owner: raw, name: "synthetic")
        #expect(repository.owner == raw.lowercased())
    }

    /// Owners reject traversal, separators, invalid endpoints, punctuation, wildcards, and whitespace without repair.
    @Test(arguments: ["", "-a", "a-", "_a", "a_b", "a.b", ".", "..", "../a", "a/..", "a\\b", "a/b", "*", "a*b", " a", "a ", "a b"])
    func rejectsInvalidRepositoryOwnerGrammar(_ raw: String) {
        #expect(throws: BrokerReadPolicyError.invalidRepository) {
            try BrokerRepositoryReference(owner: raw, name: "synthetic")
        }
    }

    /// Names accept the full specified punctuation grammar; harmless dot-containing names are not over-rejected.
    @Test(arguments: ["a", "Z", "0", "Read.Tests", "_", "-", "...", ".hidden", "synthetic.", "a..b", "a_-b"])
    func acceptsRepositoryNameGrammar(_ raw: String) throws {
        let repository = try BrokerRepositoryReference(owner: "synthetic", name: raw)
        #expect(repository.name == raw.lowercased())
    }

    /// Names reject dot traversal, path separators, wildcards, and whitespace instead of normalizing hostile paths.
    @Test(arguments: ["", ".", "..", "../synthetic", "synthetic/..", "..\\synthetic", "synthetic\\..", "a/b", "a\\b", "a:b", "*", "a*b", " synthetic", "synthetic ", "a b"])
    func rejectsInvalidRepositoryNameGrammar(_ raw: String) {
        #expect(throws: BrokerReadPolicyError.invalidRepository) {
            try BrokerRepositoryReference(owner: "synthetic", name: raw)
        }
    }

    /// Both C and G syntactic channel prefixes accept uppercase letters/digits without claiming provider existence.
    @Test(arguments: ["C0", "G0", "CA", "GZ", "CSYNTHETIC123", "G9SYNTHETIC"])
    func acceptsChannelGrammar(_ raw: String) throws {
        #expect(try BrokerChannelReference(raw).rawValue == raw)
    }

    /// Channels reject D/direct-message shapes, lowercase, punctuation, separators, wildcards, and whitespace.
    @Test(arguments: ["", "C", "G", "D0", "DSYNTHETIC", "A0", "0C", "c0", "g0", "Ca", "C_a", "C-A", "C.A", "C/A", "C\\A", "C*", " C0", "C0 ", "C A"])
    func rejectsInvalidChannelGrammar(_ raw: String) {
        #expect(throws: BrokerReadPolicyError.invalidChannel) {
            try BrokerChannelReference(raw)
        }
    }

    /// Percent-encoded and doubly encoded traversal/separators are rejected literally by every reference boundary.
    @Test(arguments: ["%", "%2f", "%2F", "%5c", "%5C", "%2e%2e", "%2E%2E", "%252f", "%255c", "%252e%252e", "%00", "%0A", "%20"])
    func rejectsEncodedSeparatorsAndTraversal(_ payload: String) {
        #expect(throws: BrokerReadPolicyError.invalidPrincipal) {
            try BrokerReadPrincipalID("a\(payload)b")
        }
        #expect(throws: BrokerReadPolicyError.invalidRepository) {
            try BrokerRepositoryReference(owner: "a\(payload)b", name: "synthetic")
        }
        #expect(throws: BrokerReadPolicyError.invalidRepository) {
            try BrokerRepositoryReference(owner: "synthetic", name: "a\(payload)b")
        }
        #expect(throws: BrokerReadPolicyError.invalidChannel) {
            try BrokerChannelReference("C\(payload)A")
        }
    }

    /// Controls, Unicode lookalikes, combining marks, and invisible/bidi scalars are rejected rather than sanitized.
    @Test(arguments: [
        "\u{0000}", "\u{0001}", "\t", "\n", "\u{000B}", "\u{000C}", "\r", "\u{001F}", "\u{007F}",
        "é", "\u{0301}", "Ａ", "\u{FF0F}", "\u{FF3C}", "\u{2028}", "\u{2029}",
        "\u{00A0}", "\u{200B}", "\u{200D}", "\u{202E}", "\u{2066}", "\u{FEFF}", "\u{1F600}",
    ])
    func rejectsControlAndUnicodePayloadsAcrossReferences(_ payload: String) {
        #expect(throws: BrokerReadPolicyError.invalidPrincipal) {
            try BrokerReadPrincipalID("a\(payload)b")
        }
        #expect(throws: BrokerReadPolicyError.invalidRepository) {
            try BrokerRepositoryReference(owner: "a\(payload)b", name: "synthetic")
        }
        #expect(throws: BrokerReadPolicyError.invalidRepository) {
            try BrokerRepositoryReference(owner: "synthetic", name: "a\(payload)b")
        }
        #expect(throws: BrokerReadPolicyError.invalidChannel) {
            try BrokerChannelReference("C\(payload)A")
        }
    }

    /// A principal at 64 ASCII bytes is retained exactly; maximum-plus-one and much larger inputs fail closed.
    @Test
    func principalLengthHasAnExact64ByteBoundary() throws {
        let maximum = String(repeating: "A", count: 64)
        #expect(try BrokerReadPrincipalID(maximum).rawValue == maximum)
        for count in [65, 4096] {
            #expect(throws: BrokerReadPolicyError.invalidPrincipal) {
                try BrokerReadPrincipalID(String(repeating: "A", count: count))
            }
        }
    }

    /// Owner length 39 is valid before canonicalization; length 40 must not be accepted by truncation.
    @Test
    func repositoryOwnerLengthHasAnExact39ByteBoundary() throws {
        let repository = try BrokerRepositoryReference(owner: String(repeating: "A", count: 39), name: "synthetic")
        #expect(repository.owner == String(repeating: "a", count: 39))
        for count in [40, 4096] {
            #expect(throws: BrokerReadPolicyError.invalidRepository) {
                try BrokerRepositoryReference(owner: String(repeating: "A", count: count), name: "synthetic")
            }
        }
    }

    /// Repository name length 100 is valid; length 101 and larger inputs cannot become truncated valid identities.
    @Test
    func repositoryNameLengthHasAnExact100ByteBoundary() throws {
        let repository = try BrokerRepositoryReference(owner: "synthetic", name: String(repeating: "N", count: 100))
        #expect(repository.name == String(repeating: "n", count: 100))
        for count in [101, 4096] {
            #expect(throws: BrokerReadPolicyError.invalidRepository) {
                try BrokerRepositoryReference(owner: "synthetic", name: String(repeating: "N", count: count))
            }
        }
    }

    /// Channel length includes its prefix: 64 bytes is valid and 65 bytes must be rejected without truncation.
    @Test
    func channelLengthHasAnExact64ByteBoundary() throws {
        let maximum = "C" + String(repeating: "A", count: 63)
        #expect(try BrokerChannelReference(maximum).rawValue == maximum)
        for count in [64, 4095] {
            #expect(throws: BrokerReadPolicyError.invalidChannel) {
                try BrokerChannelReference("C" + String(repeating: "A", count: count))
            }
        }
    }

    /// Multibyte scalars at the character-count boundary are still invalid, not lowercased or sliced into valid IDs.
    @Test
    func rejectsMultibyteUnicodeAtReferenceLengthBoundaries() {
        #expect(throws: BrokerReadPolicyError.invalidPrincipal) {
            try BrokerReadPrincipalID(String(repeating: "A", count: 63) + "é")
        }
        #expect(throws: BrokerReadPolicyError.invalidRepository) {
            try BrokerRepositoryReference(owner: String(repeating: "A", count: 38) + "É", name: "synthetic")
        }
        #expect(throws: BrokerReadPolicyError.invalidRepository) {
            try BrokerRepositoryReference(owner: "synthetic", name: String(repeating: "N", count: 99) + "É")
        }
        #expect(throws: BrokerReadPolicyError.invalidChannel) {
            try BrokerChannelReference("C" + String(repeating: "A", count: 62) + "É")
        }
    }

    /// Limit endpoints and the standard limit retain their exact values without clamping.
    @Test(arguments: [1, 30, 100])
    func acceptsReadLimitEdges(_ value: Int) throws {
        #expect(try BrokerReadLimit(value).value == value)
    }

    /// Limits outside 1...100, including both Int extremes, produce precisely invalidLimit.
    @Test(arguments: [Int.min, -1, 0, 101, Int.max])
    func rejectsReadLimitOutsideBounds(_ value: Int) {
        #expect(throws: BrokerReadPolicyError.invalidLimit) {
            try BrokerReadLimit(value)
        }
    }

    /// Standard/first constants have the frozen 30-item, page-one defaults rather than implicit pagination state.
    @Test
    func exposesExactStandardLimitAndFirstPageDefaults() throws {
        #expect(BrokerReadLimit.standard.value == 30)
        #expect(BrokerReadLimit.standard == (try BrokerReadLimit(30)))
        #expect(BrokerReadPage.first.number == 1)
        #expect(BrokerReadPage.first.limit == .standard)
        #expect(BrokerReadPage.first == (try BrokerReadPage(number: 1)))
        let finalDefaultPage = try BrokerReadPage(number: 10)
        #expect(finalDefaultPage.number == 10)
        #expect(finalDefaultPage.limit == .standard)
    }

    /// Page endpoints preserve each supplied bounded limit independently; there is no automatic advancement.
    @Test(arguments: [1, 10])
    func acceptsPageEdgesWithExplicitLimit(_ number: Int) throws {
        for value in [1, 100] {
            let limit = try BrokerReadLimit(value)
            let page = try BrokerReadPage(number: number, limit: limit)
            #expect(page.number == number)
            #expect(page.limit == limit)
        }
    }

    /// Pages outside 1...10 fail exactly with invalidPage, regardless of a valid default or explicit limit.
    @Test(arguments: [Int.min, -1, 0, 11, Int.max])
    func rejectsPageOutsideBounds(_ number: Int) throws {
        #expect(throws: BrokerReadPolicyError.invalidPage) {
            try BrokerReadPage(number: number)
        }
        let limit = try BrokerReadLimit(100)
        #expect(throws: BrokerReadPolicyError.invalidPage) {
            try BrokerReadPage(number: number, limit: limit)
        }
    }

    /// Single-issue numbers include both specified positive endpoints and preserve the exact Int value.
    @Test(arguments: [1, 2_147_483_647])
    func acceptsIssueNumberEdges(_ value: Int) throws {
        #expect(try BrokerIssueNumber(value).value == value)
    }

    /// Zero, negatives, upper-plus-one, and Int extremes fail with precisely invalidIssueNumber.
    @Test(arguments: [Int.min, -1, 0, 2_147_483_648, Int.max])
    func rejectsIssueNumberOutsideBounds(_ value: Int) {
        #expect(throws: BrokerReadPolicyError.invalidIssueNumber) {
            try BrokerIssueNumber(value)
        }
    }

    /// The resource caps are independent: 128 repositories plus 128 channels are valid, not a shared 128 total.
    @Test
    func accepts128GrantsInEachIndependentResourceSet() throws {
        let repositories = try syntheticRepositories(count: 128)
        let channels = try syntheticChannels(count: 128)
        let id = try BrokerReadPrincipalID("Reader.Cap128")
        let principal = try BrokerReadPrincipal(id: id, repositories: repositories, channels: channels)
        #expect(principal.id == id)
        #expect(principal.repositories == repositories)
        #expect(principal.channels == channels)
        #expect(principal.repositories.count == 128)
        #expect(principal.channels.count == 128)
        #expect(BrokerReadPolicy.listCapabilities(for: principal) == [.repository, .conversation])
        for repository in repositories.sorted(by: { $0.name < $1.name }) {
            for request in try repositoryRequests(for: repository) {
                try expectApproval(request, for: principal)
            }
        }
        for channel in channels.sorted(by: { $0.rawValue < $1.rawValue }) {
            for request in channelRequests(for: channel) {
                try expectApproval(request, for: principal)
            }
        }
    }

    /// Repository grant 129 is rejected whether the separate channel set is empty or exactly at its own cap.
    @Test(arguments: [0, 128])
    func rejects129RepositoryGrants(_ channelCount: Int) throws {
        let id = try BrokerReadPrincipalID("Reader.RepositoryCap")
        let repositories = try syntheticRepositories(count: 129)
        let channels = try syntheticChannels(count: channelCount)
        #expect(repositories.count == 129)
        #expect(channels.count == channelCount)
        #expect(throws: BrokerReadPolicyError.tooManyResources) {
            try BrokerReadPrincipal(id: id, repositories: repositories, channels: channels)
        }
    }

    /// Channel grant 129 is rejected whether the separate repository set is empty or exactly at its own cap.
    @Test(arguments: [0, 128])
    func rejects129ChannelGrants(_ repositoryCount: Int) throws {
        let id = try BrokerReadPrincipalID("Reader.ChannelCap")
        let repositories = try syntheticRepositories(count: repositoryCount)
        let channels = try syntheticChannels(count: 129)
        #expect(repositories.count == repositoryCount)
        #expect(channels.count == 129)
        #expect(throws: BrokerReadPolicyError.tooManyResources) {
            try BrokerReadPrincipal(id: id, repositories: repositories, channels: channels)
        }
    }

    /// Case-duplicate repositories count once in the Set cap, preserving canonical Hashable identity.
    @Test
    func canonicalDuplicatesDoNotConsumeAnAdditionalGrantSlot() throws {
        var repositories = try syntheticRepositories(count: 128)
        let duplicate = try BrokerRepositoryReference(owner: "SYNTHETIC", name: "REPO-0")
        repositories.insert(duplicate)
        #expect(repositories.count == 128)
        let principal = try BrokerReadPrincipal(id: BrokerReadPrincipalID("Reader.DuplicateCap"), repositories: repositories)
        #expect(principal.repositories.count == 128)
        try expectApproval(.repositoryMetadata(duplicate), for: principal)
    }

    /// Only the two frozen stable read IDs construct capabilities; the enum exposes no write/default/wildcard case.
    @Test
    func exposesOnlyTheTwoStableReadCapabilities() {
        #expect(BrokerReadCapability.repository.rawValue == "github_proxy")
        #expect(BrokerReadCapability.conversation.rawValue == "slack_proxy")
        #expect(BrokerReadCapability(rawValue: "github_proxy") == .repository)
        #expect(BrokerReadCapability(rawValue: "slack_proxy") == .conversation)
        #expect(BrokerReadCapability.allCases.count == 2)
        let expected: Set<BrokerReadCapability> = [.repository, .conversation]
        #expect(Set(BrokerReadCapability.allCases) == expected)
    }

    /// Unknown, legacy, case-altered, wildcard, write, and automation labels do not become capability enum values.
    @Test(arguments: [
        "", "unknown", "github", "slack", "repository", "conversation", "github.read", "slack.read",
        "memory.read", "memory.write", "memory.*", "infer.write", "project.state.read", "project.state.*",
        "github_proxy.read", "slack_proxy.read", "github_proxy.write", "slack_proxy.write", "write.too",
        "*", "github_proxy.*", "slack_proxy.*", "default", "write", "automation", "automationAllowed",
        "GITHUB_PROXY", "SLACK_PROXY", "GitHub_Proxy", " github_proxy", "slack_proxy ", "github_proxy\n",
    ])
    func rejectsUnknownAndLegacyCapabilityNames(_ raw: String) {
        #expect(BrokerReadCapability(rawValue: raw) == nil)
    }

    /// Builds one deterministic trusted fixture with a grant for each resource family and no external dependencies.
    private func approvedFixture() throws -> (
        principal: BrokerReadPrincipal,
        repository: BrokerRepositoryReference,
        channel: BrokerChannelReference
    ) {
        let repository = try BrokerRepositoryReference(owner: "Synthetic-Lab", name: "Read.Tests")
        let channel = try BrokerChannelReference("CSYNTHETIC1")
        let principal = try BrokerReadPrincipal(
            id: BrokerReadPrincipalID("Reader.Test-1"),
            repositories: [repository],
            channels: [channel]
        )
        return (principal, repository, channel)
    }

    /// Asserts all observable authorization fields and replay equality without fabricating an authorized result.
    private func expectApproval(_ request: BrokerReadRequest, for principal: BrokerReadPrincipal) throws {
        let authorized = try BrokerReadPolicy.authorize(request, for: principal)
        let repeated = try BrokerReadPolicy.authorize(request, for: principal)
        #expect(authorized.principalID == principal.id)
        #expect(authorized.request == request)
        #expect(authorized.capability == request.capability)
        #expect(authorized == repeated)
    }

    /// Enumerates exactly the three repository read operations using frozen first-page defaults and a valid issue.
    private func repositoryRequests(for repository: BrokerRepositoryReference) throws -> [BrokerReadRequest] {
        let issue = try BrokerIssueNumber(1)
        return [
            .repositoryMetadata(repository),
            .repositoryIssues(repository, page: .first),
            .repositoryIssue(repository, number: issue),
        ]
    }

    /// Enumerates exactly the two channel read operations; history has only the frozen bounded first-page limit.
    private func channelRequests(for channel: BrokerChannelReference) -> [BrokerReadRequest] {
        [
            .channelMetadata(channel),
            .channelHistory(channel, limit: .standard),
        ]
    }

    /// Combines all five finite read operations so scope-denial checks cannot omit an operation family.
    private func allRequests(
        repository: BrokerRepositoryReference,
        channel: BrokerChannelReference
    ) throws -> [BrokerReadRequest] {
        try repositoryRequests(for: repository) + channelRequests(for: channel)
    }

    /// Generates unique ASCII repository grants by index; fixtures are synthetic and case-canonical by construction.
    private func syntheticRepositories(count: Int) throws -> Set<BrokerRepositoryReference> {
        Set(try (0..<count).map { index in
            try BrokerRepositoryReference(owner: "synthetic", name: "repo-\(index)")
        })
    }

    /// Generates unique uppercase C-channel shapes deterministically, without asserting provider existence.
    private func syntheticChannels(count: Int) throws -> Set<BrokerChannelReference> {
        Set(try (0..<count).map { index in
            try BrokerChannelReference("CSYNTHETIC\(index)")
        })
    }
}
