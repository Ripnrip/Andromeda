import Foundation

/// Install destination selector for `andromeda-install`.
///
/// Target is **required** (`hud|home|both`) — no silent default to Home.
public enum InstallTarget: String, Sendable, CaseIterable {
    case home
    case hud
    case both

    /// Parses CLI tokens (`home`, `hud`, `both`, plus product-name aliases).
    public static func parse(_ raw: String) throws -> InstallTarget {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "home", "andromedahome":
            return .home
        case "hud", "andromedahud":
            return .hud
        case "both", "all":
            return .both
        default:
            throw InstallError.invalidTarget(raw)
        }
    }

    /// Ordered product installs for this target.
    public var products: [InstallProduct] {
        switch self {
        case .home:
            return [.home]
        case .hud:
            return [.hud]
        case .both:
            return [.home, .hud]
        }
    }

    /// Whether the HUD LaunchAgent should be rendered/bootstrapped after products.
    public var installsHUDLaunchAgent: Bool {
        switch self {
        case .home:
            return false
        case .hud, .both:
            return true
        }
    }
}

/// App product that can be built into `~/Applications/*.app`.
public enum InstallProduct: String, Sendable, CaseIterable {
    case home = "AndromedaHome"
    case hud = "AndromedaHUD"

    public var bundleIdentifier: String {
        switch self {
        case .home: "com.andromeda.home"
        case .hud: "com.andromeda.hud"
        }
    }

    public var displayName: String {
        switch self {
        case .home: "Andromeda Home"
        case .hud: "Andromeda HUD"
        }
    }

    /// Accessory HUD is an LSUIElement; Home is a normal app.
    public var isLSUIElement: Bool {
        switch self {
        case .home: false
        case .hud: true
        }
    }

    /// Home opens via LaunchServices after install; HUD starts only via LaunchAgent.
    public var opensAfterInstall: Bool {
        switch self {
        case .home: true
        case .hud: false
        }
    }
}
