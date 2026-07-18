import Foundation

/// Axis-aligned rectangle used by snap / drag math (portable; no AppKit).
///
/// - Invariants: `width` and `height` are non-negative after `normalized()`.
/// - Concurrency: value type, `Sendable`.
public struct HUDRect: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Origin of the rect (bottom-left in AppKit screen space).
    public var origin: HUDPoint { HUDPoint(x: x, y: y) }

    /// Center point of the rect.
    public var mid: HUDPoint {
        HUDPoint(x: x + width / 2, y: y + height / 2)
    }

    /// Returns a rect with non-negative size (flips negative extents).
    public func normalized() -> HUDRect {
        var copy = self
        if copy.width < 0 {
            copy.x += copy.width
            copy.width = -copy.width
        }
        if copy.height < 0 {
            copy.y += copy.height
            copy.height = -copy.height
        }
        return copy
    }

    /// Whether this rect contains the given point (inclusive edges).
    public func contains(_ point: HUDPoint) -> Bool {
        let n = normalized()
        return point.x >= n.x
            && point.x <= n.x + n.width
            && point.y >= n.y
            && point.y <= n.y + n.height
    }
}

/// 2D point for HUD layout math.
public struct HUDPoint: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Screen metrics used by Ice-style menu-bar snapping (BIN-56).
public struct HUDScreenMetrics: Equatable, Sendable, Codable {
    /// Full display bounds in AppKit global coordinates.
    public var visibleFrame: HUDRect
    /// Height of the menu bar strip above `visibleFrame`.
    public var menuBarHeight: Double
    /// Distance (pt) within which the HUD docks under the menu bar.
    public var snapDistance: Double

    public init(
        visibleFrame: HUDRect,
        menuBarHeight: Double = 24,
        snapDistance: Double = 28
    ) {
        self.visibleFrame = visibleFrame.normalized()
        self.menuBarHeight = max(0, menuBarHeight)
        self.snapDistance = max(0, snapDistance)
    }

    /// Y coordinate of the top edge of the visible frame (just under menu bar).
    public var menuBarDockY: Double {
        visibleFrame.y + visibleFrame.height
    }
}

/// Docking posture for the floating HUD pill.
public enum HUDSnapMode: String, CaseIterable, Equatable, Sendable, Codable {
    /// Freely positioned by the operator.
    case floating
    /// Docked flush under the menu bar (Ice-inspired).
    case menuBar

    public var accessibilityLabel: String {
        switch self {
        case .floating: return "Floating freely"
        case .menuBar: return "Snapped under menu bar"
        }
    }
}

/// Pure geometry helpers for drag + menu-bar snap (BIN-56 / BIN-60).
public enum HUDSnapEngine: Sendable {
    /// Collapsed pill size used when deciding snap targets.
    public static let collapsedSize = HUDPoint(x: 320, y: 52)

    /// Expanded search panel size.
    public static let expandedSize = HUDPoint(x: 420, y: 280)

    /// Resolve snap mode from a proposed origin + screen metrics.
    ///
    /// When the pill's top edge is within `snapDistance` of the menu-bar dock line,
    /// returns `.menuBar`; otherwise `.floating`.
    public static func resolveMode(
        proposedOrigin: HUDPoint,
        size: HUDPoint,
        screen: HUDScreenMetrics
    ) -> HUDSnapMode {
        let topY = proposedOrigin.y + size.y
        let distanceToDock = abs(topY - screen.menuBarDockY)
        if distanceToDock <= screen.snapDistance {
            return .menuBar
        }
        return .floating
    }

    /// Clamp + optionally dock a proposed origin into a legal frame.
    public static func settle(
        proposedOrigin: HUDPoint,
        size: HUDPoint,
        screen: HUDScreenMetrics,
        preferSnap: Bool = true
    ) -> (origin: HUDPoint, mode: HUDSnapMode) {
        let mode: HUDSnapMode
        if preferSnap {
            mode = resolveMode(proposedOrigin: proposedOrigin, size: size, screen: screen)
        } else {
            mode = .floating
        }

        var origin = proposedOrigin
        if mode == .menuBar {
            origin.y = screen.menuBarDockY - size.y
        }

        let frame = screen.visibleFrame
        let minX = frame.x
        let maxX = frame.x + max(0, frame.width - size.x)
        let minY = frame.y
        let maxY = frame.y + max(0, frame.height - size.y)

        origin.x = min(max(origin.x, minX), maxX)
        origin.y = min(max(origin.y, minY), maxY)

        return (origin, mode)
    }

    /// Default centered origin under the menu bar for first launch.
    public static func defaultMenuBarOrigin(
        size: HUDPoint,
        screen: HUDScreenMetrics
    ) -> HUDPoint {
        let x = screen.visibleFrame.x + (screen.visibleFrame.width - size.x) / 2
        let y = screen.menuBarDockY - size.y
        return HUDPoint(x: x, y: y)
    }
}
