import SwiftUI

// MARK: - Animated states
//
// Every specimen in AndromedaUI is a *state machine with a look*, not a
// one-off animation. `MotionState` names the four states the control plane
// can be in; `andromedaMotionActive` lets a host (Xcode preview, snapshot
// test, Reduce Motion) pin looping motion to its end frame so captures are
// deterministic.

/// The four states any Andromeda surface can occupy.
public enum MotionState: String, CaseIterable, Identifiable, Sendable {
    case idle, active, alert, done

    public var id: String { rawValue }
    public var label: String { rawValue }

    public var tint: Color {
        switch self {
        case .idle:   return .andromedaMuted
        case .active: return .andromedaTeal
        case .alert:  return .andromedaAmber
        case .done:   return .andromedaLive
        }
    }

    /// Whether this state should be visibly moving.
    public var isAnimating: Bool { self == .active }
}

// MARK: - Motion environment

private struct MotionActiveKey: EnvironmentKey { static let defaultValue = true }

public extension EnvironmentValues {
    /// When `false`, looping motion is pinned to its end frame — the mode
    /// snapshot tests and Reduce Motion run in.
    var andromedaMotionActive: Bool {
        get { self[MotionActiveKey.self] }
        set { self[MotionActiveKey.self] = newValue }
    }
}

public extension View {
    /// Turn looping motion on or off for this subtree.
    func andromedaMotion(_ active: Bool) -> some View {
        environment(\.andromedaMotionActive, active)
    }

    /// Freeze looping motion at its end frame (deterministic captures).
    func andromedaFrozen() -> some View {
        environment(\.andromedaMotionActive, false)
    }

    /// Apply a looping animation that respects `andromedaMotionActive` and
    /// the system Reduce Motion setting.
    func andromedaLoop<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(AndromedaLoop(animation: animation, value: value))
    }
}

/// Gates a looping animation on the motion environment + Reduce Motion.
public struct AndromedaLoop<V: Equatable>: ViewModifier {
    @Environment(\.andromedaMotionActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let animation: Animation
    private let value: V

    public init(animation: Animation, value: V) {
        self.animation = animation
        self.value = value
    }

    public func body(content: Content) -> some View {
        content.animation((active && !reduceMotion) ? animation : nil, value: value)
    }
}

// MARK: - State matrix

/// Renders one component across a set of states, side by side — the
/// standard `#Preview` and snapshot canvas for anything state-driven.
public struct AndromedaStateMatrix<Content: View>: View {
    private let states: [MotionState]
    private let size: CGSize
    private let content: (MotionState) -> Content

    public init(
        _ states: [MotionState] = MotionState.allCases,
        size: CGSize = CGSize(width: 132, height: 116),
        @ViewBuilder content: @escaping (MotionState) -> Content
    ) {
        self.states = states
        self.size = size
        self.content = content
    }

    public var body: some View {
        HStack(spacing: 10) {
            ForEach(states) { state in
                VStack(spacing: 7) {
                    ZStack {
                        AndromedaSurface()
                        content(state)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(state.tint.opacity(0.28), lineWidth: 1)
                    )
                    Text(state.label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(state.tint)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("state \(state.label)")
            }
        }
        .padding(12)
        .fixedSize()
    }
}

// MARK: - Labeled tile

/// A named specimen tile — used by the gallery walls and composite sheets.
public struct AndromedaTile<Content: View>: View {
    private let title: String
    private let height: CGFloat
    private let content: Content

    public init(_ title: String, height: CGFloat = 118, @ViewBuilder content: () -> Content) {
        self.title = title
        self.height = height
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 7) {
            ZStack { AndromedaSurface(); content }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.andromedaTeal.opacity(0.12)))
            Text(title)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("State matrix") {
    AndromedaStateMatrix { state in
        LivePulse(color: state.tint, size: 20)
            .andromedaMotion(state.isAnimating)
    }
    .preferredColorScheme(.dark)
}
