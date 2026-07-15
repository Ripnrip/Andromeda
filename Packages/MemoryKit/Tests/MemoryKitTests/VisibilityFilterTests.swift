/**
 * 🎭 The VisibilityFilterTests - The Sentinel Auditing Rituals
 *
 * "Wielding the sharpest instruments of assertion,
 * we verify the security of our memory palace.
 * No secret shall slip past the gate, no credential shall leak into the sky."
 *
 * - The Spellbinding Museum Director of Privacy Verification
 */

import Testing
import Foundation
@testable import MemoryKit

@Suite("🛡️ The Visibility Filter and Privacy Gate Rituals")
struct VisibilityFilterTests {

    // MARK: - Classification & Forcing Tests

    @Test("🟢 Normal Classification - Suggested visibilities remain intact when safe")
    func testNormalClassification() {
        let safeNarrative = "Today I learned that Swift 6 strict concurrency makes our lives more predictable and thread-safe."

        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "public") == "public")
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "friends") == "friends")
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "private") == "private")
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "internal") == "internal")

        // Unknown suggestion → private (fail closed)
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "cosmic_secret") == "private")
    }

    @Test("🔤 Case-Insensitive Visibility - PUBLIC / Friends / Private normalize correctly")
    func testCaseInsensitiveVisibilityParse() {
        let safeNarrative = "A quiet satellite note with no credentials."

        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "PUBLIC") == "public")
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "Friends") == "friends")
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: " PRIVATE ") == "private")

        #expect(VisibilityClass.parse("Internal") == .internal)
        #expect(VisibilityClass.parse("nope") == nil)

        // Pipeline gate must also accept mixed-case visibility strings
        #expect(VisibilityFilter.isAllowed(visibility: "Friends", target: .cloudKit) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "PRIVATE", target: .cloudKit) == false)
    }

    @Test("🔒 Credential Forcing - AWS Access Key ID triggers immediate lock to internal")
    func testAwsAccessKeyForcing() {
        let narrative = "I configured our AWS client using the key AKIAIOSFODNN7EXAMPLE to read from S3 buckets."
        let determined = VisibilityFilter.determineVisibility(for: narrative, suggestedVisibility: "public")

        #expect(determined == "internal", "AWS Access Key must force the record to internal visibility class!")
    }

    @Test("🔒 Credential Forcing - AWS Secret Access Key triggers immediate lock to internal")
    func testAwsSecretKeyForcing() {
        let narrative = "Remember to set aws_secret_access_key in your envrc file before deploying the launch agents."
        let determined = VisibilityFilter.determineVisibility(for: narrative, suggestedVisibility: "friends")

        #expect(determined == "internal", "AWS Secret Key keyword must force the record to internal visibility class!")
    }

    @Test("🔒 Credential Forcing - OpenAI API Key triggers immediate lock to internal")
    func testOpenAiKeyForcing() {
        let narrative = "Our Gemini and OpenAI gateway runs with the token sk-proj-1234567890abcdef1234567890abcdef."
        let determined = VisibilityFilter.determineVisibility(for: narrative, suggestedVisibility: "public")

        #expect(determined == "internal", "OpenAI API Key must force the record to internal visibility class!")
    }

    @Test("🔒 Credential Forcing - Slack Token triggers immediate lock to internal")
    func testSlackTokenForcing() {
        let narrative = "The Telegram and Slack announcer needs xoxb-1234567890-abcdef1234567890abcdef1234."
        let determined = VisibilityFilter.determineVisibility(for: narrative, suggestedVisibility: "friends")

        #expect(determined == "internal", "Slack Token must force the record to internal visibility class!")
    }

    @Test("🔒 Credential Forcing - Private Key boundary triggers immediate lock to internal")
    func testPrivateKeyForcing() {
        let narrative = """
        To authorize ssh connection to book.local, we loaded the key:
        -----BEGIN RSA PRIVATE KEY-----
        MIIEogIBAAKCAQEA0y6j...
        -----END RSA PRIVATE KEY-----
        """
        let determined = VisibilityFilter.determineVisibility(for: narrative, suggestedVisibility: "public")

        #expect(determined == "internal", "Private Key block must force the record to internal visibility class!")
    }

    @Test("🔒 Credential Forcing - Sensitive indicator key-value pairs trigger immediate lock to internal")
    func testSensitiveIndicatorForcing() {
        let narrative1 = "The database can be accessed via api_key: magical_elixir_123"
        let narrative2 = "Set client_secret=very_secret_stuff in your configuration"

        #expect(VisibilityFilter.determineVisibility(for: narrative1, suggestedVisibility: "public") == "internal")
        #expect(VisibilityFilter.determineVisibility(for: narrative2, suggestedVisibility: "friends") == "internal")
    }

    @Test("🔒 Cloak Tag Forcing - Cloak tags in parameters or text force dynamic lock to internal")
    func testCloakForcing() {
        let safeNarrative = "A beautifully curated note."
        let determinedWithTags = VisibilityFilter.determineVisibility(
            for: safeNarrative,
            suggestedVisibility: "public",
            tags: ["swift", "CLOAK"]
        )
        #expect(determinedWithTags == "internal")

        let narrativeWithBracket = "This is a quiet note [cloak] about the upcoming WWDC claims."
        let narrativeWithHash = "Do not share this #cloak text."
        let narrativeWithWord = "We must cloak our local-first coordinates from telemetry."

        #expect(VisibilityFilter.determineVisibility(for: narrativeWithBracket, suggestedVisibility: "public") == "internal")
        #expect(VisibilityFilter.determineVisibility(for: narrativeWithHash, suggestedVisibility: "public") == "internal")
        #expect(VisibilityFilter.determineVisibility(for: narrativeWithWord, suggestedVisibility: "public") == "internal")
    }

    @Test("🔒 Secrets Tag Forcing - secrets tags and markers force lock to internal")
    func testSecretsTagForcing() {
        let safeNarrative = "A note that should not leave the vault."

        #expect(
            VisibilityFilter.determineVisibility(
                for: safeNarrative,
                suggestedVisibility: "public",
                tags: ["secrets"]
            ) == "internal"
        )
        #expect(
            VisibilityFilter.determineVisibility(
                for: safeNarrative,
                suggestedVisibility: "friends",
                tags: ["SECRET"]
            ) == "internal"
        )
        #expect(
            VisibilityFilter.determineVisibility(
                for: "Hold this [secrets] close.",
                suggestedVisibility: "public"
            ) == "internal"
        )
        #expect(
            VisibilityFilter.determineVisibility(
                for: "Marked #secret in the margin.",
                suggestedVisibility: "friends"
            ) == "internal"
        )
    }

    // MARK: - Redaction Tests

    @Test("✂️ Redaction Rite - Sensitive credentials are swept and replaced with poetic banners")
    func testRedaction() {
        let narrative = """
        Checklist for deployment:
        - Use AWS ID AKIAIOSFODNN7EXAMPLE
        - OpenAI API token: sk-proj-abcdfGHIJKLMN123456789
        - Slack robot token: xoxb-1234567890-abcdef
        - Private key:
        -----BEGIN PRIVATE KEY-----
        ABCDEF123456789
        -----END PRIVATE KEY-----
        - api_key: magical_elixir_123
        """

        let redacted = VisibilityFilter.redactSensitiveData(in: narrative)

        #expect(!redacted.contains("AKIAIOSFODNN7EXAMPLE"))
        #expect(!redacted.contains("sk-proj-abcdfGHIJKLMN123456789"))
        #expect(!redacted.contains("xoxb-1234567890-abcdef"))
        #expect(!redacted.contains("ABCDEF123456789"))
        #expect(!redacted.contains("magical_elixir_123"))

        #expect(redacted.contains("[🔒 REDACTED AWS ACCESS KEY]"))
        #expect(redacted.contains("[🔒 REDACTED API KEY]"))
        #expect(redacted.contains("[🔒 REDACTED SLACK TOKEN]"))
        #expect(redacted.contains("[🔒 REDACTED PRIVATE KEY]"))
        #expect(redacted.contains("[🔒 REDACTED SECRET]"))
    }

    // MARK: - Pipeline Gating Tests

    @Test("🚪 Gateway Verification - Dropping private/internal from share/export/CloudKit")
    func testPipelineGating() {
        // 1. External Replication / CloudKit aliases
        for target in [PipelineTarget.externalReplication, .cloudKit] {
            #expect(VisibilityFilter.isAllowed(visibility: "public", target: target) == true)
            #expect(VisibilityFilter.isAllowed(visibility: "friends", target: target) == true)
            #expect(VisibilityFilter.isAllowed(visibility: "private", target: target) == false)
            #expect(VisibilityFilter.isAllowed(visibility: "internal", target: target) == false)
        }

        // 2. Vector Upload (Qdrant)
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .vectorUpload) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .vectorUpload) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "private", target: .vectorUpload) == false)
        #expect(VisibilityFilter.isAllowed(visibility: "internal", target: .vectorUpload) == false)

        // 3. Friends Export / export aliases — public + friends
        for target in [PipelineTarget.friendsExport, .export] {
            #expect(VisibilityFilter.isAllowed(visibility: "public", target: target) == true)
            #expect(VisibilityFilter.isAllowed(visibility: "friends", target: target) == true)
            #expect(VisibilityFilter.isAllowed(visibility: "private", target: target) == false)
            #expect(VisibilityFilter.isAllowed(visibility: "internal", target: target) == false)
        }

        // 4. Public share — public ONLY (friends stay out of the town square)
        for target in [PipelineTarget.publicShare, .share] {
            #expect(VisibilityFilter.isAllowed(visibility: "public", target: target) == true)
            #expect(VisibilityFilter.isAllowed(visibility: "friends", target: target) == false)
            #expect(VisibilityFilter.isAllowed(visibility: "private", target: target) == false)
            #expect(VisibilityFilter.isAllowed(visibility: "internal", target: target) == false)
        }

        // 5. Local LadybugDB Indexing (Allowed for all)
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .ladybugIndex) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .ladybugIndex) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "private", target: .ladybugIndex) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "internal", target: .ladybugIndex) == true)

        // 6. Local Obsidian Materialization (Allowed for all)
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .localMaterialization) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .localMaterialization) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "private", target: .localMaterialization) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "internal", target: .localMaterialization) == true)
    }

    @Test("🚪 Public vs Friends Rules - friends may export/CloudKit but not unrestricted share")
    func testPublicFriendsRules() {
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .cloudKit) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .export) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .vectorUpload) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .publicShare) == false)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .share) == false)

        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .publicShare) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .cloudKit) == true)
    }

    @Test("🚪 Gateway Verifier Filter - Filtering collection of records by keypath")
    func testRecordFiltering() {
        struct MockRecord {
            let title: String
            let visibility: String
        }

        let records = [
            MockRecord(title: "Public announcement", visibility: "public"),
            MockRecord(title: "Friends picnic invite", visibility: "friends"),
            MockRecord(title: "Private diary entry", visibility: "private"),
            MockRecord(title: "Internal database credentials", visibility: "internal")
        ]

        let replicationList = VisibilityFilter.filterRecords(
            records,
            visibilityKeyPath: \.visibility,
            target: .cloudKit
        )
        #expect(replicationList.count == 2)
        #expect(replicationList.contains { $0.title == "Public announcement" })
        #expect(replicationList.contains { $0.title == "Friends picnic invite" })
        #expect(!replicationList.contains { $0.title == "Private diary entry" })
        #expect(!replicationList.contains { $0.title == "Internal database credentials" })

        let publicShareList = VisibilityFilter.filterRecords(
            records,
            visibilityKeyPath: \.visibility,
            target: .share
        )
        #expect(publicShareList.count == 1)
        #expect(publicShareList.first?.title == "Public announcement")

        let localVaultList = VisibilityFilter.filterRecords(
            records,
            visibilityKeyPath: \.visibility,
            target: .localMaterialization
        )
        #expect(localVaultList.count == 4)
    }

    @Test("🧭 Leaves Device Map - share/export/CloudKit/vector leave; local stays")
    func testLeavesDevice() {
        #expect(VisibilityFilter.leavesDevice(.cloudKit) == true)
        #expect(VisibilityFilter.leavesDevice(.externalReplication) == true)
        #expect(VisibilityFilter.leavesDevice(.export) == true)
        #expect(VisibilityFilter.leavesDevice(.friendsExport) == true)
        #expect(VisibilityFilter.leavesDevice(.share) == true)
        #expect(VisibilityFilter.leavesDevice(.publicShare) == true)
        #expect(VisibilityFilter.leavesDevice(.vectorUpload) == true)
        #expect(VisibilityFilter.leavesDevice(.ladybugIndex) == false)
        #expect(VisibilityFilter.leavesDevice(.localMaterialization) == false)
    }

    @Test("🧾 Task9 Proof Harness - cloak/secrets→internal; private/internal drop; public/friends rules")
    func testTask9VisibilityProofHarness() {
        // Cloak / secrets force internal even when suggested public
        let cloaked = VisibilityFilter.prepareForEgress(
            narrative: "Satellite coordinates [cloak]",
            suggestedVisibility: "public",
            tags: []
        )
        #expect(cloaked.visibility == "internal")

        let secretTagged = VisibilityFilter.prepareForEgress(
            narrative: "Harmless prose",
            suggestedVisibility: "friends",
            tags: ["secrets"]
        )
        #expect(secretTagged.visibility == "internal")

        let withKey = VisibilityFilter.prepareForEgress(
            narrative: "Deploy with sk-proj-1234567890abcdef1234567890ab",
            suggestedVisibility: "public"
        )
        #expect(withKey.visibility == "internal")
        #expect(!withKey.redactedNarrative.contains("sk-proj-1234567890abcdef1234567890ab"))
        #expect(withKey.redactedNarrative.contains("[🔒 REDACTED API KEY]"))

        // private / internal never leave via share / export / CloudKit
        for visibility in ["private", "internal"] {
            #expect(VisibilityFilter.isAllowed(visibility: visibility, target: .cloudKit) == false)
            #expect(VisibilityFilter.isAllowed(visibility: visibility, target: .export) == false)
            #expect(VisibilityFilter.isAllowed(visibility: visibility, target: .share) == false)
            #expect(VisibilityFilter.isAllowed(visibility: visibility, target: .vectorUpload) == false)
        }

        // public may leave everywhere; friends may CloudKit/export/vector but not unrestricted share
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .share) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .cloudKit) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .export) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .share) == false)

        // Local paths remain open for all classes
        #expect(VisibilityFilter.isAllowed(visibility: "internal", target: .localMaterialization) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "private", target: .ladybugIndex) == true)
    }
}
