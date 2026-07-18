/**
 * Composition helper: embed `MemoryKitConsoleView` in `AndromedaHUDView`.
 *
 * Lives in MemoryKit so the root `AndromedaHUD` package stays free of a
 * MemoryKit dependency (Linux-safe gateway builds). Product apps import both
 * modules and call `makeAndromedaHUDWithMemoryKit`.
 *
 * Note: This file documents the host pattern; the actual `AndromedaHUDView`
 * generic lives in the Andromeda package. Use the snippet in docs / app target:
 *
 * ```swift
 * let hud = AndromedaHUDModel(showsAccessory: true)
 * let console = MemoryKitConsoleModel.snapshotFixture()
 * AndromedaHUDView(model: hud) {
 *     MemoryKitConsoleView(model: console)
 * }
 * ```
 */

import SwiftUI

/// Factory helpers for product shells that link both AndromedaHUD + MemoryKit.
@MainActor
public enum AndromedaHUDMemoryKitHost {
    /// Recommended accessory: tabbed MemoryKit console.
    public static func makeConsole(
        model: MemoryKitConsoleModel = .snapshotFixture()
    ) -> MemoryKitConsoleView {
        MemoryKitConsoleView(model: model)
    }
}
