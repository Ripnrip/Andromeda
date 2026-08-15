import Foundation

/// Claude Code's statusline stdin payload. Only the fields we render.
struct StatusPayload: Decodable, Sendable {
    struct Model: Decodable, Sendable {
        let displayName: String?
    }

    struct Workspace: Decodable, Sendable {
        let currentDir: String?
    }

    let model: Model?
    let workspace: Workspace?
}

enum StatusPayloadDecoder {
    static func decode(_ data: Data) -> StatusPayload? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(StatusPayload.self, from: data)
    }
}
