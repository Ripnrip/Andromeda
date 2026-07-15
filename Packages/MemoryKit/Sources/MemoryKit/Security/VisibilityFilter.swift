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

    /// 🔮 Parse a raw visibility string case-insensitively; unknown → nil (caller fail-closes to private)
    public static func parse(_ raw: String) -> VisibilityClass? {
        VisibilityClass(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

/// 🌟 Defines target destinations/pipelines for episodic memories
public enum PipelineTarget: Sendable, Equatable, CaseIterable {
    /// iCloud / CloudKit private DB (own satellites) — public + friends only
    case externalReplication
    /// Explicit CloudKit alias of `externalReplication` (same gate)
    case cloudKit
    /// Qdrant / externalized vector graph — public + friends; never private/internal
    case vectorUpload
    /// Friends-facing export graph — public + friends
    case friendsExport
    /// Explicit export alias of `friendsExport` (same gate)
    case export
    /// Unrestricted public share surface — **public only** (friends stay cloaked from the town square)
    case publicShare
    /// Explicit share alias of `publicShare` (same gate)
    case share
    /// Local LadybugDB indexing — all classes
    case ladybugIndex
    /// Local Obsidian materialization — all classes
    case localMaterialization
}

/// 🎭 VisibilityFilter - Discerns dynamic visibility, redacts secrets, and gates pipelines on-device
public enum VisibilityFilter: Sendable {

    // 🌟 Sensitive credential regex patterns — computed (Regex is non-Sendable; avoid static let)
    private static var sensitiveRegexes: [Regex<AnyRegexOutput>] {
        [
            #"AKIA[0-9A-Z]{16}"#,
            #"(?i)aws_secret_access_key"#,
            #"sk-[a-zA-Z0-9_-]{20,}"#,
            #"xox[baprs]-[0-9a-zA-Z]{10,}"#,
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
            #"(?i)(password|passwd|api_key|client_secret|client_id)\s*[:=]\s*[^\s'\"]+"#
        ].compactMap { try? Regex($0) }
    }

    // 🌟 Cloak / secrets markers in narrative text — computed for Sendable safety
    private static var cloakPatterns: [Regex<AnyRegexOutput>] {
        [
            #"(?i)\[cloak\]"#,
            #"(?i)#cloak\b"#,
            #"(?i)\bcloak\b"#,
            #"(?i)\[secrets?\]"#,
            #"(?i)#secrets?\b"#
        ].compactMap { try? Regex($0) }
    }

    /// 🌟 Determine dynamic visibility class based on narrative content, suggested visibility, and tags.
    /// Cloak tags, secrets tags, or credential patterns force `internal`.
    public static func determineVisibility(
        for narrative: String,
        suggestedVisibility: String = "private",
        tags: [String] = []
    ) -> String {
        // 1. Explicit cloak / secrets tags → internal (the vault door slams)
        if tagsContainCloakOrSecrets(tags) {
            return VisibilityClass.internal.rawValue
        }

        // 2. Narrative cloak / secrets markers → internal
        for pattern in cloakPatterns {
            if (try? pattern.firstMatch(in: narrative)) != nil {
                return VisibilityClass.internal.rawValue
            }
        }

        // 3. Credential / secret patterns in narrative → internal
        for pattern in sensitiveRegexes {
            if (try? pattern.firstMatch(in: narrative)) != nil {
                return VisibilityClass.internal.rawValue
            }
        }

        // 4. Honor suggested class; unknown → private (fail closed)
        return VisibilityClass.parse(suggestedVisibility)?.rawValue
            ?? VisibilityClass.private.rawValue
    }

    /// 🌟 Redact sensitive credentials/API keys from narrative text with poetic placeholders
    public static func redactSensitiveData(in narrative: String) -> String {
        var redactedNarrative = narrative

        let literalReplacements: [(String, String)] = [
            (#"AKIA[0-9A-Z]{16}"#, "[🔒 REDACTED AWS ACCESS KEY]"),
            (#"sk-[a-zA-Z0-9_-]{20,}"#, "[🔒 REDACTED API KEY]"),
            (#"xox[baprs]-[0-9a-zA-Z]{10,}"#, "[🔒 REDACTED SLACK TOKEN]"),
            (
                #"-----BEGIN [A-Z ]*PRIVATE KEY-----(?s).*?-----END [A-Z ]*PRIVATE KEY-----"#,
                "[🔒 REDACTED PRIVATE KEY]"
            )
        ]

        for (pattern, placeholder) in literalReplacements {
            if let regex = try? Regex(pattern) {
                redactedNarrative = redactedNarrative.replacing(regex, with: placeholder)
            }
        }

        // ✨ Sweep keyed secrets (api_key: foo → [🔒 REDACTED SECRET]).
        // Full-match replace only — never leave `key:=value` shape or the while-loop rematches forever.
        if let keyedSecretRegex = try? Regex(
            #"(?i)(password|passwd|api_key|client_secret|client_id)\s*[:=]\s*[^\s'\"]+"#
        ) {
            var guardRails = 0
            while let match = try? keyedSecretRegex.firstMatch(in: redactedNarrative), guardRails < 64 {
                redactedNarrative.replaceSubrange(match.range, with: "[🔒 REDACTED SECRET]")
                guardRails += 1
            }
        }

        return redactedNarrative
    }

    /// 🌟 Verify whether a record with given visibility class may enter the target pipeline.
    ///
    /// Rules:
    /// - **CloudKit / export / vector / friendsExport:** drop `private` + `internal`; allow `public` + `friends`
    /// - **publicShare / share:** allow `public` only (friends never enter the town square)
    /// - **ladybug / local materialization:** all classes remain on-device
    public static func isAllowed(visibility: String, target: PipelineTarget) -> Bool {
        let vClass = VisibilityClass.parse(visibility) ?? .private

        switch target {
        case .externalReplication, .cloudKit, .vectorUpload, .friendsExport, .export:
            return vClass == .public || vClass == .friends

        case .publicShare, .share:
            return vClass == .public

        case .ladybugIndex, .localMaterialization:
            return true
        }
    }

    /// 🌟 True when the pipeline leaves the local device (share / export / CloudKit / vectors)
    public static func leavesDevice(_ target: PipelineTarget) -> Bool {
        switch target {
        case .externalReplication, .cloudKit, .vectorUpload, .friendsExport, .export, .publicShare, .share:
            return true
        case .ladybugIndex, .localMaterialization:
            return false
        }
    }

    /// 🌟 Gatekeeper payload verifier. Filters out restricted items.
    public static func filterRecords<T>(
        _ records: [T],
        visibilityKeyPath: KeyPath<T, String>,
        target: PipelineTarget
    ) -> [T] {
        records.filter { record in
            isAllowed(visibility: record[keyPath: visibilityKeyPath], target: target)
        }
    }

    /// 🔮 Classify then redact — the pre-export ritual before anything leaves the sanctum
    public static func prepareForEgress(
        narrative: String,
        suggestedVisibility: String = "private",
        tags: [String] = []
    ) -> (visibility: String, redactedNarrative: String) {
        let visibility = determineVisibility(
            for: narrative,
            suggestedVisibility: suggestedVisibility,
            tags: tags
        )
        let redacted = redactSensitiveData(in: narrative)
        return (visibility, redacted)
    }

    // MARK: - Private helpers

    /// 🎨 Tag array harbors cloak or secrets? The cloak wins.
    private static func tagsContainCloakOrSecrets(_ tags: [String]) -> Bool {
        tags.contains { tag in
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "cloak" || normalized.contains("cloak") { return true }
            if normalized == "secret" || normalized == "secrets" { return true }
            return false
        }
    }
}
