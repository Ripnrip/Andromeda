import AndromedaHTTP
import Foundation
import Logging
import MemoryKit

/// Adapts the git-backed writer into the runtime's brand-free ingress seam.
/// Lives in the serve process — fleet law forbids a second ingress daemon.
struct MemoryIngressHost: LettaIngressHandling {
    private let writer: IngressTelemetryWriter

    init(writer: IngressTelemetryWriter) {
        self.writer = writer
    }

    /// Builds the hosted lane: git writer + os.Logger and JSONL telemetry.
    static func make(logger: Logger) -> MemoryIngressHost {
        let telemetry = MultiplexTelemetryClient(clients: [
            OSLogTelemetryClient(subsystem: "ai.andromeda.runtime", category: "memory-ingress"),
            FileJSONLTelemetryClient(fileName: "memory-ingress.jsonl"),
        ])
        let hosted = LaunchEntity.hostedMemoryIngress()
        logger.info(
            "memory ingress hosted",
            metadata: [
                "label": .string(hosted.label),
                "home": .string(hosted.plistPath),
            ]
        )
        return MemoryIngressHost(
            writer: IngressTelemetryWriter(writer: GitBackedLettaWriter(), telemetry: telemetry)
        )
    }

    /// Maps a curtain request onto a tagged fact. Unknown visibility never reaches git.
    /// Backend receipts keep path/SHA on the host; the MCP curtain only sees opaque ids.
    func write(_ request: LettaIngressRequest) async throws -> LettaIngressReceipt {
        guard let visibility = MemoryVisibility(rawValue: request.visibility) else {
            throw IngressBackendError(errorCode: "visibility_rejected")
        }
        do {
            let receipt = try await writer.write(
                LettaMemoryFact(
                    title: request.title,
                    body: request.body,
                    visibility: visibility,
                    tags: request.tags,
                    source: request.source
                ),
                to: request.agentID
            )
            return LettaIngressReceipt(
                agentID: receipt.agentID,
                unchanged: receipt.unchanged
            )
        } catch let error as LettaIngressError {
            // Paths and git stderr stay local; clients get the telemetry code only.
            throw IngressBackendError(errorCode: error.telemetryCode)
        } catch {
            throw IngressBackendError(errorCode: "ingress_failed")
        }
    }
}
