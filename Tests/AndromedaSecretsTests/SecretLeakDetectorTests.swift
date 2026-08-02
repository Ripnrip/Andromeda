import Testing
import Foundation
@testable import AndromedaSecrets

/// Tests for SecretLeakDetector — the Swift-native replacement for the bash
/// `assert_no_secret_leak` helper that was a complete no-op.
///
/// These tests prove:
/// 1. Every real-format secret is detected (the bash helper missed ghp_, tskey-,
///    sk-ant-, and generic bearer tokens).
/// 2. Clean text passes.
/// 3. Literal known-secret values are detected regardless of format.
/// 4. The typed `SecretScanResult` enum prevents the class of bug where a
///    "leak detected" result is accidentally treated as "clean."
@Suite("SecretLeakDetector")
struct SecretLeakDetectorTests {

    let detector = SecretLeakDetector()

    // MARK: - Positive cases: clean text must pass

    @Test("Clean JSON response passes")
    func cleanJSON() {
        #expect(detector.scan(#"{"status":"ok","count":3}"#) == .clean)
    }

    @Test("Empty string passes")
    func emptyString() {
        #expect(detector.scan("") == .clean)
    }

    @Test("Ordinary English text passes")
    func ordinaryText() {
        #expect(detector.scan("The quick brown fox jumps over the lazy dog.") == .clean)
    }

    // MARK: - Negative cases: each real-format secret must be detected

    @Test("Detects OpenAI sk- key")
    func detectsOpenAIKey() {
        let result = detector.scan(#"{"token":"sk-abcdefghijklmnopqrstuvwxyz1234567890"}"#)
        #expect(result != .clean)
        if case .leakDetected(let pattern, _) = result {
            #expect(pattern == .openAIKey)
        }
    }

    @Test("Detects Anthropic sk-ant-api03 key (hyphens in prefix — the bash bug)")
    func detectsAnthropicKey() {
        // The original bash regex `[A-Za-z0-9]{16,}` broke after 3 chars on
        // `sk-ant-api03-` because hyphens weren't in the character class.
        // Swift's pattern includes `-` so this is caught.
        let result = detector.scan(#"{"key":"sk-ant-api03-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}"#)
        #expect(result != .clean)
    }

    @Test("Detects Cerebras csk- key")
    func detectsCerebrasKey() {
        let result = detector.scan(#"{"token":"csk-abcdefghijklmnopqrstuvwxyz1234567890"}"#)
        #expect(result != .clean)
    }

    @Test("Detects Slack xoxb- token")
    func detectsSlackToken() {
        let result = detector.scan(#"{"token":"xoxb-1234567890-abcdefghij"}"#)
        #expect(result != .clean)
    }

    @Test("Detects GitHub PAT (ghp_)")
    func detectsGitHubPAT() {
        let result = detector.scan(#"{"token":"ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD"}"#)
        #expect(result != .clean)
    }

    @Test("Detects Tailscale tskey- auth key")
    func detectsTailscaleKey() {
        let result = detector.scan(#"{"key":"tskey-auth-abcdef1234567890abcdefghij"}"#)
        #expect(result != .clean)
    }

    @Test("Detects PEM private key block")
    func detectsPEMKey() {
        let result = detector.scan("-----BEGIN RSA PRIVATE KEY-----\nMIIEpAI...\n-----END RSA PRIVATE KEY-----")
        #expect(result != .clean)
    }

    @Test("Detects generic Bearer token in header")
    func detectsBearerToken() {
        let result = detector.scan(#"{"header":"Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5c"}"#)
        #expect(result != .clean)
    }

    @Test("Detects AI_WORKER_MCP_TOKEN assignment")
    func detectsEnvVarAssignment() {
        let result = detector.scan("AI_WORKER_MCP_TOKEN=worker-secret-token-abc123")
        #expect(result != .clean)
    }

    // MARK: - Literal secret values

    @Test("Detects literal secret value via knownSecrets")
    func detectsLiteralSecret() {
        let detectorWithSecrets = SecretLeakDetector(knownSecrets: ["my-arbitrary-format-token-XYZ"])
        let result = detectorWithSecrets.scan(#"{"data":"my-arbitrary-format-token-XYZ"}"#)
        #expect(result != .clean)
    }

    @Test("Literal secret not present in text passes")
    func literalSecretAbsent() {
        let detectorWithSecrets = SecretLeakDetector(knownSecrets: ["completely-different-secret-value"])
        #expect(detectorWithSecrets.scan(#"{"data":"safe-value-here"}"#) == .clean)
    }

    @Test("Short literal (< 8 chars) is ignored to avoid false positives")
    func shortLiteralIgnored() {
        let detectorWithSecrets = SecretLeakDetector(knownSecrets: ["abc"])
        #expect(detectorWithSecrets.scan(#"{"id":"abc"}"#) == .clean)
    }

    // MARK: - Type safety guarantees

    @Test("SecretScanResult leakDetected carries the pattern that matched")
    func resultCarriesPattern() {
        let result = detector.scan(#"{"t":"sk-abcdefghijklmnopqrstuvwxyz1234567890"}"#)
        if case .leakDetected(let pattern, let matched) = result {
            #expect(pattern == .openAIKey)
            #expect(matched.hasPrefix("sk-"))
        } else {
            Issue.record("Expected .leakDetected, got \(result)")
        }
    }

    @Test("isClean convenience returns correct boolean")
    func isCleanConvenience() {
        #expect(detector.isClean(#"{"status":"ok"}"#) == true)
        #expect(detector.isClean(#"{"t":"sk-abcdefghijklmnopqrstuvwxyz1234567890"}"#) == false)
    }

    @Test("All SecretLeakPattern cases have valid compilable regexes")
    func allPatternsCompile() {
        for pattern in SecretLeakPattern.allCases {
            #expect(throws: Never.self) {
                _ = try NSRegularExpression(pattern: pattern.pattern, options: [])
            }
        }
    }
}
