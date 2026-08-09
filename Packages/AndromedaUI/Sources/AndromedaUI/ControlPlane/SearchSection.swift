import SwiftUI

// MARK: - Ask Andromeda (internal vs external web)

public struct SearchSection: View {
    public init() {}
    @State private var mode = "internal"
    @State private var query = ""
    @State private var phase = "idle"     // idle · loading · ready

    private var internalMode: Bool { mode == "internal" }
    private var accent: Color { internalMode ? .andromedaTeal : .andromedaLive }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                SegTab(label: "Andromeda internals", active: internalMode) { mode = "internal"; phase = "idle" }
                SegTab(label: "External web", active: !internalMode) { mode = "web"; phase = "idle" }
                Spacer()
                Text(internalMode ? "asks the Anima store — never leaves the machine" : "runs against your logged-in web session")
                    .font(AndromedaFont.ui(11.5)).foregroundStyle(Color.andromedaMuted)
            }

            HStack(spacing: 10) {
                Image(systemName: internalMode ? "triangle" : "magnifyingglass").font(.system(size: 15)).foregroundStyle(accent)
                TextField(internalMode ? "Ask about memory, curtain, routing…" : "Ask anything — live web…", text: $query)
                    .textFieldStyle(.plain).font(AndromedaFont.ui(14)).foregroundStyle(Color.andromedaInk)
                    .onSubmit(run)
                Button(action: run) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.andromedaVoid)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                }.buttonStyle(.plain).accessibilityLabel("Run search")
            }
            .padding(.horizontal, 15).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.andromedaTeal.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(phase == "idle" ? Color.andromedaTeal.opacity(0.14) : accent.opacity(0.5))))

            switch phase {
            case "loading": loading
            case "ready": answer
            default: idle
            }
        }
    }

    private func run() {
        withAnimation { phase = "loading" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { phase = "ready" } }
    }

    private var idle: some View {
        VStack(spacing: 8) {
            AndromedaCore(size: 52)
            Text(internalMode ? "Ask Andromeda about itself" : "Real, live web search")
                .font(AndromedaFont.ui(16, .medium)).foregroundStyle(Color.andromedaInk)
            Text(internalMode ? "Grounded in the six-pillar graph, MemoryKit and the control-plane docs — cites internal sources, stays local."
                              : "Ask anything — runs against your logged-in search session, not a scraped shell.")
                .font(AndromedaFont.ui(13)).foregroundStyle(Color.andromedaMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44)
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                ProgressRing().frame(width: 14, height: 14)
                Text(internalMode ? "searching working set + docs…" : "querying live web session…")
                    .font(AndromedaFont.mono(12)).foregroundStyle(accent)
            }
            ForEach([CGFloat(0.94), 0.8, 0.66], id: \.self) { w in
                RecallSkeletonRow(width: 520 * w, delay: 0).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var answer: some View {
        let lead = internalMode
            ? "Recall runs entirely behind the curtain: a client calls memory.recall with a stable id, and Andromeda resolves the index — SwiftData hot store first, then vault and vector recall — ranking hits by salience."
            : "Certificate pinning is a TLS control in which an app accepts a server only if its presented certificate — or its public key — matches a value the app already expects, guarding against man-in-the-middle attacks."
        let steps: [(String, String)] = internalMode
            ? [("1", "The capability id enters the curtain — no store paths or index brands leak to the client."),
               ("2", "MemoryKit ranks candidates by salience across hot store, vault and vector recall."),
               ("3", "Dreaming reflections periodically consolidate and commit updates back.")]
            : [("1", "The app performs ordinary TLS certificate validation."),
               ("2", "It compares the server's certificate or public-key hash against a stored pin."),
               ("3", "If the pin doesn't match it rejects the connection — even when otherwise valid.")]
        let sources = internalMode ? ["MEMORY-ONEPAGER.md", "MemoryKit/recall", "control-plane §1"]
                                   : ["owasp.org", "developer.apple.com", "rfc-editor.org"]
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    badge(internalMode ? "internal" : "pro", accent)
                    badge(internalMode ? "pillar graph" : "web session", .andromedaMuted)
                    Spacer()
                }
                Text(lead).font(AndromedaFont.ui(14.5)).foregroundStyle(Color.andromedaInk).fixedSize(horizontal: false, vertical: true)
                Text(internalMode ? "How it resolves" : "How it works").font(AndromedaFont.mono(12)).foregroundStyle(accent)
                ForEach(steps, id: \.0) { s in
                    HStack(alignment: .top, spacing: 10) {
                        Text(s.0).font(AndromedaFont.mono(12)).foregroundStyle(Color.andromedaMuted)
                        Text(s.1).font(AndromedaFont.ui(13.5)).foregroundStyle(Color.andromedaInk).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().overlay(Color.andromedaTeal.opacity(0.14))
                HStack(spacing: 8) {
                    Text("sources").font(AndromedaFont.mono(11)).foregroundStyle(Color.andromedaMuted)
                    ForEach(Array(sources.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 6) {
                            Text("\(i + 1)").font(AndromedaFont.mono(10)).foregroundStyle(accent)
                            Text(s).font(AndromedaFont.ui(11)).foregroundStyle(Color.andromedaMuted)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().stroke(Color.andromedaTeal.opacity(0.14)))
                    }
                }
            }
        }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(AndromedaFont.mono(10)).foregroundStyle(c)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(c.opacity(0.16)))
    }
}
