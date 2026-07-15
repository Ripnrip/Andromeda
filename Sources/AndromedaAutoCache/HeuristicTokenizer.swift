import Foundation

/// Fast heuristic Anthropic token estimator (Autocache-compatible).
///
/// This intentionally overestimates slightly so cache thresholds are more likely
/// to be met; it is not a byte-perfect Anthropic tokenizer.
public final class HeuristicTokenizer: @unchecked Sendable {
    private var cache: [String: Int] = [:]
    private let lock = NSLock()

    public init() {}

    public func countTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        lock.lock()
        if let cached = cache[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let charCount = text.count
        var tokens = Double(charCount) / 1.5
        if isCodeLike(text) { tokens *= 1.2 }
        if isJSONLike(text) { tokens *= 1.3 }
        if charCount < 50 { tokens *= 1.1 }
        if charCount > 1000 { tokens += 2 }

        var result = Int(tokens)
        if result < 1 { result = 1 }

        lock.lock()
        cache[text] = result
        lock.unlock()
        return result
    }

    public func countMessageTokens(_ message: Message) -> Int {
        3 + message.content.reduce(0) { $0 + countContentBlockTokens($1) }
    }

    public func countContentBlockTokens(_ block: ContentBlock) -> Int {
        var total = 2
        switch block.type {
        case "text":
            total += countTokens(block.text ?? "")
        case "image":
            total += 85
        default:
            break
        }
        return total
    }

    public func countToolTokens(_ tool: ToolDefinition) -> Int {
        var total = 5
        total += countTokens(tool.name)
        total += countTokens(tool.description)
        total += countTokens(tool.inputSchema.debugDescription)
        return total
    }

    public func modelMinimumTokens(for model: String) -> Int {
        model.lowercased().contains("haiku") ? 2048 : 1024
    }

    public func countSystemTokens(_ system: String) -> Int {
        guard !system.isEmpty else { return 0 }
        return countTokens(system) + 2
    }

    public func countSystemBlocksTokens(_ blocks: [ContentBlock]) -> Int {
        2 + blocks.reduce(0) { $0 + countContentBlockTokens($1) }
    }

    public func estimateRequestTokens(_ request: AnthropicRequest) -> Int {
        var total = 5
        switch request.system {
        case .text(let text):
            total += countSystemTokens(text)
        case .blocks(let blocks):
            total += countSystemBlocksTokens(blocks)
        case .none:
            break
        }
        for tool in request.tools ?? [] {
            total += countToolTokens(tool)
        }
        for message in request.messages {
            total += countMessageTokens(message)
        }
        return total
    }

    private func isCodeLike(_ text: String) -> Bool {
        let patterns = [
            "function", "class", "import", "def ", "var ", "const ", "let ",
            "if (", "for (", "while (",
        ]
        if patterns.contains(where: { text.contains($0) }) { return true }
        let punct = text.filter { "{}[]().,;:\"'`<>=+-*/&|^%!".contains($0) }.count
        return text.count > 20 && Double(punct) / Double(text.count) > 0.15
    }

    private func isJSONLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }
}
