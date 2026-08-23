import SwiftUI

/// Shared layout constants for the frosted results panel under the HUD pill.
public enum HUDResultsLayout {
    /// Enough vertical room for ~3–4 memory rows before ScrollView kicks in.
    public static let visibleMinHeight: CGFloat = 132
    /// Cap list height so many hits scroll instead of growing forever.
    public static let contentMaxHeight: CGFloat = 280
}

/// 🌟 Frosted-glass results panel that sits below the HUD search field.
///
/// Appears when `isVisible` is true (results / sync / outcome present).
/// Honors `@Environment(\.accessibilityReduceMotion)` for transitions.
///
/// Layout contract: content drives height (min ~3 rows when visible). Do **not**
/// wrap this in a Capsule — rounded rect material only; list rows must not clip.
@MainActor
public struct HUDResultsView<Content: View>: View {
    public let isVisible: Bool
    @ViewBuilder public let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isVisible: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isVisible = isVisible
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                content()
                    .frame(
                        maxWidth: .infinity,
                        minHeight: HUDResultsLayout.visibleMinHeight,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            )
                    )
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: isVisible ? HUDResultsLayout.visibleMinHeight : 0,
            alignment: .top
        )
        .background {
            if isVisible {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        SurrealBackgroundView()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                    .shadow(
                        color: .black.opacity(reduceMotion ? 0.15 : 0.25),
                        radius: 12,
                        y: 8
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.andromedaLine.opacity(0.5), lineWidth: 1)
                    )
                    .transition(.opacity)
            }
        }
        // Corner-round via the material shape only — do not clipShape the outer
        // container (that squashed list rows + ate the drop shadow).
        .animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
            value: isVisible
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hudResults.container")
    }
}

#if DEBUG
@MainActor
private struct HUDResultsPreviewHelper: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Search Bar Dummy")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))

            HUDResultsView(isVisible: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Result Match 1")
                        .font(.headline)
                    Text("Result Match 2")
                        .font(.subheadline)
                    Text("Result Match 3")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding()
        .frame(width: 320, height: 400)
    }
}

#Preview("HUDResults · visible · light") {
    HUDResultsPreviewHelper()
        .preferredColorScheme(.light)
}

#Preview("HUDResults · visible · dark") {
    HUDResultsPreviewHelper()
        .preferredColorScheme(.dark)
}

#Preview("HUDResults · visible · dark · a11y3") {
    HUDResultsPreviewHelper()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("HUDResults · hidden · reduceMotion") {
    HUDResultsView(isVisible: false) {
        Text("Hidden")
            .padding()
    }
    .frame(width: 320, height: 120)
    .preferredColorScheme(.light)
}
#endif
