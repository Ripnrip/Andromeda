import SwiftUI

// MARK: - Shared control-plane building blocks

/// Honesty status pill.
public struct StatusBadge: View {
    public var status: PillarStatus
    public init(_ status: PillarStatus) { self.status = status }
    public var body: some View {
        Text(status.label)
            .font(AndromedaFont.mono(10))
            .foregroundStyle(status.color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(status.color.opacity(0.14)))
            .accessibilityLabel("status \(status.dot)")
    }
}

/// Glass surface card.
public struct GlassCard<Content: View>: View {
    var content: Content
    public init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(Color.andromedaTeal.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.andromedaTeal.opacity(0.14)))
            )
    }
}

/// Little dot + label status inline.
struct DotStatus: View {
    var text: String; var color: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 4)
            Text(text).font(AndromedaFont.mono(10)).foregroundStyle(color)
        }
    }
}

/// Pill-style tab used by scope / model tabs.
struct SegTab: View {
    var label: String; var active: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(AndromedaFont.ui(12, .medium))
                .foregroundStyle(active ? Color.andromedaInk : Color.andromedaMuted)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.andromedaTeal.opacity(0.14) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.andromedaTeal.opacity(0.35) : Color.andromedaTeal.opacity(0.14))))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }
}

/// "＋ Add …" affordance.
struct AddButton: View {
    var label: String; var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                Text(label).font(AndromedaFont.ui(12.5, .medium))
            }
            .foregroundStyle(Color.andromedaGlow)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.andromedaTeal.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.andromedaTeal.opacity(0.35))))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
