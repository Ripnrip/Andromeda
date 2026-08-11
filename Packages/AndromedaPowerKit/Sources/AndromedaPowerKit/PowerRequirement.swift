import Foundation

public struct PowerRequirement: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Keep the Mac awake while allowing displays to sleep.
    public static let preventSystemSleep = Self(rawValue: 1 << 0)

    /// Keep displays awake as well. Reserve this for genuinely interactive
    /// work such as Simulator automation, screenshots, or UI-driving agents.
    public static let preventDisplaySleep = Self(rawValue: 1 << 1)

    public static let none: Self = []
}
