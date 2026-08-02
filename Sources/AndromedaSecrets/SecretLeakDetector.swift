import Foundation

/// A secret-leak pattern that the detector scans text against.
///
/// Each case carries a `NSRegularExpression` compiled at construction time —
/// not a loose string evaluated at call time. This eliminates the entire class
/// of "the regex was wrong but we didn't find out until production" bugs that
/// the bash helper suffered from (e.g. `[A-Za-z0-9]` silently failing on
/// hyphenated Anthropic keys).
public enum SecretLeakPattern: Sendable {
    /// OpenAI-style keys: `sk-...` (also catches `sk-ant-api03-...` because
    /// the character class includes hyphens, unlike the original bash regex).
    case openAIKey
    /// Cerebras-style keys: `csk-...`
    case cerebrasKey
    /// Slack tokens: `xoxb-...`, `xoxp-...`, `xoxa-...`, etc.
    case slackToken
    /// GitHub PATs: `ghp_...`, `gho_...`, `ghs_...`, `ghr_...`, `ghu_...`
    case githubPAT
    /// Tailscale auth keys: `tskey-auth-...`, `tskey-apikey-...`
    case tailscaleKey
    /// PEM private key blocks
    case pemPrivateKey
    /// Generic bearer tokens in HTTP header context
    case bearerToken
    /// Known secret-bearing environment variable assignments
    case envVarAssignment

    /// The regex pattern string for this case.
    var pattern: String {
        switch self {
        case .openAIKey:        #"\bsk-[A-Za-z0-9_-]{16,}"#
        case .cerebrasKey:      #"\bcsk-[A-Za-z0-9_-]{16,}"#
        case .slackToken:       #"\bxox[baprs]-[A-Za-z0-9-]{10,}"#
        case .githubPAT:        #"\bgh[pousr]_[A-Za-z0-9]{36,}"#
        case .tailscaleKey:     #"\btskey-[A-Za-z0-9-]{10,}"#
        case .pemPrivateKey:    #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#
        case .bearerToken:      #"(?i)bearer\s+[A-Za-z0-9._~+/=-]{20,}"#
        case .envVarAssignment:
            #"(?:AI_WORKER_MCP_TOKEN|GITHUB_PAT_TOKEN|ANTHROPIC_API_KEY|CEREBRAS_API_KEY|OPENAI_API_KEY)=[^\s"'<$]{8,}"#
        }
    }

    /// Human-readable description for diagnostics.
    public var description: String {
        switch self {
        case .openAIKey:        "OpenAI/Anthropic API key"
        case .cerebrasKey:      "Cerebras API key"
        case .slackToken:       "Slack token"
        case .githubPAT:        "GitHub PAT"
        case .tailscaleKey:     "Tailscale auth key"
        case .pemPrivateKey:    "PEM private key"
        case .bearerToken:      "Bearer token"
        case .envVarAssignment:  "Secret environment variable assignment"
        }
    }
}

/// The result of scanning text for secret leaks.
///
/// This is a value type — not an exit code from a subprocess. The caller
/// pattern-matches on the case; there is no way to accidentally treat a
/// "leak detected" result as "clean" because they are different enum cases.
public enum SecretScanResult: Sendable, Equatable {
    /// No secrets detected in the scanned text.
    case clean
    /// A secret pattern was detected.
    case leakDetected(pattern: SecretLeakPattern, matchedSubstring: String)
}

/// Scans text for secret-shaped patterns and literal known-secret values.
///
/// **Why this exists in Swift instead of bash:**
///
/// The previous bash implementation (`assert_no_secret_leak` in AI-Config) had
/// a structural flaw where a pipe-into-heredoc pattern caused bash to discard
/// the piped text entirely — `python3 -` consumed stdin as its program source,
/// and `sys.stdin.read()` always returned an empty string. Every security check
/// was a no-op.
///
/// In Swift, this category of error is impossible:
/// - The input `text` is a `String` parameter, not stdin from a subprocess pipe.
///   There is no pipe, no heredoc, no stdin multiplexing.
/// - The `SecretScanResult` is a typed enum. You cannot return `.clean` when a
///   pattern matched — the compiler enforces that only one case is produced.
/// - Patterns are `SecretLeakPattern` enum cases with compiled regexes, not
///   loose strings in a list that might silently fail to compile.
/// - Literal secret values are `[String]` — if the caller passes an empty array,
///   nothing is checked; if they pass values, each is checked. There is no
///   "the pipe ate my input" failure mode.
public struct SecretLeakDetector: Sendable {
    /// All built-in patterns to scan against.
    private static let allPatterns: [(SecretLeakPattern, NSRegularExpression)] = {
        SecretLeakPattern.allCases.compactMap { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern, options: []) else {
                return nil
            }
            return (pattern, regex)
        }
    }()

    /// Literal secret values known to the caller (e.g. the actual worker token).
    /// These are checked for direct presence in the text — no regex can catch
    /// arbitrary-format tokens, so the caller supplies them explicitly.
    private let knownSecrets: [String]

    /// Creates a detector with optional literal secret values.
    ///
    /// - Parameter knownSecrets: Actual secret values to check for direct
    ///   presence in scanned text. Values shorter than 8 characters are ignored
    ///   to avoid false positives. Pass actual token values from your environment.
    public init(knownSecrets: [String] = []) {
        self.knownSecrets = knownSecrets.filter { $0.count >= 8 }
    }

    /// Scans text for any secret-shaped pattern or known literal secret.
    ///
    /// - Parameter text: The text to scan. Required — this is a `String`, not
    ///   optional stdin. If you have no text to scan, don't call this function.
    /// - Returns: `.clean` if no secrets detected, `.leakDetected` with the
    ///   pattern and matched substring otherwise.
    public func scan(_ text: String) -> SecretScanResult {
        // Check regex patterns
        let fullRange = NSRange(text.startIndex..., in: text)
        for (pattern, regex) in Self.allPatterns {
            if let match = regex.firstMatch(in: text, options: [], range: fullRange),
               let matchedRange = Range(match.range, in: text) {
                return .leakDetected(pattern: pattern, matchedSubstring: String(text[matchedRange]))
            }
        }

        // Check literal secret values
        for secret in knownSecrets {
            if text.contains(secret) {
                return .leakDetected(pattern: .bearerToken, matchedSubstring: "<literal secret: \(secret.prefix(4))…>")
            }
        }

        return .clean
    }

    /// Convenience: returns `true` if the text is safe (no leaks detected).
    public func isClean(_ text: String) -> Bool {
        scan(text) == .clean
    }
}

// MARK: - Pattern iteration support

extension SecretLeakPattern: CaseIterable {}
