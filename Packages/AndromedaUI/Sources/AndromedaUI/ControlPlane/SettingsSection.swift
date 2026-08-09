import SwiftUI

// MARK: - Settings (setup / doctor / cleanup / lifecycle)

public enum LifecycleAction { case export, importCfg, uninstall }

/// One doctor probe result — never greenwash: `ok == false` is an honest miss.
public struct DoctorCheck: Identifiable, Sendable, Equatable {
    public var id: String { title }
    public let title: String
    public let ok: Bool
    public let detail: String
    public init(_ title: String, ok: Bool, detail: String = "") {
        self.title = title; self.ok = ok; self.detail = detail
    }
}

/// Injectable doctor probes. Gate 0 ships an unwired default that reports failure,
/// never a fake all-green pass.
public protocol DoctorProbing: Sendable {
    func run() async -> [DoctorCheck]
}

/// Default probe for the design-system package — honest "not wired" results.
public struct UnwiredDoctorProbe: DoctorProbing {
    public init() {}
    public func run() async -> [DoctorCheck] {
        [
            DoctorCheck("Doctor probes wired", ok: false, detail: "No diagnostic service injected yet"),
            DoctorCheck("MemoryKit store reachable", ok: false, detail: "Probe not connected in AndromedaUI"),
            DoctorCheck("MCP host health", ok: false, detail: "Probe not connected in AndromedaUI"),
            DoctorCheck("Env key scrub", ok: false, detail: "Probe not connected in AndromedaUI"),
            DoctorCheck("Autocache gateway", ok: false, detail: "Probe not connected in AndromedaUI"),
        ]
    }
}

public struct SettingsSection: View {
    public var onLifecycle: ((LifecycleAction) -> Void)?
    private let doctorProbe: any DoctorProbing
    public init(
        onLifecycle: ((LifecycleAction) -> Void)? = nil,
        doctorProbe: any DoctorProbing = UnwiredDoctorProbe()
    ) {
        self.onLifecycle = onLifecycle
        self.doctorProbe = doctorProbe
    }
    @State private var doctor = "idle"   // idle · running · done
    @State private var checks: [DoctorCheck] = []

    private let cols = [GridItem(.adaptive(minimum: 280), spacing: 16)]

    public var body: some View {
        LazyVGrid(columns: cols, spacing: 16) {
            setup
            doctorCard
            cleanup
            about
            lifecycle
        }
    }

