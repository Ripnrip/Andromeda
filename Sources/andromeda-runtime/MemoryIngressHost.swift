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
    func write(_ request: LettaIngressRequest) async throws -> LettaIngressReceipt {
        guard let visibility = MemoryVisibility(rawValue: request.visibility) else {
            throw MemoryIngressHostError.visibilityRejected(request.visibility)
        }
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
            relativePath: receipt.relativePath,
            commitSHA: receipt.commitSHA,
            unchanged: receipt.unchanged
        )
    }
}

enum MemoryIngressHostError: LocalizedError {
    case visibilityRejected(String)

    var errorDescription: String? {
        switch self {
        case let .visibilityRejected(value):
            "visibility '\(value)' is not a known cloak tag"
        }
    }
}
