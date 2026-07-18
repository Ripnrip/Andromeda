/**
 * Shared modern SwiftUI chrome for MemoryKit panels.
 *
 * Follows swiftui-expert-skill: `@Observable` + `@Bindable`, `.animation(_:value:)`,
 * continuous shapes, ultra-thin materials (Liquid Glass fallback while deployment
 * remains macOS 14 / iOS 17), Pop-inspired springs, Reduce Motion respect.
 *
 * When the package bumps to macOS 26 / iOS 26 SDK, swap `memoryKitPanelChrome`
 * to native `glassEffect` per `references/liquid-glass.md`.
 */

import SwiftUI

// MARK: - Spring tokens (Pop-inspired)

/// Spring recipes for MemoryKit UI — aligned with AndromedaHUD expand/snap feel.
public enum MemoryKitMotion: Sendable {
    /// Panel expand / state change spring.
    public static var panel: Animation {
        .spring(response: 0.32, dampingFraction: 0.82)
    }

    /// Subtle badge / chip updates.
    public static var chip: Animation {
        .spring(response: 0.28, dampingFraction: 0.90)
    }

    /// Reduce-motion safe short fade.
    public static var reduced: Animation {
        .easeInOut(duration: 0.12)
    }

    /// Pick spring vs reduce-motion animation.
    public static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : panel
    }
}

// MARK: - Surface chrome

/// Corner / material tokens shared across CommandCenter, Roster, MCP, ProjectState.
public enum MemoryKitChrome {
    public static let panelCorner: CGFloat = 16
    public static let chipCorner: CGFloat = 10
    public static let pillCorner: CGFloat = 22
}

// MARK: - View modifiers

public extension View {
    /// Apply MemoryKit panel chrome (material + continuous stroke).
    ///
    /// Material path is the skill’s Liquid Glass fallback for pre-26 deployment.
    func memoryKitPanelChrome(
        cornerRadius: CGFloat = MemoryKitChrome.panelCorner
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.04),
                                Color.cyan.opacity(0.07),
                                Color.primary.opacity(0.03),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    /// Soft chip / badge chrome for status rows.
    func memoryKitChipChrome(cornerRadius: CGFloat = MemoryKitChrome.chipCorner) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.45), in: shape)
    }
}

// MARK: - Header atom

/// Reusable panel header — brand glyph + title + tertiary caption.
public struct MemoryKitPanelHeader: View {
    public let title: String
    public let systemImage: String
    public let caption: String
    public let tint: Color
    public let accessibilityIdentifier: String

    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 18

    public init(
        title: String,
        systemImage: String,
        caption: String,
        tint: Color = .cyan,
        accessibilityIdentifier: String
    ) {
        self.title = title
        self.systemImage = systemImage
        self.caption = caption
        self.tint = tint
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.headline)
            Spacer(minLength: 0)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