    private var setup: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                head("Setup", "All-Swift install — no hybrid bash reopen.")
                step("Install LaunchAgents", "7 agents · all-Swift (BIN-101)", true)
                step("Sign & notarize", "Developer ID · hardened runtime", true)
                step("Register menu-bar app", "LSUIElement · non-activating panel", true)
                step("Enable fleet telemetry", "TelemetryHub · opt-in", false)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var doctorCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Doctor").font(AndromedaFont.ui(14, .medium)).foregroundStyle(Color.andromedaInk)
                    Spacer()
                    Button {
                        doctor = "running"
                        checks = []
                        Task { @MainActor in
                            let result = await doctorProbe.run()
                            withAnimation {
                                checks = result
                                doctor = "done"
                            }
                        }
                    } label: {
                        Text(doctor == "running" ? "Running…" : doctor == "done" ? "Re-run" : "Run doctor")
                            .font(AndromedaFont.ui(11, .medium)).foregroundStyle(Color.andromedaGlow)
                            .padding(.horizontal, 13).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.andromedaTeal.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.andromedaTeal.opacity(0.35))))
                    }.buttonStyle(.plain).accessibilityLabel("Run doctor")
                }
                if doctor == "done" {
                    Text("CAVEAT · results reflect the injected probe; Gate 0 default is unwired.")
                        .font(AndromedaFont.mono(10))
                        .foregroundStyle(Color.andromedaAmber)
                    ForEach(checks) { c in
                        check(c.title, c.ok, c.detail)
                    }
                } else {
                    Text("Run doctor to execute real probes (default: unwired → honest failures).")
                        .font(AndromedaFont.ui(12)).foregroundStyle(Color.andromedaMuted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cleanup: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                head("Cleanup", "Reclaim space and tame process sprawl.")
                cleanupRow("Orphan MCP / Playwright procs", "reclaim 3.1 GB · 152 procs", "Sweep")
                cleanupRow("Stale recall cache", "cache older than 30d", "Clear")
                cleanupRow("Rotated telemetry logs", "health.json archive · 240 MB", "Prune")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var about: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("About").font(AndromedaFont.ui(14, .medium)).foregroundStyle(Color.andromedaInk).padding(.bottom, 12)
                aboutRow("version", "0.9.4 (build 1512)")
                aboutRow("channel", "internal")
                aboutRow("pillars live", "3 shipped · 3 partial · 1 spec")
                aboutRow("workspace flip", "NO-GO")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lifecycle: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                head("Config & lifecycle", "Move Andromeda between machines, or remove it cleanly.")
                HStack(spacing: 12) {
                    lifeTile("Export config", "Secret-free bundle for another machine", "square.and.arrow.down", .andromedaTeal) { onLifecycle?(.export) }
                    lifeTile("Import config", "Restore routes, mounts & skills", "square.and.arrow.up", .andromedaTeal) { onLifecycle?(.importCfg) }
                    lifeTile("Remove Andromeda", "Clean, all-Swift uninstall", "trash", Color(red: 1, green: 0.42, blue: 0.42)) { onLifecycle?(.uninstall) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .gridCellColumns(2)
    }

    // helpers
    private func head(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).font(AndromedaFont.ui(14, .medium)).foregroundStyle(Color.andromedaInk)
            Text(s).font(AndromedaFont.ui(12)).foregroundStyle(Color.andromedaMuted)
        }
    }
    private func step(_ n: String, _ note: String, _ done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15)).foregroundStyle(done ? Color.andromedaLive : Color.andromedaAmber)
            VStack(alignment: .leading, spacing: 1) {
                Text(n).font(AndromedaFont.ui(12.5, .medium)).foregroundStyle(Color.andromedaInk)
                Text(note).font(AndromedaFont.mono(10)).foregroundStyle(Color.andromedaMuted)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(n), \(done ? "done" : "pending")")
    }
    private func check(_ n: String, _ ok: Bool, _ warn: String = "") -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13)).foregroundStyle(ok ? Color.andromedaLive : Color.andromedaAmber)
            Text(n).font(AndromedaFont.ui(12.5)).foregroundStyle(Color.andromedaInk)
            Spacer()
            if !warn.isEmpty { Text(warn).font(AndromedaFont.mono(10)).foregroundStyle(Color.andromedaAmber) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(n): \(ok ? "ok" : "warning \(warn)")")
    }
    private func cleanupRow(_ n: String, _ d: String, _ action: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(n).font(AndromedaFont.ui(12.5, .medium)).foregroundStyle(Color.andromedaInk)
                Text(d).font(AndromedaFont.mono(10)).foregroundStyle(Color.andromedaMuted)
            }
            Spacer()
            Text(action).font(AndromedaFont.ui(11, .medium)).foregroundStyle(Color.andromedaMuted)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.andromedaTeal.opacity(0.14)))
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).stroke(Color.andromedaTeal.opacity(0.14)))
    }
    private func aboutRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(AndromedaFont.mono(12)).foregroundStyle(Color.andromedaMuted)
            Spacer()
            Text(v).font(AndromedaFont.ui(12.5, .medium)).foregroundStyle(Color.andromedaInk)
        }
        .padding(.vertical, 9)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.andromedaTeal.opacity(0.14)), alignment: .bottom)
    }
    private func lifeTile(_ t: String, _ s: String, _ sym: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: sym).font(.system(size: 16)).foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.14)))
                Text(t).font(AndromedaFont.ui(13, .medium)).foregroundStyle(color == .andromedaTeal ? Color.andromedaInk : color)
                Text(s).font(AndromedaFont.ui(11)).foregroundStyle(Color.andromedaMuted).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(color == .andromedaTeal ? 0.14 : 0.3)))
        }
        .buttonStyle(.plain).accessibilityLabel(t)
    }
}
