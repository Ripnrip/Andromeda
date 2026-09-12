@testable import AndromedaMCPHub
import Foundation

// MARK: - Fixture payload types

/// A generic client request for builder use: any method, any JSON value as
/// params, plus arbitrary EXTRA top-level members (unknown-field tests).
/// Encodes in canonical `jsonrpc,id,method[,params][,extras…]` order.
struct ClientRequestFixture: Encodable {
    let jsonrpc: String
    let id: JSONRPCRequestID
    let method: String
    let params: JSONValue?
    let extras: [String: JSONValue]

    init(
        id: JSONRPCRequestID, method: String, params: JSONValue? = nil,
        extras: [String: JSONValue] = [:]
    ) {
        jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
        self.extras = extras
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        if let params {
            try container.encode(params, forKey: .params)
        }
        // Unknown/extra members — the existing container is keyed by the
        // fixed CodingKeys, so extras go through a fresh keyed pass over
        // the SAME encoder via superEncoder (same object, added members).
        // Sorted for deterministic output; encoded PRESENT even when null
        // (the shape the relay must preserve).
        if !extras.isEmpty {
            let extrasEncoder = container.superEncoder()
            var extrasContainer = extrasEncoder.container(keyedBy: ExtraKey.self)
            for (key, value) in extras.sorted(by: { $0.key < $1.key }) {
                try extrasContainer.encode(value, forKey: ExtraKey(key))
            }
        }
    }

    enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }

    private struct ExtraKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init(_ string: String) {
            stringValue = string; intValue = nil
        }

        init?(intValue: Int) {
            nil
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }
    }
}

/// A notification (no id member) for builder use.
struct ClientNotificationFixture: Encodable {
    let jsonrpc: String
    let method: String
    let params: JSONValue?

    init(method: String, params: JSONValue? = nil) {
        jsonrpc = "2.0"
        self.method = method
        self.params = params
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(method, forKey: .method)
        if let params {
            try container.encode(params, forKey: .params)
        }
    }

    enum CodingKeys: String, CodingKey { case jsonrpc, method, params }
}

/// An upstream response for builder use (the direction the hub routes back).
struct UpstreamResponseFixture: Encodable {
    let jsonrpc: String
    let id: JSONRPCRequestID
    let result: JSONValue

    init(id: JSONRPCRequestID, result: JSONValue) {
        jsonrpc = "2.0"
        self.id = id
        self.result = result
    }

    enum CodingKeys: String, CodingKey { case jsonrpc, id, result }
}

// MARK: - JSON value shim

/// Minimal typed JSON value for builder params/results — enough to build
/// the fixtures the relay tests need without importing a JSON library.
/// Each nested encode call receives its own Encoder, so each case creates
/// exactly one container of the right shape.
enum JSONValue: Encodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .object(object):
            var container = encoder.container(keyedBy: JSONKey.self)
            // Sorted keys → deterministic builder output.
            for (key, value) in object.sorted(by: { $0.key < $1.key }) {
                try container.encode(value, forKey: JSONKey(key))
            }
        case let .array(items):
            var container = encoder.unkeyedContainer()
            for item in items {
                try container.encode(item)
            }
        case let .string(string):
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case let .number(number):
            var container = encoder.singleValueContainer()
            try container.encode(number)
        case let .bool(bool):
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    private struct JSONKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init(_ string: String) {
            stringValue = string; intValue = nil
        }

        init?(intValue: Int) {
            nil
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }
    }
}

// MARK: - Builders

/// Fixture builders: valid JSON-RPC frames assembled from typed values.
enum JSONRPCFixtures {
    /// A client request with an integer id.
    static func makeClientRequest(
        id: Int, method: String, params: JSONValue? = nil,
        extras: [String: JSONValue] = [:]
    ) -> Data {
        encode(ClientRequestFixture(id: .number(id), method: method, params: params, extras: extras))
    }

    /// A client request with a string id.
    static func makeClientRequest(
        id: String, method: String, params: JSONValue? = nil,
        extras: [String: JSONValue] = [:]
    ) -> Data {
        encode(ClientRequestFixture(id: .string(id), method: method, params: params, extras: extras))
    }

    /// A notification (no id member at all).
    static func makeNotification(
        method: String, params: JSONValue? = nil
    ) -> Data {
        encode(ClientNotificationFixture(method: method, params: params))
    }

    /// A `notifications/cancelled` frame — the SAME typed builder produces
    /// both wire shapes (integer and string `params.requestId`), the two
    /// shapes MCP servers actually see.
    static func makeCancelledNotification(requestId: JSONRPCRequestID) -> Data {
        makeNotification(
            method: "notifications/cancelled",
            params: .object(["requestId": idValue(requestId)])
        )
    }

    /// Convenience overload: integer cancelled requestId.
    static func makeCancelledNotification(requestId: Int) -> Data {
        makeCancelledNotification(requestId: .number(requestId))
    }

    /// Convenience overload: string cancelled requestId (e.g. "c2.7").
    static func makeCancelledNotification(requestId: String) -> Data {
        makeCancelledNotification(requestId: .string(requestId))
    }

    /// An upstream response carrying the namespaced composite id.
    static func makeUpstreamResponse(id: JSONRPCRequestID, result: JSONValue) -> Data {
        encode(UpstreamResponseFixture(id: id, result: result))
    }

    private static func idValue(_ id: JSONRPCRequestID) -> JSONValue {
        switch id {
        case let .number(n): .number(Double(n))
        case let .string(s): .string(s)
        }
    }

    private static func encode(_ fixture: some Encodable) -> Data {
        let encoder = JSONEncoder()
        // Real JSON-RPC emitters do not escape `/` — without this the
        // fixtures carry `tools\/list`, which is valid but obscures the
        // assertions that inspect the frame text.
        encoder.outputFormatting = [.withoutEscapingSlashes]
        // swiftlint:disable:next force_try
        return try! encoder.encode(fixture)
    }
}
