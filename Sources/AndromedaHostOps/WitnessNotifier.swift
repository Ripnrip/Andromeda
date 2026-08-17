import AndromedaSecrets
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Notification protocol

/// Injectable notification boundary. Implementations must never log or
/// persist secret tokens.
public protocol WitnessNotifying: Sendable {
    /// Send a transition notification. Returns true on successful delivery.
    func notify(event: WitnessTransitionEvent) async -> Bool
}

// MARK: - No-op notifier

/// Does nothing — used when no notification channel is configured.
public struct NoOpWitnessNotifier: WitnessNotifying {
    public init() {}

    /// No channel means no delivery. Returning false keeps the notification
    /// in the durable outbox and prevents status from claiming it was sent.
    public func notify(event: WitnessTransitionEvent) async -> Bool { false }
}

// MARK: - Recording notifier (for tests)

/// Records all notifications for test assertions without sending anything.
public actor RecordingWitnessNotifier: WitnessNotifying {
    public private(set) var captured: [WitnessTransitionEvent] = []

    public init() {}

    public func notify(event: WitnessTransitionEvent) async -> Bool {
        captured.append(event)
        return true
    }

    public func reset() {
        captured.removeAll()
    }
}

// MARK: - Telegram HTTP client protocol

/// Injectable HTTP client for Telegram Bot API calls. Tests inject a mock;
/// production uses `URLSessionTelegramClient`.
public protocol TelegramHTTPClient: Sendable {
    /// Send a text message via the Telegram Bot API.
    func sendMessage(
        baseURL: String,
        botToken: String,
        chatID: String,
        text: String
    ) async -> Bool
}

// MARK: - URLSession Telegram client

/// Production Telegram HTTP client using URLSession. The bot token is passed
/// as a parameter (resolved at call time from `SecretProviding`) and never
/// stored or logged.
public struct URLSessionTelegramClient: TelegramHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func sendMessage(
        baseURL: String,
        botToken: String,
        chatID: String,
        text: String
    ) async -> Bool {
        guard let url = URL(string: "\(baseURL)/bot\(botToken)/sendMessage") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "chat_id": chatID,
            "text": text,
            "parse_mode": "Markdown",
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return false
        }
        request.httpBody = bodyData

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}

// MARK: - Telegram notifier

/// Sends transition notifications via the Telegram Bot API.
///
/// The bot token is resolved from `SecretProviding` at call time — never stored
/// in configuration, state, or logs. The chat ID is non-secret and may come
/// from config or CLI.
public struct TelegramWitnessNotifier: WitnessNotifying {
    private let config: TelegramConfig
    private let secretProvider: any SecretProviding
    private let httpClient: any TelegramHTTPClient

    public init(
        config: TelegramConfig,
        secretProvider: any SecretProviding,
        httpClient: any TelegramHTTPClient = URLSessionTelegramClient()
    ) {
        self.config = config
        self.secretProvider = secretProvider
        self.httpClient = httpClient
    }

    public func notify(event: WitnessTransitionEvent) async -> Bool {
        let botToken: String
        do {
            botToken = try await secretProvider.secret(for: config.botTokenReference)
        } catch {
            // Surface the failure — do not silently swallow. The reference
            // names are safe to include; the token value is never logged.
            return false
        }
        let text = Self.formatMessage(event: event)
        return await httpClient.sendMessage(
            baseURL: config.apiBaseURL,
            botToken: botToken,
            chatID: config.chatID,
            text: text
        )
    }

    /// Formats a human-readable Telegram message for a transition event.
    /// Never includes secrets — only the event's typed fields.
    public static func formatMessage(event: WitnessTransitionEvent) -> String {
        let emoji: String
        switch event.kind {
        case .established:
            emoji = "✅"
        case .alert:
            emoji = "🚨"
        case .recovery:
            emoji = "🔄"
        }
        return """
        \(emoji) *Andromeda Witness*

        Target: `\(event.targetLabel)`
        Transition: \(event.fromStatus.rawValue) → \(event.toStatus.rawValue)
        Kind: \(event.kind.rawValue)
        Reason: \(event.reason)
        Owner: \(event.owner)
        Host: \(event.host)
        Failures: \(event.consecutiveFailures)
        """
    }
}
