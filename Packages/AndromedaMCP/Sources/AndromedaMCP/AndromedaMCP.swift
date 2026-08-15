// AndromedaMCP — MCP stdio server exposing ast-grep search/rewrite as tools.
// Replaces the OMC Node bridge: one small Swift 6 binary, zero dependencies.
//
// Protocol: Model Context Protocol over stdio (JSON-RPC 2.0, line-delimited).
// This file is the effect shell only — the stdio loop and dispatch. Wire
// models live in RPC.swift, the tool surface in Tools.swift, and the engine
// in ASTGrep.swift.

import Foundation

@main
struct AndromedaMCPServer {
    static func main() async throws {
        // Resolve the pattern engine once; a missing engine still serves
        // initialize/tools/list and reports the gap per tool call.
        let engine = await EngineLocator.locate()

        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            await dispatch(Data(trimmed.utf8), engine: engine)
        }
    }

    // MARK: - Dispatch

    private static func dispatch(_ data: Data, engine: URL?) async {
        guard let header = decode(RPCRequestHeader.self, from: data, id: nil) else { return }

        switch header.method {
        case "initialize":
            struct InitializeParams: Decodable {}
            if let request = decode(RPCRequest<InitializeParams>.self, from: data, id: header.id) {
                send(RPCResult(id: request.id, result: InitializeResult()))
            }

        case "notifications/initialized":
            break // notification — no response

        case "tools/list":
            struct NoParams: Decodable {}
            if let request = decode(RPCRequest<NoParams>.self, from: data, id: header.id) {
                send(RPCResult(id: request.id, result: ToolsListResult(tools: Tool.all)))
            }

        case "tools/call":
            await toolCall(data, engine: engine)

        default:
            // Unknown notifications are dropped silently; unknown requests
            // get a method-not-found error.
            if let id = header.id {
                send(RPCErrorResponse(
                    id: id,
                    code: .methodNotFound,
                    message: "Method not found: \(header.method)"
                ))
            }
        }
    }

    /// First decode pass inside `tools/call`: just the tool name, so the
    /// second pass can decode tool-specific arguments.
    private struct ToolNameProbe: Decodable {
        struct Params: Decodable { let name: String }
        let params: Params
    }

    /// Two typed decode passes over the same bytes: route on the tool name,
    /// then decode the full request with tool-specific arguments so schema
    /// violations surface as `-32602` with the coding path.
    private static func toolCall(_ data: Data, engine: URL?) async {
        guard let probe = decode(ToolNameProbe.self, from: data, id: nil) else { return }

        switch probe.params.name {
        case Tool.search.name:
            guard let request = decode(
                ToolCallRequest<CodeSearchArguments>.self, from: data, id: nil
            ) else { return }
            let arguments = request.params.arguments
            guard let engine else {
                send(RPCResult(id: request.id, result: CallToolResult.text(
                    "Error: \(ASTGrepError.binaryNotFound.localizedDescription)", isError: true
                )))
                return
            }
            do {
                let matches = try await runASTGrep(
                    engine: engine,
                    pattern: arguments?.pattern ?? "",
                    path: arguments?.path,
                    language: arguments?.language
                )
                send(RPCResult(
                    id: request.id,
                    result: CallToolResult.text(formatSearchMatches(matches))
                ))
            } catch {
                send(RPCResult(
                    id: request.id,
                    result: CallToolResult.text("Error: \(error.localizedDescription)", isError: true)
                ))
            }

        case Tool.replacement.name:
            guard let request = decode(
                ToolCallRequest<CodeReplaceArguments>.self, from: data, id: nil
            ) else { return }
            let arguments = request.params.arguments
            guard let engine else {
                send(RPCResult(id: request.id, result: CallToolResult.text(
                    "Error: \(ASTGrepError.binaryNotFound.localizedDescription)", isError: true
                )))
                return
            }
            do {
                let matches = try await runASTGrep(
                    engine: engine,
                    pattern: arguments?.pattern ?? "",
                    replacement: arguments?.replacement,
                    path: arguments?.path,
                    language: arguments?.language,
                    apply: arguments?.appliesToDisk ?? false
                )
                send(RPCResult(
                    id: request.id,
                    result: CallToolResult.text(
                        formatReplacementPreview(matches, applied: arguments?.appliesToDisk ?? false)
                    )
                ))
            } catch {
                send(RPCResult(
                    id: request.id,
                    result: CallToolResult.text("Error: \(error.localizedDescription)", isError: true)
                ))
            }

        default:
            if let request = decode(ToolCallRequest<EmptyArguments>.self, from: data, id: nil) {
                send(RPCResult(
                    id: request.id,
                    result: CallToolResult.text(
                        "Error: unknown tool '\(probe.params.name)'", isError: true
                    )
                ))
            }
        }
    }

    // MARK: - Wire I/O

    /// Decode with evidence: failures reply `-32700`/`-32602` carrying the
    /// coding path instead of collapsing to a silent nil.
    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, id: RPCID?) -> T? {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            let isHeader = type == RPCRequestHeader.self || type == ToolNameProbe.self
            send(RPCErrorResponse(
                id: id,
                code: isHeader ? .parseError : .invalidParams,
                message: "Invalid request: \(error.brief)"
            ))
            return nil
        } catch {
            send(RPCErrorResponse(id: id, code: .parseError, message: "Parse error"))
            return nil
        }
    }

    private static func send<Response: Encodable>(_ response: Response) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let payload = try encoder.encode(response)
            FileHandle.standardOutput.write(payload)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data(
                "andromeda-mcp: failed to encode response: \(error)\n".utf8
            ))
        }
    }
}
