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
    /// Render path. Nil means degrade, never crash. The coding path lives in `evidence`.
    static func decode(_ data: Data) -> StatusPayload? {
        if case let .success(payload) = evidence(data) { return payload }
        return nil
    }

    /// Why a payload could not be read. Callers that only render still degrade;
    /// they must not drop this string on the floor.
    static func evidence(_ data: Data) -> Result<StatusPayload, StatusDecodeFailure> {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return .success(try decoder.decode(StatusPayload.self, from: data))
        } catch let error as DecodingError {
            return .failure(StatusDecodeFailure(evidence: error.brief))
        } catch {
            return .failure(StatusDecodeFailure(evidence: "parse error"))
        }
    }
}

struct StatusDecodeFailure: Error, Equatable {
    let evidence: String
}

private extension DecodingError {
    var brief: String {
        func path(_ context: Context) -> String {
            let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
            return joined.isEmpty ? "root" : joined
        }
        switch self {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case .valueNotFound(_, let context):
            return "unexpected null at \(path(context))"
        case .typeMismatch(_, let context), .dataCorrupted(let context):
            return "\(localizedDescription) at \(path(context))"
        @unknown default:
            return localizedDescription
        }
    }
}
