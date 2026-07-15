/**
 * 🎭 The VisibilityFilter - The Sentinel of the Sanctum
 *
 * "Standing at the gates of the digital memory palace,
 * discerning which thoughts may soar into the shared ether,
 * and which must remain locked in the dark vault of private contemplation."
 *
 * - The Spellbinding Museum Director of Security & Privacy
 */

import Foundation

/// 🌟 Represents the standard classification of memory visibility
public enum VisibilityClass: String, Sendable, Codable, CaseIterable {
    case `public` = "public"
    case friends = "friends"
    case `private` = "private"
    case `internal` = "internal"
}

/// 🌟 Defines target destinations/pipelines for episodic memories
public enum PipelineTarget: Sendable {
    case externalReplication // iCloud / CloudKit sync
    case vectorUpload        // Qdrant vector upload
    case friendsExport       // Exporting to trusted friends
    case ladybugIndex        // Local LadybugDB indexing
    case localMaterialization // Curation into local Obsidian Markdown files
}

/// 🎭 VisibilityFilter - Discerns dynamic visibility, redacts secrets, and gates pipelines on-device
public final class VisibilityFilter: Sendable {
    
    // 🌟 Sensitive credential regex patterns to detect API keys and private keys
    private static var sensitiveRegexes: [Regex<AnyRegexOutput>] {
        let patterns = [
            // AWS Access Key ID
            #"AKIA[0-9A-Z]{16}"#,
            // AWS Secret Access Key indicator
            #"(?i)aws_secret_access_key"#,
            // OpenAI / Anthropic / general API keys
            #"sk-[a-zA-Z0-9_-]{20,}"#,
            // Slack tokens
            #"xox[baprs]-[0-9a-zA-Z]{10,}"#,
            // Generic Private Key boundaries
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
            // Password or api secret key patterns
            #"(?i)(password|passwd|api_key|client_secret|client_id)\s*[:=]\s*[^\s'"]+"#
        ]
        return patterns.compactMap { try? Regex($0) }
    }
    
    // 🌟 Cloak indicators in text
    private static var cloakPatterns: [Regex<AnyRegexOutput>] {
        let patterns = [
            #"(?i)\[cloak\]"#,
            #"(?i)#cloak\b"#,
            #"(?i)\bcloak\b"#
        ]
        return patterns.compactMap { try? Regex($0) }
    }

    /// 🌟 Determine dynamic visibility class based on narrative content, suggested visibility, and tags.
    /// If sensitive keys or cloak tags are present, we force "internal".
    public static func determineVisibility(
        for narrative: String,
        suggestedVisibility: String = "private",
        tags: [String] = []
    ) -> String {
        // 1. If explicit "cloak" tag is in the tags array, force to internal
        let hasCloakTag = tags.contains { tag in
            tag.localizedCaseInsensitiveContains("cloak")
        }
        if hasCloakTag {
            return VisibilityClass.internal.rawValue
        }
        
        // 2. Scan narrative text for explicit cloak tags or markers
        for pattern in cloakPatterns {
            if (try? pattern.firstMatch(in: narrative)) != nil {
                return VisibilityClass.internal.rawValue
            }
        }
        
        // 3. Scan narrative text for API keys or private credentials
        for pattern in sensitiveRegexes {
            if (try? pattern.firstMatch(in: narrative)) != nil {
                return VisibilityClass.internal.rawValue
            }
        }
        
        // Otherwise, validate and return the suggested visibility, falling back to private
        guard let visibilityClass = VisibilityClass(rawValue: suggestedVisibility) else {
            return VisibilityClass.private.rawValue
        }
        return visibilityClass.rawValue
    }
    
    /// 🌟 Redact sensitive credentials/API keys from narrative text with poetic placeholders
    public static func redactSensitiveData(in narrative: String) -> String {
        var redactedNarrative = narrative
        
        let replacements: [(Regex<AnyRegexOutput>, String)] = [
            (try! Regex(#"AKIA[0-9A-Z]{16}"#), "[🔒 REDACTED AWS ACCESS KEY]"),
            (try! Regex(#"sk-[a-zA-Z0-9_-]{20,}"#), "[🔒 REDACTED API KEY]"),
            (try! Regex(#"xox[baprs]-[0-9a-zA-Z]{10,}"#), "[🔒 REDACTED SLACK TOKEN]"),
            (try! Regex(#"-----BEGIN [A-Z ]*PRIVATE KEY-----(?s).*?-----END [A-Z ]*PRIVATE KEY-----"#), "[🔒 REDACTED PRIVATE KEY]")
        ]
        
        for (regex, placeholder) in replacements {
            redactedNarrative = redactedNarrative.replacing(regex, with: placeholder)
        }
        
        return redactedNarrative
    }
    
    /// 🌟 Verify whether a record with given visibility class is allowed to pass to the target pipeline.
    /// Drop `private` or `internal` records from any external replication, vector upload, or friends export pipelines.
    public static func isAllowed(visibility: String, target: PipelineTarget) -> Bool {
        let vClass = VisibilityClass(rawValue: visibility) ?? .private
        
        switch target {
        case .externalReplication, .vectorUpload, .friendsExport:
            // Drop private and internal. Only allow public and friends.
            return vClass == .public || vClass == .friends
            
        case .ladybugIndex, .localMaterialization:
            // All classes can be indexed locally or materialized locally
            return true
        }
    }
    
    /// 🌟 Gatekeeper payload verifier. Filters out restricted items.
    public static func filterRecords<T>(_ records: [T], visibilityKeyPath: KeyPath<T, String>, target: PipelineTarget) -> [T] {
        return records.filter { record in
            isAllowed(visibility: record[keyPath: visibilityKeyPath], target: target)
        }
    }
}
