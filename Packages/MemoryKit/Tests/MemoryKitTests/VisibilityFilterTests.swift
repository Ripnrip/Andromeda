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
        // Given safe narratives
        let safeNarrative = "Today I learned that Swift 6 strict concurrency makes our lives more predictable and thread-safe."
        
        // When determining visibility, then suggested class is respected
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "public") == "public")
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "friends") == "friends")
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "private") == "private")
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "internal") == "internal")
        
        // Defaulting to private for unknown suggestions
        #expect(VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "cosmic_secret") == "private")
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
        // Tag array has cloak
        let safeNarrative = "A beautifully curated note."
        let determinedWithTags = VisibilityFilter.determineVisibility(for: safeNarrative, suggestedVisibility: "public", tags: ["swift", "CLOAK"])
        #expect(determinedWithTags == "internal")
        
        // Narrative has cloak tags/indicators
        let narrativeWithBracket = "This is a quiet note [cloak] about the upcoming WWDC claims."
        let narrativeWithHash = "Do not share this #cloak text."
        let narrativeWithWord = "We must cloak our local-first coordinates from telemetry."
        
        #expect(VisibilityFilter.determineVisibility(for: narrativeWithBracket, suggestedVisibility: "public") == "internal")
        #expect(VisibilityFilter.determineVisibility(for: narrativeWithHash, suggestedVisibility: "public") == "internal")
        #expect(VisibilityFilter.determineVisibility(for: narrativeWithWord, suggestedVisibility: "public") == "internal")
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
        """
        
        let redacted = VisibilityFilter.redactSensitiveData(in: narrative)
        
        #expect(!redacted.contains("AKIAIOSFODNN7EXAMPLE"))
        #expect(!redacted.contains("sk-proj-abcdfGHIJKLMN123456789"))
        #expect(!redacted.contains("xoxb-1234567890-abcdef"))
        #expect(!redacted.contains("ABCDEF123456789"))
        
        #expect(redacted.contains("[🔒 REDACTED AWS ACCESS KEY]"))
        #expect(redacted.contains("[🔒 REDACTED API KEY]"))
        #expect(redacted.contains("[🔒 REDACTED SLACK TOKEN]"))
        #expect(redacted.contains("[🔒 REDACTED PRIVATE KEY]"))
    }
    
    // MARK: - Pipeline Gating Tests
    
    @Test("🚪 Gateway Verification - Dropping private/internal from external/shared pipelines")
    func testPipelineGating() {
        // 1. External Replication (iCloud/CloudKit)
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .externalReplication) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .externalReplication) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "private", target: .externalReplication) == false)
        #expect(VisibilityFilter.isAllowed(visibility: "internal", target: .externalReplication) == false)
        
        // 2. Vector Upload (Qdrant)
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .vectorUpload) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .vectorUpload) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "private", target: .vectorUpload) == false)
        #expect(VisibilityFilter.isAllowed(visibility: "internal", target: .vectorUpload) == false)
        
        // 3. Friends Export
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .friendsExport) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .friendsExport) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "private", target: .friendsExport) == false)
        #expect(VisibilityFilter.isAllowed(visibility: "internal", target: .friendsExport) == false)
        
        // 4. Local LadybugDB Indexing (Allowed for all)
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .ladybugIndex) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .ladybugIndex) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "private", target: .ladybugIndex) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "internal", target: .ladybugIndex) == true)
        
        // 5. Local Obsidian Materialization (Allowed for all)
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .localMaterialization) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .localMaterialization) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "private", target: .localMaterialization) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "internal", target: .localMaterialization) == true)
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
        
        // Filter for CloudKit replication
        let replicationList = VisibilityFilter.filterRecords(records, visibilityKeyPath: \.visibility, target: .externalReplication)
        #expect(replicationList.count == 2)
        #expect(replicationList.contains { $0.title == "Public announcement" })
        #expect(replicationList.contains { $0.title == "Friends picnic invite" })
        #expect(!replicationList.contains { $0.title == "Private diary entry" })
        #expect(!replicationList.contains { $0.title == "Internal database credentials" })
        
        // Filter for local Obsidian vault
        let localVaultList = VisibilityFilter.filterRecords(records, visibilityKeyPath: \.visibility, target: .localMaterialization)
        #expect(localVaultList.count == 4)
    }
}
